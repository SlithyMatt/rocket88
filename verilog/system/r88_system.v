// Rocket88 - A New 8-Bit Architecture
// Module: r88_system
// Description: Rocket88 computer: CPU, memory map, video, sound, PS/2 and board I/O
// See https://github.com/SlithyMatt/rocket88 for current code and documentation
//
// This module is independent of the board; the board's top level connects
// it to the pins (see c4board.v). The memory map and registers are
// described in system/README.md.
//
// Clocking: everything runs on one 50 MHz clock. The CPU is clocked by
// cpu_clk, which is that clock divided by 16 (3.125 MHz, so 1.5625 MHz per
// two-step cycle). Each CPU clock period is a 16-clock bus slot, counted by
// phase, with the CPU clock rising as phase goes from 15 to 0:
//
//   4 -> 5    the CPU's address, Read, Write and data are latched (they
//             have had 5 clocks to settle); SDRAM ACTIVE is issued
//   5 -> 6    writes to on-chip memory and I/O registers
//   6 -> 7    SDRAM READ or WRITE
//   10 -> 11  read data is latched for the CPU, along with the IRQ and
//             RESET inputs, so they have 5 clocks to settle before the CPU
//             clock rises; reads of I/O registers take effect here
//   11 -> 12  SDRAM refresh, when one is due

module r88_system (
	input clk,							// 50 MHz
	input reset,						// power-on / PLL not locked (active high)
	input reset_button_n,			// restarts the CPU (active low)

	// SDRAM
	output sdram_cke,
	output sdram_cs_n,
	output sdram_ras_n,
	output sdram_cas_n,
	output sdram_we_n,
	output [1:0] sdram_ba,
	output [11:0] sdram_a,
	output [1:0] sdram_dqm,
	inout [15:0] sdram_dq,

	// Video
	output [2:0] vga_rgb,			// bit 2 red, bit 1 green, bit 0 blue
	output vga_hsync,
	output vga_vsync,

	// Sound
	output audio_pwm,					// high to drive the speaker

	// PS/2 keyboard and mouse (open drain: *_low pulls the line low)
	input kbd_clk_in,
	input kbd_dat_in,
	output kbd_clk_low,
	output kbd_dat_low,
	input mouse_clk_in,
	input mouse_dat_in,
	output mouse_clk_low,
	output mouse_dat_low,

	// Board I/O
	input [3:0] keys,					// pressed = 1
	output [3:0] leds,				// on = 1
	output [15:0] hex_value,		// value for a 4-digit hex display
	output hex_enable
);

// ---------------------------------------------------------------------------
// Bus slot and CPU clock
// ---------------------------------------------------------------------------
reg [3:0] phase = 4'd0;
reg cpu_clk_r = 1'b0;
wire [3:0] next_phase = phase + 4'd1;
always @(posedge clk) begin
	phase <= next_phase;
	cpu_clk_r <= ~next_phase[3];		// high for phases 0-7
end

// ---------------------------------------------------------------------------
// CPU
// ---------------------------------------------------------------------------
wire [7:0] cpu_d;
wire [15:0] cpu_a;
wire cpu_read, cpu_write;
reg [7:0] rdata = 8'h00;
reg cpu_reset_n = 1'b0;
reg cpu_irq_n = 1'b1;

// The core drives the data bus while writing; otherwise it reads rdata
assign cpu_d = cpu_write ? 8'bz : rdata;

