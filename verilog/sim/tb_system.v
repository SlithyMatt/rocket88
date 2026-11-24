// Rocket88 - A New 8-Bit Architecture
// Testbench: tb_system
// Description: The whole computer on the Cyclone IV board top level, running
//              the boot program, with models of the SDRAM, a PS/2 keyboard and
//              a PS/2 mouse
//
// From the verilog directory:
//   iverilog -g2005 -DSIMULATION -o sim/system.vvp sim/tb_system.v sim/sdram_model.v \
//       sim/ps2_device.v c4board.v system/*.v Rocket88.v r88_*.v
//   vvp -n sim/system.vvp [+fullram]
//
// The boot program's RAM test normally covers $0000-$BFFF, which takes about
// a second of simulated time; the testbench shortens it to $0000-$01FF
// unless +fullram is given. Two video frames are written to
// sim/frame_text.ppm and sim/frame_bitmap.ppm.

`timescale 1ns / 100ps

module tb_system;

reg CLOCK_50 = 1'b0;
always #10 CLOCK_50 = ~CLOCK_50;

reg RESET_N = 1'b1;
reg [3:0] KEY = 4'b1111;
wire [3:0] LED, DIG;
wire [7:0] SEG;
wire VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS, BEEP;
wire PS2_KB_CLK, PS2_KB_DAT, PS2_MS_CLK, PS2_MS_DAT;
pullup (PS2_KB_CLK);
pullup (PS2_KB_DAT);
pullup (PS2_MS_CLK);
pullup (PS2_MS_DAT);
wire SDRAM_CLK, SDRAM_CKE, SDRAM_CS_N, SDRAM_RAS_N, SDRAM_CAS_N, SDRAM_WE_N;
wire SDRAM_LDQM, SDRAM_UDQM;
wire [1:0] SDRAM_BA;
wire [11:0] SDRAM_A;
wire [15:0] SDRAM_DQ;

c4board dut (
	.CLOCK_50(CLOCK_50),
	.RESET_N(RESET_N),
	.KEY(KEY),
	.LED(LED),
	.DIG(DIG),
	.SEG(SEG),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.BEEP(BEEP),
	.PS2_KB_CLK(PS2_KB_CLK),
	.PS2_KB_DAT(PS2_KB_DAT),
	.PS2_MS_CLK(PS2_MS_CLK),
	.PS2_MS_DAT(PS2_MS_DAT),
	.SDRAM_CLK(SDRAM_CLK),
	.SDRAM_CKE(SDRAM_CKE),
	.SDRAM_CS_N(SDRAM_CS_N),
	.SDRAM_RAS_N(SDRAM_RAS_N),
	.SDRAM_CAS_N(SDRAM_CAS_N),
	.SDRAM_WE_N(SDRAM_WE_N),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_A(SDRAM_A),
	.SDRAM_LDQM(SDRAM_LDQM),
	.SDRAM_UDQM(SDRAM_UDQM),
	.SDRAM_DQ(SDRAM_DQ)
);

sdram_model sdram (
	.clk(SDRAM_CLK),
	.cke(SDRAM_CKE),
	.cs_n(SDRAM_CS_N),
	.ras_n(SDRAM_RAS_N),
	.cas_n(SDRAM_CAS_N),
	.we_n(SDRAM_WE_N),
	.ba(SDRAM_BA),
	.a(SDRAM_A),
	.dqm({SDRAM_UDQM, SDRAM_LDQM}),
	.dq(SDRAM_DQ)
);

ps2_device #("keyboard") keyboard (.ps2_clk(PS2_KB_CLK), .ps2_dat(PS2_KB_DAT));
ps2_device #("mouse") mouse (.ps2_clk(PS2_MS_CLK), .ps2_dat(PS2_MS_DAT));

// ---------------------------------------------------------------------------
// Checking
// ---------------------------------------------------------------------------
integer checks = 0;
integer failures = 0;

task check;
	input ok;
	input [8*80-1:0] what;
	begin
		checks = checks + 1;
		if (ok !== 1'b1) begin
			failures = failures + 1;
			$display("FAIL: %0s", what);
		end
	end
endtask

function [7:0] text_at;
	input integer row, col;
	text_at = dut.system.video.text_ram[row * 40 + col];
endfunction

function [7:0] color_at;
	input integer row, col;
	color_at = dut.system.video.color_ram[row * 40 + col];
endfunction

// Check that the text at (row, col) starts with s (up to 40 characters)
task check_text;
	input integer row, col;
	input [8*40-1:0] s;
	integer i, len, ok;
	reg [7:0] ch;
	begin
		len = 0;
		for (i = 0; i < 40; i = i + 1) if (s[i*8 +: 8] != 0) len = i + 1;
		ok = 1;
		for (i = 0; i < len; i = i + 1) begin
			ch = s[(len - 1 - i) * 8 +: 8];
			if (text_at(row, col + i) != ch) ok = 0;
		end
		check(ok, s);
		if (!ok) begin
			$write("      row %0d is \"", row);
			for (i = 0; i < 40; i = i + 1) $write("%c", (text_at(row, i) >= 32 && text_at(row, i) < 127) ? text_at(row, i) : "?");
			$display("\"");
		end
	end
endtask

function [7:0] sdram_byte;
	input [15:0] addr;
	reg [15:0] w;
	begin
		w = sdram.mem[addr >> 1];
		sdram_byte = addr[0] ? w[15:8] : w[7:0];
	end
endfunction

task wait_ms;
	input integer ms;
	integer i;
	begin
		for (i = 0; i < ms; i = i + 1) #(1000000);
	end
endtask

task key;
	input [7:0] code;
	begin
		keyboard.send(code);
		keyboard.send(8'hF0);
		keyboard.send(code);
	end
endtask

task mouse_packet;
	input [7:0] flags, dx, dy;
	begin
		mouse.send(flags);
		mouse.send(dx);
		mouse.send(dy);
	end
endtask

// ---------------------------------------------------------------------------
// Shorten the RAM test: "lda b / cpa #$C0 / jpnz" -> "cpa #$02" (3 places)
// ---------------------------------------------------------------------------
integer a, patched = 0;
initial begin
	#1;
	if (!$test$plusargs("fullram")) begin
		for (a = 0; a < 4093; a = a + 1) begin
			if (dut.system.boot_ram[a] == 8'h12 && dut.system.boot_ram[a+1] == 8'h1C &&
					dut.system.boot_ram[a+2] == 8'hC0 && dut.system.boot_ram[a+3] == 8'h54) begin
				dut.system.boot_ram[a+2] = 8'h02;
				patched = patched + 1;
			end
		end
		if (patched != 3) $display("FAIL: found %0d of the 3 RAM test limits to shorten", patched);
	end
end

// ---------------------------------------------------------------------------
// Video capture and sync timing
// ---------------------------------------------------------------------------
reg [2:0] frame_buf [0:640*480-1];
integer px = 0, py = 0;
integer capture = 0;					// 1: capture the next frame, 2: capturing
integer blank_errors = 0;
real hs_fall = 0, hs_rise = 0, vs_fall = 0, vs_rise = 0;
real hs_period = 0, hs_width = 0, vs_period = 0, vs_width = 0;

always @(negedge VGA_HS) begin
	if (hs_fall > 0) hs_period = $realtime - hs_fall;
	hs_fall = $realtime;
	px = -96;
	py = py + 1;
end
always @(posedge VGA_HS) begin
	hs_rise = $realtime;
	hs_width = hs_rise - hs_fall;
end
always @(negedge VGA_VS) begin
	if (vs_fall > 0) vs_period = $realtime - vs_fall;
	vs_fall = $realtime;
	py = -2 - 33;
	if (capture == 2) capture = 3;
	if (capture == 1) capture = 2;
end
always @(posedge VGA_VS) vs_width = $realtime - vs_fall;

// Each pixel lasts two clocks; the outputs change when pe was high
always @(negedge CLOCK_50) begin
	if (!dut.system.video.pe) begin
		if (px >= 48 && px < 48 + 640 && py >= 0 && py < 480) begin
			if (capture == 2) frame_buf[py * 640 + px - 48] = {VGA_R, VGA_G, VGA_B};
		end else if ({VGA_R, VGA_G, VGA_B} != 3'b000) begin
			blank_errors = blank_errors + 1;
		end
		px = px + 1;
	end
end

task capture_frame;
	input [8*64-1:0] file;
	integer f, i;
	begin
		capture = 1;
		wait (capture == 3);
		capture = 0;
		f = $fopen(file, "w");
		$fwrite(f, "P3\n640 480\n1\n");
		for (i = 0; i < 640 * 480; i = i + 1)
			$fwrite(f, "%0d %0d %0d\n", frame_buf[i][2], frame_buf[i][1], frame_buf[i][0]);
		$fclose(f);
	end
endtask

function [2:0] pixel;
	input integer x, y;
	pixel = frame_buf[y * 640 + x];
endfunction

// Progress, and an optional time limit (+stopms=N)
integer stop_ms = 0, ms = 0;
integer frame_pulses = 0, irq_acks = 0;
initial begin
	if (!$value$plusargs("stopms=%d", stop_ms)) stop_ms = 0;
	forever begin
		#(10000000);
		ms = ms + 10;
		$display("  %0d ms", ms);
		$fflush;
		if (stop_ms != 0 && ms >= stop_ms) begin
			$display("stopped at %0d ms", ms);
			$finish;
		end
	end
end

// Frame pulses and interrupt acknowledgements: one each per frame
always @(posedge dut.clk) begin
	if (dut.system.frame) frame_pulses = frame_pulses + 1;
	if (dut.system.io_write && dut.system.io_reg == 8'h30) irq_acks = irq_acks + 1;
end
// Every SDRAM read must return what the model holds
integer read_errors = 0;
reg [15:0] chk_addr;
always @(posedge dut.clk) begin
	if (dut.system.phase == 4'd10 && dut.system.req_read && dut.system.req_region == 2'd0
			&& dut.system.req_addr < 16'h8000) begin
		chk_addr = dut.system.req_addr;
		if (dut.system.sdram_rdata !== sdram_byte(chk_addr)) begin
			read_errors = read_errors + 1;
			if (read_errors <= 10)
				$display("READ MISMATCH at %0t: $%h read %h, memory has %h", $time, chk_addr,
					dut.system.sdram_rdata, sdram_byte(chk_addr));
		end
	end
end

// Sound activity
integer beep_edges = 0;
always @(negedge BEEP) beep_edges = beep_edges + 1;

// ---------------------------------------------------------------------------
// The test
// ---------------------------------------------------------------------------
integer t, frames_before, edges_before, i, acks_before, pulses_before;
reg [7:0] font_row;

initial begin
	$display("Booting...");
	// Wait for the mouse to be told to start reporting, after the screen is drawn
	t = 0;
	while (mouse.received_count == 0 && t < 2000) begin
		wait_ms(1);
		t = t + 1;
	end
	$display("Boot screen up after %0d ms", t);

	check_text(0, 0, "ROCKET88 COMPUTER");
	check_text(1, 0, "64K RAM, 8 colors, 4 voices");
	check_text(3, 0, "RAM $0000-$BFFF OK");
	check_text(5, 0, "Type on the keyboard. Move the mouse:");
	check_text(9, 0, "KEY3 clear    KEY4 colors");
	check(text_at(11, 0) == 8'h7F, "cursor at row 11");
	check(color_at(11, 0) == 8'h97, "cursor blinks");
	check(color_at(0, 0) == 8'h17, "white on blue");
	check(text_at(12, 20) == 8'h1F, "mouse pointer at (20, 12)");
	check(dut.system.border == 3'd3, "cyan border");

	wait_ms(2);
	check(mouse.received_count == 1 && mouse.received[0] == 8'hF4, "mouse received $F4");

	// Type "Hi": shift down, h, shift up, i
	keyboard.send(8'h12);
	key(8'h33);
	keyboard.send(8'hF0);
	keyboard.send(8'h12);
	key(8'h43);
	wait_ms(3);
	check_text(11, 0, "Hi");
	check(text_at(11, 2) == 8'h7F, "cursor after Hi");
	check(color_at(11, 0) == 8'h17 && color_at(11, 2) == 8'h97, "cursor blink moved");
	check(dut.system.hex_reg == 16'h69F0 || dut.system.hex_reg == 16'h6943, "display shows the last key");
	check(dut.system.sound.freq[0] == 16'h0348 && dut.system.sound.freq[1] == 16'h0690, "click pitch from the key");
	edges_before = beep_edges;
	wait_ms(5);
	check(beep_edges - edges_before > 100, "speaker is driven");

	// Enter, then x and backspace
	key(8'h5A);
	key(8'h22);
	wait_ms(3);
	check(text_at(12, 0) == "x" && text_at(12, 1) == 8'h7F, "x on the next line");
	key(8'h66);
	wait_ms(3);
	check(text_at(12, 0) == 8'h7F && text_at(12, 1) == " ", "backspace");

	// Mouse: right 8, down 4 -> cell (22, 13)
	mouse_packet(8'h08, 8'h08, 8'hFC);
	wait_ms(3);
	check(text_at(13, 22) == 8'h1F, "pointer moved to (22, 13)");
	check(text_at(12, 20) == " ", "old pointer cell restored");
	// Left button and right 4: leaves a block
	mouse_packet(8'h09, 8'h04, 8'h00);
	wait_ms(3);
	check(text_at(13, 22) == 8'h7F && text_at(13, 23) == 8'h1F, "left button draws");
	wait_ms(40);
	check(LED == 4'b1110 || LED == 4'b0110, "LED1 shows the left button");
	mouse_packet(8'h08, 8'hFC, 8'h00);
	wait_ms(3);
	check(text_at(13, 22) == 8'h1F && text_at(13, 23) == " ", "pointer moved back left");

	// Frame interrupts are counted in RAM
	frames_before = sdram_byte(16'h0010);
	acks_before = irq_acks;
	pulses_before = frame_pulses;
	wait_ms(50);
	check(irq_acks - acks_before == frame_pulses - pulses_before, "one interrupt per frame");
	check(sdram_byte(16'h0010) - frames_before >= 2 && sdram_byte(16'h0010) - frames_before <= 4,
		"frame interrupt at 60 Hz");

	// Video timing
	check(hs_period > 31990 && hs_period < 32010, "line period 32 us");
	check(hs_width > 3830 && hs_width < 3850, "hsync 96 pixels");
	check(vs_period > 16799000 && vs_period < 16801000, "frame period 16.8 ms");
	check(vs_width > 63990 && vs_width < 64010, "vsync 2 lines");

	// A frame of text
	capture_frame("sim/frame_text.ppm");
	check(blank_errors == 0, "no color outside the picture");
	check(pixel(0, 0) == 3'b011 && pixel(639, 39) == 3'b011, "border is cyan");
	// 'R' at the top left: its top row is .#####..
	font_row = 8'b01111100;
	t = 1;
	for (i = 0; i < 16; i = i + 1)
		if (pixel(i, 40) != (font_row[7 - i/2] ? 3'b111 : 3'b001)) t = 0;
	check(t, "R drawn white on blue");
	check(pixel(0, 440) == 3'b011, "border below the picture");

	// KEY1: bitmap mode
	KEY[0] = 1'b0;
	wait_ms(2);
	KEY[0] = 1'b1;
	wait_ms(2);
	check(dut.system.bitmap_mode == 1'b1, "KEY1 selects bitmap mode");
	capture_frame("sim/frame_bitmap.ppm");
	// Bitmap byte (row y, column c) is c*8 ^ y; check rows 0 and 9 of column 5
	t = 1;
	for (i = 0; i < 16; i = i + 1) begin
		font_row = 8'd40;
		if (pixel(80 + i, 40) != (font_row[7 - i/2] ? 3'b111 : 3'b001)) t = 0;
		font_row = 8'd40 ^ 8'd9;
		if (pixel(80 + i, 40 + 18) != (font_row[7 - i/2] ? 3'b111 : 3'b001)) t = 0;
	end
	check(t, "bitmap pattern");

	// KEY2: border color
	KEY[1] = 1'b0;
	wait_ms(2);
	KEY[1] = 1'b1;
	wait_ms(2);
	check(dut.system.border == 3'd4, "KEY2 changes the border");

	// 7-segment display: digit 0 is the low nibble of the last scan code
	wait (dut.digit == 2'd0);
	#100;
	check(DIG == 4'b1110 && SEG == {1'b1, ~dut.segments} && dut.nibble == dut.hex_value[3:0],
		"7-segment display");

	// SDRAM and PS/2 protocol
	check(sdram.errors == 0, "SDRAM timing and protocol");
	check(read_errors == 0, "SDRAM reads return the stored data");
	check(sdram.max_refresh_gap < 16000.0, "SDRAM refreshed every 15.6 us");
	check(sdram.refreshes > 1000, "SDRAM refreshes counted");
	check(keyboard.errors == 0 && mouse.errors == 0, "PS/2 frames");
	check(dut.system.keyboard.error == 1'b0 && dut.system.mouse.error == 1'b0, "PS/2 ports report no errors");

	$display("%0d checks, %0d failures, %0.1f ms simulated", checks, failures, $realtime / 1000000.0);
	if (failures == 0) $display("PASS");
	else $display("FAIL");
	$finish;
end

endmodule
