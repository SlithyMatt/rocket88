// Rocket88 - A New 8-Bit Architecture
// Module: c4board
// Description: Top level for the Rocket88 computer on the Cyclone IV EP4CE6
//              development board ("Altera Cyclone IV board V3.0", sold as
//              OMDAZZ / RZ-EasyFPGA A2.2 and similar)
// See https://github.com/SlithyMatt/rocket88 for current code and documentation
//
// Board documentation: https://github.com/SlithyMatt/Altera-Cyclone-IV-board-V3.0
// Pin assignments are in Rocket88.qsf, timing constraints in Rocket88.sdc.
//
//   RESET button    restarts the CPU (the boot RAM and SDRAM keep their contents)
//   KEY1-KEY4       readable at $FE41
//   LED1-LED4       set by $FE40
//   4-digit display shows $FE42-$FE43 in hex, or the address bus
//   VGA             8 colors (the board has one bit per color)
//   Speaker         4-voice sound
//   PS/2 port       keyboard
//   PS2_MS_*        a second PS/2 port for a mouse, wired to the expansion
//                   header (see Rocket88.qsf)

module c4board (
	input CLOCK_50,
	input RESET_N,

	input [3:0] KEY,				// active low
	output [3:0] LED,				// active low
	output [3:0] DIG,				// digit select, active low; DIG[0] is the rightmost
	output [7:0] SEG,				// segments a-g, dp, active low

	output VGA_R,
	output VGA_G,
	output VGA_B,
	output VGA_HS,
	output VGA_VS,

	output BEEP,					// speaker, active low

	inout PS2_KB_CLK,
	inout PS2_KB_DAT,
	inout PS2_MS_CLK,
	inout PS2_MS_DAT,

	output SDRAM_CLK,
	output SDRAM_CKE,
	output SDRAM_CS_N,
	output SDRAM_RAS_N,
	output SDRAM_CAS_N,
	output SDRAM_WE_N,
	output [1:0] SDRAM_BA,
	output [11:0] SDRAM_A,
	output SDRAM_LDQM,
	output SDRAM_UDQM,
	inout [15:0] SDRAM_DQ
);

wire clk;
wire locked;

r88_pll pll (
	.inclk(CLOCK_50),
	.clk(clk),
	.sdram_clk(SDRAM_CLK),
	.locked(locked)
);

// Hold everything in reset until the PLL has locked
reg [2:0] lock_sync = 3'b000;
always @(posedge clk) lock_sync <= {lock_sync[1:0], locked};
wire reset = ~lock_sync[2];

wire [2:0] rgb;
wire audio;
wire kbd_clk_low, kbd_dat_low, mouse_clk_low, mouse_dat_low;
wire [3:0] leds;
wire [15:0] hex_value;
wire hex_enable;

r88_system system (
	.clk(clk),
	.reset(reset),
	.reset_button_n(RESET_N),
	.sdram_cke(SDRAM_CKE),
	.sdram_cs_n(SDRAM_CS_N),
	.sdram_ras_n(SDRAM_RAS_N),
	.sdram_cas_n(SDRAM_CAS_N),
	.sdram_we_n(SDRAM_WE_N),
	.sdram_ba(SDRAM_BA),
	.sdram_a(SDRAM_A),
	.sdram_dqm({SDRAM_UDQM, SDRAM_LDQM}),
	.sdram_dq(SDRAM_DQ),
	.vga_rgb(rgb),
	.vga_hsync(VGA_HS),
	.vga_vsync(VGA_VS),
	.audio_pwm(audio),
	.kbd_clk_in(PS2_KB_CLK),
	.kbd_dat_in(PS2_KB_DAT),
	.kbd_clk_low(kbd_clk_low),
	.kbd_dat_low(kbd_dat_low),
	.mouse_clk_in(PS2_MS_CLK),
	.mouse_dat_in(PS2_MS_DAT),
	.mouse_clk_low(mouse_clk_low),
	.mouse_dat_low(mouse_dat_low),
	.keys(~KEY),
	.leds(leds),
	.hex_value(hex_value),
	.hex_enable(hex_enable)
);

assign {VGA_R, VGA_G, VGA_B} = rgb;
assign BEEP = ~audio;
assign LED = ~leds;

// Open-drain PS/2 lines
assign PS2_KB_CLK = kbd_clk_low ? 1'b0 : 1'bz;
assign PS2_KB_DAT = kbd_dat_low ? 1'b0 : 1'bz;
assign PS2_MS_CLK = mouse_clk_low ? 1'b0 : 1'bz;
assign PS2_MS_DAT = mouse_dat_low ? 1'b0 : 1'bz;

// ---------------------------------------------------------------------------
// 4-digit 7-segment display, scanned at 760 Hz per digit
// ---------------------------------------------------------------------------
reg [17:0] scan = 18'd0;
always @(posedge clk) scan <= scan + 18'd1;
wire [1:0] digit = scan[17:16];
wire [3:0] nibble = hex_value[{digit, 2'b00} +: 4];

reg [6:0] segments;			// gfedcba, 1 = lit
always @(*) begin
	case (nibble)
		4'h0: segments = 7'b0111111;
		4'h1: segments = 7'b0000110;
		4'h2: segments = 7'b1011011;
		4'h3: segments = 7'b1001111;
		4'h4: segments = 7'b1100110;
		4'h5: segments = 7'b1101101;
		4'h6: segments = 7'b1111101;
		4'h7: segments = 7'b0000111;
		4'h8: segments = 7'b1111111;
		4'h9: segments = 7'b1101111;
		4'hA: segments = 7'b1110111;
		4'hB: segments = 7'b1111100;
		4'hC: segments = 7'b0111001;
		4'hD: segments = 7'b1011110;
		4'hE: segments = 7'b1111001;
		default: segments = 7'b1110001;
	endcase
end

assign SEG = {1'b1, ~segments};
assign DIG = hex_enable ? ~(4'b0001 << digit) : 4'b1111;

endmodule