Rocket88 cpu (
	.extD(cpu_d),
	.readMem(cpu_read),
	.writeMem(cpu_write),
	.resetReq(cpu_reset_n),
	.nmiReq(1'b1),
	.irq(cpu_irq_n),
	.sysClock(cpu_clk_r),
	.extA(cpu_a)
);

// ---------------------------------------------------------------------------
// Memory map
// ---------------------------------------------------------------------------
//   $0000-$BFFF  SDRAM (48 KB; $8000-$BFFF is a window onto any 16 KB bank)
//   $C000-$EFFF  video memory (on-chip)
//   $F000-$FFFF  boot RAM (on-chip, loaded with system/boot.mem), except
//   $FE00-$FEFF  I/O registers
localparam R_SDRAM = 2'd0, R_VIDEO = 2'd1, R_BOOT = 2'd2, R_IO = 2'd3;

function [1:0] region;
	input [15:0] a;
	begin
		if (a[15:14] != 2'b11) region = R_SDRAM;
		else if (a[15:12] != 4'hF) region = R_VIDEO;
		else if (a[15:8] == 8'hFE) region = R_IO;
		else region = R_BOOT;
	end
endfunction

reg [7:0] bank = 8'd0;				// 16 KB SDRAM bank shown at $8000-$BFFF

// SDRAM byte address: $0000-$7FFF are fixed; bank n at $8000 is SDRAM page
// n+2, so bank 0 makes $0000-$BFFF one flat 48 KB.
function [22:0] sdram_addr;
	input [15:0] a;
	input [7:0] b;
	begin
		if (!a[15]) sdram_addr = {8'd0, a[14:0]};
		else sdram_addr = {({1'b0, b} + 9'd2), a[13:0]};
	end
endfunction

// Bus request, latched at phase 4 -> 5
reg [15:0] req_addr = 16'h0000;
reg [7:0] req_wdata = 8'h00;
reg req_read = 1'b0;
reg req_write = 1'b0;
reg [1:0] req_region = R_SDRAM;

always @(posedge clk) begin
	if (phase == 4'd4) begin
		req_addr <= cpu_a;
		req_wdata <= cpu_d;
		req_read <= cpu_read && cpu_reset_n;
		req_write <= cpu_write && cpu_reset_n;
		req_region <= region(cpu_a);
	end
end

wire write_now = (phase == 4'd5) && req_write;	// write at 5 -> 6
wire read_now = (phase == 4'd10) && req_read;	// read at 10 -> 11

// ---------------------------------------------------------------------------
// SDRAM
// ---------------------------------------------------------------------------
wire sdram_ready;
wire [7:0] sdram_rdata;

r88_sdram sdram (
	.clk(clk),
	.reset(reset),
	.phase(phase),
	.start((cpu_read || cpu_write) && cpu_reset_n && (region(cpu_a) == R_SDRAM)),
	.we(cpu_write),
	.addr(sdram_addr(cpu_a, bank)),
	.wdata(cpu_d),
	.rdata(sdram_rdata),
	.ready(sdram_ready),
	.sdram_cke(sdram_cke),
	.sdram_cs_n(sdram_cs_n),
	.sdram_ras_n(sdram_ras_n),
	.sdram_cas_n(sdram_cas_n),
	.sdram_we_n(sdram_we_n),
	.sdram_ba(sdram_ba),
	.sdram_a(sdram_a),
	.sdram_dqm(sdram_dqm),
	.sdram_dq(sdram_dq)
);

// ---------------------------------------------------------------------------
// Boot RAM: $F000-$FFFF, loaded when the FPGA is configured
// ---------------------------------------------------------------------------
reg [7:0] boot_ram [0:4095];
reg [7:0] boot_q;
initial $readmemh("system/boot.mem", boot_ram);
always @(posedge clk) begin
	if (write_now && req_region == R_BOOT) boot_ram[req_addr[11:0]] <= req_wdata;
	boot_q <= boot_ram[req_addr[11:0]];
end

// ---------------------------------------------------------------------------
// Video
// ---------------------------------------------------------------------------
reg bitmap_mode = 1'b0;
reg [2:0] border = 3'd0;
wire [7:0] video_rdata;
wire [9:0] video_line;
wire frame;

r88_video video (
	.clk(clk),
	.reset(reset),
	.cpu_addr(req_addr),
	.cpu_wdata(req_wdata),
	.cpu_we(write_now && req_region == R_VIDEO),
	.cpu_rdata(video_rdata),
	.bitmap_mode(bitmap_mode),
	.border(border),
	.rgb(vga_rgb),
	.hsync(vga_hsync),
	.vsync(vga_vsync),
	.line(video_line),
	.frame(frame)
);

// ---------------------------------------------------------------------------
// I/O registers
// ---------------------------------------------------------------------------
wire io_write = write_now && req_region == R_IO;
wire io_read = read_now && req_region == R_IO;
wire [7:0] io_reg = req_addr[7:0];

// Reset for the I/O registers: power-on, or the reset button
reg [2:0] button_sync = 3'b111;
always @(posedge clk) button_sync <= {button_sync[1:0], reset_button_n};
wire button = ~button_sync[2];
wire io_reset = reset | button;

// PS/2 ports
wire [7:0] kbd_rx, mouse_rx;
wire kbd_ready, mouse_ready, kbd_busy, mouse_busy, kbd_error, mouse_error;

r88_ps2 keyboard (
	.clk(clk),
	.reset(io_reset),
	.ps2_clk_in(kbd_clk_in),
	.ps2_dat_in(kbd_dat_in),
	.ps2_clk_low(kbd_clk_low),
	.ps2_dat_low(kbd_dat_low),
	.rx_data(kbd_rx),
	.rx_ready(kbd_ready),
	.rx_pop(io_read && io_reg == 8'h10),
	.tx_data(req_wdata),
	.tx_start(io_write && io_reg == 8'h10),
	.tx_busy(kbd_busy),
	.error(kbd_error),
	.clear_error(io_write && io_reg == 8'h11)
);

r88_ps2 mouse (
	.clk(clk),
	.reset(io_reset),
	.ps2_clk_in(mouse_clk_in),
	.ps2_dat_in(mouse_dat_in),
	.ps2_clk_low(mouse_clk_low),
	.ps2_dat_low(mouse_dat_low),
	.rx_data(mouse_rx),
	.rx_ready(mouse_ready),
	.rx_pop(io_read && io_reg == 8'h12),
	.tx_data(req_wdata),
	.tx_start(io_write && io_reg == 8'h12),
	.tx_busy(mouse_busy),
	.error(mouse_error),
	.clear_error(io_write && io_reg == 8'h13)
);

// Sound: $FE20-$FE2F
r88_sound sound (
	.clk(clk),
	.reset(io_reset),
	.reg_addr(io_reg[3:0]),
	.reg_data(req_wdata),
	.reg_write(io_write && io_reg[7:4] == 4'h2),
	.pwm(audio_pwm)
);

// Interrupts: bit 0 frame (end of the picture), bit 1 keyboard data,
// bit 2 mouse data. The frame bit is latched until cleared by writing a 1.
reg frame_flag = 1'b0;
reg [2:0] irq_enable = 3'd0;
wire [2:0] irq_status = {mouse_ready, kbd_ready, frame_flag};

// Board I/O
reg [3:0] led_reg = 4'd0;
reg [15:0] hex_reg = 16'h0000;
reg [1:0] hex_ctrl = 2'b01;			// bit 0 display on, bit 1 show address bus
reg [15:0] last_addr = 16'h0000;		// last address the CPU read or wrote
reg [2:0] key_sync0 = 3'b000, key_sync1 = 3'b000, key_sync2 = 3'b000, key_sync3 = 3'b000;
wire [3:0] key_state = {key_sync3[2], key_sync2[2], key_sync1[2], key_sync0[2]};
always @(posedge clk) begin
	key_sync0 <= {key_sync0[1:0], keys[0]};
	key_sync1 <= {key_sync1[1:0], keys[1]};
	key_sync2 <= {key_sync2[1:0], keys[2]};
	key_sync3 <= {key_sync3[1:0], keys[3]};
end

assign leds = led_reg;
assign hex_value = hex_ctrl[1] ? last_addr : hex_reg;
assign hex_enable = hex_ctrl[0];

always @(posedge clk) begin
	if (frame) frame_flag <= 1'b1;
	if (phase == 4'd5 && (req_read || req_write)) last_addr <= req_addr;

	if (io_reset) begin
		bitmap_mode <= 1'b0;
		border <= 3'd0;
		irq_enable <= 3'd0;
		frame_flag <= 1'b0;
		led_reg <= 4'd0;
		hex_reg <= 16'h0000;
		hex_ctrl <= 2'b01;
		bank <= 8'd0;
	end else if (io_write) begin
		case (io_reg)
			8'h00: bitmap_mode <= req_wdata[0];
			8'h01: border <= req_wdata[2:0];
			8'h30: if (req_wdata[0]) frame_flag <= 1'b0;
			8'h31: irq_enable <= req_wdata[2:0];
			8'h40: led_reg <= req_wdata[3:0];
			8'h42: hex_reg[7:0] <= req_wdata;
			8'h43: hex_reg[15:8] <= req_wdata;
			8'h44: hex_ctrl <= req_wdata[1:0];
			8'h48: bank <= req_wdata;
			default: ;
		endcase
	end
end

reg [7:0] io_rdata;
always @(*) begin
	case (io_reg)
		8'h00: io_rdata = {7'd0, bitmap_mode};
		8'h01: io_rdata = {5'd0, border};
		8'h02: io_rdata = video_line[7:0];
		8'h03: io_rdata = {6'd0, video_line[9:8]};
		8'h10: io_rdata = kbd_rx;
		8'h11: io_rdata = {5'd0, kbd_error, kbd_busy, kbd_ready};
		8'h12: io_rdata = mouse_rx;
		8'h13: io_rdata = {5'd0, mouse_error, mouse_busy, mouse_ready};
		8'h30: io_rdata = {5'd0, irq_status};
		8'h31: io_rdata = {5'd0, irq_enable};
		8'h40: io_rdata = {4'd0, led_reg};
		8'h41: io_rdata = {4'd0, key_state};
		8'h42: io_rdata = hex_reg[7:0];
		8'h43: io_rdata = hex_reg[15:8];
		8'h44: io_rdata = {6'd0, hex_ctrl};
		8'h48: io_rdata = bank;
		default: io_rdata = 8'h00;
	endcase
end

// ---------------------------------------------------------------------------
// Read data, IRQ and reset for the CPU, latched at phase 10 -> 11
// ---------------------------------------------------------------------------
always @(posedge clk) begin
	if (phase == 4'd10) begin
		if (req_read) begin
			case (req_region)
				R_SDRAM: rdata <= sdram_rdata;
				R_VIDEO: rdata <= video_rdata;
				R_BOOT:  rdata <= boot_q;
				default: rdata <= io_rdata;
			endcase
		end
		cpu_irq_n <= ~|(irq_status & irq_enable);
		cpu_reset_n <= sdram_ready && !button;
	end
end

endmodule
