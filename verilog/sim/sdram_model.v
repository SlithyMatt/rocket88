// Rocket88 - A New 8-Bit Architecture
// Testbench model: sdram_model
// Description: Behavioral 4-bank x 4096-row x 256-column x 16-bit SDRAM
//              (HY57V641620-like) that checks the controller's timing
//
// Pin delays are modeled so that the controller's -3 ns SDRAM clock phase
// is checked the way it will work on the board: the clock reaches the chip
// CLK_DELAY after the FPGA's PLL output, commands and write data CMD_DELAY
// after the FPGA clock edge, and read data reaches the FPGA DQ_DELAY after
// the chip drives it.
//
// Any timing or protocol violation is printed as "SDRAM ERROR" and counted
// in errors.

`timescale 1ns / 100ps

module sdram_model #(
	parameter real CLK_DELAY = 3.0,		// PLL output pin and trace
	parameter real CMD_DELAY = 4.0,		// FPGA output register to SDRAM pin
	parameter real DQ_DELAY = 1.0,		// SDRAM pin to FPGA input register
	parameter real T_AC = 5.4,				// access time from clock, CL 2
	parameter real T_OH = 2.7				// data hold after the next clock
) (
	input clk,
	input cke,
	input cs_n,
	input ras_n,
	input cas_n,
	input we_n,
	input [1:0] ba,
	input [11:0] a,
	input [1:0] dqm,
	inout [15:0] dq
);

// Signals as seen at the chip
wire #(CLK_DELAY) ck = clk;
wire #(CMD_DELAY) cs_d = cs_n;
wire #(CMD_DELAY) ras_d = ras_n;
wire #(CMD_DELAY) cas_d = cas_n;
wire #(CMD_DELAY) we_d = we_n;
wire [1:0] #(CMD_DELAY) ba_d = ba;
wire [11:0] #(CMD_DELAY) a_d = a;
wire [1:0] #(CMD_DELAY) dqm_d = dqm;
wire [15:0] #(CMD_DELAY) dq_d = dq;

reg [15:0] mem [0:(1 << 22) - 1];

reg drive = 1'b0;
reg [15:0] dout = 16'h0000;
assign #(DQ_DELAY) dq = drive ? dout : 16'bz;

integer errors = 0;
integer cycle = 0;
integer refreshes = 0;
real last_refresh = 0.0;
real max_refresh_gap = 0.0;
real power_on;

reg mode_set = 1'b0;
integer refreshes_before_mode = 0;
reg precharged_all = 1'b0;
reg [11:0] row [0:3];
reg [3:0] open_bank = 4'b0000;
integer act_cycle [0:3];				// cycle of the last ACTIVE in each bank
integer idle_cycle [0:3];				// first cycle each bank can be activated
integer refresh_done = 0;				// first cycle after tRFC
integer rd_pending = 0;					// a READ was registered at the last edge
reg [15:0] rd_data;

localparam T_RCD = 1, T_RAS = 3, T_RP = 1, T_WR = 2, T_RC = 4, T_RFC = 4;

task fail;
	input [8*64-1:0] msg;
	begin
		errors = errors + 1;
		if (errors <= 20) $display("SDRAM ERROR at %0t ns: %0s", $time, msg);
	end
endtask

integer i;
initial begin
	power_on = $realtime;
	for (i = 0; i < 4; i = i + 1) begin
		act_cycle[i] = -100;
		idle_cycle[i] = 0;
		row[i] = 12'h000;
	end
end

wire [21:0] word = {ba_d, row[ba_d], a_d[7:0]};

always @(posedge ck) begin
	cycle = cycle + 1;

	// CAS latency 2: read data for a READ at the last edge is driven tAC
	// after this edge and held until tOH after the next one
	if (rd_pending == 1) begin
		dout <= #(T_AC) rd_data;
		drive <= #(T_AC) 1'b1;
		rd_pending = 0;
	end else if (drive) begin
		drive <= #(T_OH) 1'b0;
	end

	if (!cs_d && cke && {ras_d, cas_d, we_d} != 3'b111) begin
		if ($realtime - power_on < 100000.0) fail("command during the 100 us power-up wait");
		if (cycle < refresh_done) fail("command during tRFC");
		case ({ras_d, cas_d, we_d})
			3'b011: begin	// ACTIVE
				if (!mode_set) fail("ACTIVE before the mode register is set");
				if (open_bank[ba_d]) fail("ACTIVE to an open bank");
				if (cycle < idle_cycle[ba_d]) fail("ACTIVE before precharge finished (tRP/tRC)");
				open_bank[ba_d] = 1'b1;
				row[ba_d] = a_d;
				act_cycle[ba_d] = cycle;
			end
			3'b101, 3'b100: begin	// READ, WRITE
				if (!open_bank[ba_d]) fail("READ/WRITE to a closed bank");
				if (cycle - act_cycle[ba_d] < T_RCD + 1) fail("READ/WRITE before tRCD");
				if (!a_d[10]) fail("READ/WRITE without auto precharge");
				if (we_d) begin
					rd_data = mem[word];
					rd_pending = 1;
					idle_cycle[ba_d] = (act_cycle[ba_d] + T_RAS > cycle + 1 ? act_cycle[ba_d] + T_RAS : cycle + 1) + T_RP;
				end else begin
					if (!dqm_d[0]) mem[word][7:0] = dq_d[7:0];
					if (!dqm_d[1]) mem[word][15:8] = dq_d[15:8];
					if (^dq_d === 1'bx) fail("WRITE data is not driven");
					idle_cycle[ba_d] = (act_cycle[ba_d] + T_RAS > cycle + T_WR ? act_cycle[ba_d] + T_RAS : cycle + T_WR) + T_RP;
				end
				if (idle_cycle[ba_d] < act_cycle[ba_d] + T_RC) idle_cycle[ba_d] = act_cycle[ba_d] + T_RC;
				open_bank[ba_d] = 1'b0;
			end
			3'b010: begin	// PRECHARGE
				if (a_d[10]) begin
					precharged_all = 1'b1;
					open_bank = 4'b0000;
				end else begin
					open_bank[ba_d] = 1'b0;
				end
			end
			3'b001: begin	// AUTO REFRESH
				if (!precharged_all) fail("REFRESH before PRECHARGE ALL");
				if (open_bank != 4'b0000) fail("REFRESH with an open bank");
				for (i = 0; i < 4; i = i + 1)
					if (cycle < idle_cycle[i]) fail("REFRESH before precharge finished");
				refresh_done = cycle + T_RFC;
				if (mode_set) begin
					if ($realtime - last_refresh > max_refresh_gap)
						max_refresh_gap = $realtime - last_refresh;
				end else begin
					refreshes_before_mode = refreshes_before_mode + 1;
				end
				last_refresh = $realtime;
				refreshes = refreshes + 1;
			end
			3'b000: begin	// LOAD MODE REGISTER
				if (refreshes_before_mode < 2) fail("mode set before 2 refreshes");
				if (a_d[6:4] != 3'd2) fail("CAS latency is not 2");
				if (a_d[2:0] != 3'd0) fail("burst length is not 1");
				if (open_bank != 4'b0000) fail("mode set with an open bank");
				mode_set = 1'b1;
				last_refresh = $realtime;
			end
		endcase
	end
end

endmodule
