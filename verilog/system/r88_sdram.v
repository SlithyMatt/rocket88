// Rocket88 - A New 8-Bit Architecture
// Module: r88_sdram
// Description: SDRAM controller for the Rocket88 system
// See https://github.com/SlithyMatt/rocket88 for current code and documentation
//
// Drives a 4-bank x 4096-row x 256-column x 16-bit SDRAM (8 MB, such as the
// HY57V641620 or K4S641632) at 50 MHz, CAS latency 2, burst length 1.
//
// The controller runs on the system's 16-clock bus slot (see r88_system.v)
// and does at most one byte access per slot, with auto precharge, so every
// access takes the same time:
//
//   phase 4 -> 5   ACTIVE (when start is high)
//   phase 6 -> 7   READ or WRITE, with auto precharge
//   phase 9 -> 10  read data captured in the input register (rdata is valid
//                  during phase 10, for the system to latch at 10 -> 11)
//   phase 11 -> 12 AUTO REFRESH, when one is due
//
// Each "a -> b" is the clock edge where the phase changes from a to b.
// sdram_clk must lead clk by about 3 ns (see r88_pll.v) so that command
// setup and hold, and the read data window, are centered on clk edges.

module r88_sdram (
	input clk,
	input reset,					// restarts initialization (active high)
	input [3:0] phase,			// bus slot phase
	input start,					// begin an access at the next edge (phase 4 only)
	input we,						// write (1) or read (0)
	input [22:0] addr,			// byte address
	input [7:0] wdata,
	output [7:0] rdata,			// read data, valid during phase 10
	output reg ready = 1'b0,	// initialization is complete

	output sdram_cke,
	output reg sdram_cs_n = 1'b1,
	output reg sdram_ras_n = 1'b1,
	output reg sdram_cas_n = 1'b1,
	output reg sdram_we_n = 1'b1,
	output reg [1:0] sdram_ba = 2'b00,
	output reg [11:0] sdram_a = 12'h000,
	output reg [1:0] sdram_dqm = 2'b11,	// {UDQM, LDQM}
	inout [15:0] sdram_dq
);

// Commands: {CS_n, RAS_n, CAS_n, WE_n}
localparam CMD_NOP       = 4'b0111;
localparam CMD_ACTIVE    = 4'b0011;
localparam CMD_READ      = 4'b0101;
localparam CMD_WRITE     = 4'b0100;
localparam CMD_PRECHARGE = 4'b0010;
localparam CMD_REFRESH   = 4'b0001;
localparam CMD_MODE      = 4'b0000;

// Mode register: write burst = programmed length, CAS latency 2,
// sequential, burst length 1
localparam MODE = 12'b00_0_00_010_0_000;

// 64 ms / 4096 rows = 15.6 us; refresh every 15 us (750 clocks at 50 MHz)
localparam REFRESH_INTERVAL = 10'd750;

// Power-up wait: 200 us (10000 clocks at 50 MHz)
localparam INIT_WAIT = 14'd10000;

assign sdram_cke = 1'b1;

reg [15:0] dq_out = 16'h0000;
reg dq_oe = 1'b0;
reg [15:0] dq_in = 16'h0000;
assign sdram_dq = dq_oe ? dq_out : 16'bz;

// Input register, captured every clock (packed into the I/O cell)
always @(posedge clk) dq_in <= sdram_dq;

reg hi_byte = 1'b0;			// the access is to the upper byte of the word
assign rdata = hi_byte ? dq_in[15:8] : dq_in[7:0];

task command;
	input [3:0] cmd;
	begin
		{sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} <= cmd;
	end
endtask

// Initialization sequence
reg [13:0] init_count = 14'd0;
reg [4:0] init_step = 5'd0;

// Access and refresh state
reg active = 1'b0;			// an access is in progress in this slot
reg write = 1'b0;
reg [7:0] col = 8'h00;
reg [7:0] data = 8'h00;
reg [9:0] refresh_count = 10'd0;
reg refresh_due = 1'b0;

always @(posedge clk) begin
	command(CMD_NOP);
	dq_oe <= 1'b0;

	if (reset) begin
		ready <= 1'b0;
		init_count <= 14'd0;
		init_step <= 5'd0;
		active <= 1'b0;
		refresh_due <= 1'b0;
		refresh_count <= 10'd0;
		sdram_dqm <= 2'b11;
	end else if (!ready) begin
		// Wait, precharge all banks, 8 auto refreshes, load the mode register.
		// Each step waits 8 clocks, which covers tRP, tRFC and tMRD.
		if (init_count != 14'd0) begin
			init_count <= init_count - 14'd1;
		end else begin
			init_step <= init_step + 5'd1;
			init_count <= 14'd7;
			case (init_step)
				5'd0: init_count <= INIT_WAIT;
				5'd1: begin
					command(CMD_PRECHARGE);
					sdram_a[10] <= 1'b1;			// all banks
				end
				5'd2, 5'd3, 5'd4, 5'd5, 5'd6, 5'd7, 5'd8, 5'd9:
					command(CMD_REFRESH);
				5'd10: begin
					command(CMD_MODE);
					sdram_ba <= 2'b00;
					sdram_a <= MODE;
				end
				5'd11: begin
					// Start in step with the bus slot
					if (phase == 4'd15) begin
						ready <= 1'b1;
						sdram_dqm <= 2'b00;
					end else begin
						init_step <= init_step;
						init_count <= 14'd0;
					end
				end
				default: ;
			endcase
		end
	end else begin
		if (refresh_count == REFRESH_INTERVAL) begin
			refresh_count <= 10'd0;
			refresh_due <= 1'b1;
		end else begin
			refresh_count <= refresh_count + 10'd1;
		end

		case (phase)
			4'd4: if (start) begin
				// ACTIVE: bank = addr[22:21], row = addr[20:9]
				command(CMD_ACTIVE);
				sdram_ba <= addr[22:21];
				sdram_a <= addr[20:9];
				col <= addr[8:1];
				hi_byte <= addr[0];
				write <= we;
				data <= wdata;
				active <= 1'b1;
			end
			4'd6: if (active) begin
				// READ or WRITE with auto precharge (A10)
				command(write ? CMD_WRITE : CMD_READ);
				sdram_a <= {1'b0, 1'b1, 2'b00, col};
				if (write) begin
					dq_out <= {data, data};
					dq_oe <= 1'b1;
					sdram_dqm <= hi_byte ? 2'b01 : 2'b10;	// mask the other byte
				end else begin
					sdram_dqm <= 2'b00;
				end
			end
			4'd7: begin
				active <= 1'b0;
				sdram_dqm <= 2'b00;
			end
			4'd11: if (refresh_due) begin
				command(CMD_REFRESH);
				refresh_due <= 1'b0;
			end
			default: ;
		endcase
	end
end

endmodule
