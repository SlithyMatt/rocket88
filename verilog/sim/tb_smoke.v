// Rocket88 - A New 8-Bit Architecture
// Testbench: tb_smoke
// Description: Runs system/examples/smoke_test.asm on the Cyclone IV board
//              top level and checks the color bars, the tone on each key
//              press and the display
//
// From the repository root:
//   python3 tools/build_system_roms.py verilog/system/examples/smoke_test.asm
//   cp verilog/system/boot.mem verilog/sim/smoke_test.mem
//   python3 tools/build_system_roms.py
// then from the verilog directory:
//   iverilog -g2005 -DSIMULATION -o sim/smoke.vvp sim/tb_smoke.v sim/sdram_model.v \
//       sim/ps2_device.v c4board.v system/*.v Rocket88.v r88_*.v
//   vvp -n sim/smoke.vvp +boot=sim/smoke_test.mem
//
// A frame is written to sim/frame_smoke.ppm.

`timescale 1ns / 100ps

module tb_smoke;

reg CLOCK_50 = 1'b0;
always #10 CLOCK_50 = ~CLOCK_50;

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
	.CLOCK_50(CLOCK_50), .RESET_N(1'b1), .KEY(KEY), .LED(LED), .DIG(DIG), .SEG(SEG),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS),
	.BEEP(BEEP),
	.PS2_KB_CLK(PS2_KB_CLK), .PS2_KB_DAT(PS2_KB_DAT),
	.PS2_MS_CLK(PS2_MS_CLK), .PS2_MS_DAT(PS2_MS_DAT),
	.SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE), .SDRAM_CS_N(SDRAM_CS_N),
	.SDRAM_RAS_N(SDRAM_RAS_N), .SDRAM_CAS_N(SDRAM_CAS_N), .SDRAM_WE_N(SDRAM_WE_N),
	.SDRAM_BA(SDRAM_BA), .SDRAM_A(SDRAM_A), .SDRAM_LDQM(SDRAM_LDQM),
	.SDRAM_UDQM(SDRAM_UDQM), .SDRAM_DQ(SDRAM_DQ)
);

sdram_model sdram (
	.clk(SDRAM_CLK), .cke(SDRAM_CKE), .cs_n(SDRAM_CS_N), .ras_n(SDRAM_RAS_N),
	.cas_n(SDRAM_CAS_N), .we_n(SDRAM_WE_N), .ba(SDRAM_BA), .a(SDRAM_A),
	.dqm({SDRAM_UDQM, SDRAM_LDQM}), .dq(SDRAM_DQ)
);

ps2_device #("keyboard") keyboard (.ps2_clk(PS2_KB_CLK), .ps2_dat(PS2_KB_DAT));

// Load the smoke test into the boot RAM in place of the boot program
reg [8*256-1:0] boot_file;
initial begin
	#1;
	if ($value$plusargs("boot=%s", boot_file)) $readmemh(boot_file, dut.system.boot_ram);
	else begin
		$display("usage: +boot=<smoke_test image>");
		$finish;
	end
end

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

function [7:0] var_at;		// the smoke test's variables in the boot RAM
	input [15:0] addr;
	var_at = dut.system.boot_ram[addr - 16'hF000];
endfunction

task wait_ms;
	input integer ms;
	integer i;
	begin
		for (i = 0; i < ms; i = i + 1) #(1000000);
	end
endtask

// ---------------------------------------------------------------------------
// Video capture (see tb_system.v)
// ---------------------------------------------------------------------------
reg [2:0] frame_buf [0:640*480-1];
integer px = 0, py = 0;
integer capture = 0;

always @(negedge VGA_HS) begin
	px = -96;
	py = py + 1;
end
always @(negedge VGA_VS) begin
	py = -2 - 33;
	if (capture == 2) capture = 3;
	if (capture == 1) capture = 2;
end
always @(negedge CLOCK_50) begin
	if (!dut.system.video.pe) begin
		if (capture == 2 && px >= 48 && px < 48 + 640 && py >= 0 && py < 480)
			frame_buf[py * 640 + px - 48] = {VGA_R, VGA_G, VGA_B};
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

integer beep_edges = 0;
always @(negedge BEEP) beep_edges = beep_edges + 1;

// ---------------------------------------------------------------------------
// The test
// ---------------------------------------------------------------------------
reg [2:0] bar_colors [0:7];
integer t, i, ok, frames_before, edges_before, white;

initial begin
	bar_colors[0] = 3'd7;	// white
	bar_colors[1] = 3'd6;	// yellow
	bar_colors[2] = 3'd3;	// cyan
	bar_colors[3] = 3'd2;	// green
	bar_colors[4] = 3'd5;	// magenta
	bar_colors[5] = 3'd4;	// red
	bar_colors[6] = 3'd1;	// blue
	bar_colors[7] = 3'd0;	// black

	// Wait for the title, which is drawn last
	t = 0;
	while (text_at(24, 1) !== "P" && t < 100) begin
		wait_ms(1);
		t = t + 1;
	end
	wait_ms(1);
	$display("Screen drawn after %0d ms", t);
	check(text_at(23, 1) == "R" && text_at(23, 10) == "S" && text_at(24, 1) == "P", "title text");

	capture_frame("sim/frame_smoke.ppm");
	ok = 1;
	for (i = 0; i < 8; i = i + 1) begin
		// Each bar is 5 cells (80 screen pixels) wide; check its middle at
		// the top, middle and bottom of the bars (picture lines 0-183)
		if (pixel(i * 80 + 40, 40) != bar_colors[i]) ok = 0;
		if (pixel(i * 80 + 40, 200) != bar_colors[i]) ok = 0;
		if (pixel(i * 80 + 40, 40 + 183 * 2) != bar_colors[i]) ok = 0;
		if (pixel(i * 80 + 2, 200) != bar_colors[i] || pixel(i * 80 + 77, 200) != bar_colors[i]) ok = 0;
	end
	check(ok, "8 color bars: white, yellow, cyan, green, magenta, red, blue, black");
	check(pixel(0, 0) == 3'd0 && pixel(639, 479) == 3'd0, "black border");
	white = 0;
	for (i = 0; i < 640; i = i + 1) if (pixel(i, 40 + 184 * 2 + 2) == 3'd7) white = white + 1;
	check(white > 20 && pixel(0, 40 + 184 * 2) == 3'd0, "title drawn white on black");

	// The frame counter runs (LED4 blinks from it)
	frames_before = var_at(16'hFD02);
	wait_ms(50);
	check(var_at(16'hFD02) - frames_before >= 2 && var_at(16'hFD02) - frames_before <= 4,
		"frame counter at 60 Hz");
	check(dut.system.sound.volume[0] == 0 && LED[0] == 1'b1, "silent before a key");
	check(dut.system.hex_reg == 16'h0000 && dut.system.hex_enable, "display reads 0000 at boot");

	// Press and release 'A' (scan code $1C)
	keyboard.send(8'h1C);
	wait_ms(1);
	check(dut.system.sound.volume[0] == 15 && dut.system.sound.freq[0] == 16'd590
		&& dut.system.sound.wave[0] == 2'd0, "key press plays a 440 Hz square wave");
	check(dut.system.hex_reg == 16'h0028, "display shows scan code 28 (decimal)");
	edges_before = beep_edges;
	wait_ms(20);
	check(beep_edges - edges_before > 100, "speaker is driven");
	check(LED[0] == 1'b0, "LED1 on during the tone");
	keyboard.send(8'hF0);
	keyboard.send(8'h1C);
	wait_ms(1);
	check(dut.system.hex_reg == 16'h0028, "key release doesn't change the display");

	// The tone stops after 15 frames
	wait_ms(250);
	check(dut.system.sound.volume[0] == 0, "tone stops after a quarter second");
	check(LED[0] == 1'b1, "LED1 off after the tone");
	edges_before = beep_edges;
	wait_ms(5);
	check(beep_edges == edges_before, "speaker quiet after the tone");

	// An extended key (up arrow: $E0 $75) also plays the tone
	keyboard.send(8'hE0);
	keyboard.send(8'h75);
	wait_ms(1);
	check(dut.system.sound.volume[0] == 15 && dut.system.hex_reg == 16'h0117, "extended key, shown as 0117");
	keyboard.send(8'hF0);
	keyboard.send(8'h75);

	// More decimal conversions: F7 ($83), Backspace ($66), F9 ($01), F3 ($04), Esc ($76)
	keyboard.send(8'h83);
	wait_ms(1);
	check(dut.system.hex_reg == 16'h0131, "scan code 83 shown as 0131");
	keyboard.send(8'h66);
	wait_ms(1);
	check(dut.system.hex_reg == 16'h0102, "scan code 66 shown as 0102");
	keyboard.send(8'h01);
	wait_ms(1);
	check(dut.system.hex_reg == 16'h0001, "scan code 01 shown as 0001");
	keyboard.send(8'h76);
	wait_ms(1);
	check(dut.system.hex_reg == 16'h0118, "scan code 76 shown as 0118");

	check(sdram.errors == 0, "SDRAM timing and protocol");
	check(keyboard.errors == 0 && dut.system.keyboard.error == 1'b0, "PS/2 frames");

	$display("%0d checks, %0d failures, %0.1f ms simulated", checks, failures, $realtime / 1000000.0);
	if (failures == 0) $display("PASS");
	else $display("FAIL");
	$finish;
end

endmodule
