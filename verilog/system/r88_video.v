// Rocket88 - A New 8-Bit Architecture
// Module: r88_video
// Description: VGA video controller with text and bitmap modes
// See https://github.com/SlithyMatt/rocket88 for current code and documentation
//
// Outputs 640x480 at 60 Hz (25 MHz pixel clock, from a 50 MHz clock) with
// 8 colors. The picture is 320x200, with each pixel doubled to 640x400, and a
// 40-line border above and below it.
//
// Video memory, in the CPU's address space (cpu_addr is the full address):
//   $C000-$DFFF  Bitmap: 320x200, 1 bit per pixel, 40 bytes per row, the
//                leftmost pixel in bit 7 (8000 bytes; $DF40-$DFFF is spare)
//   $E000-$E3FF  Text: 40x25 character codes, row by row (1000 bytes)
//   $E400-$E7FF  Color: one byte for each 8x8 cell (1000 bytes)
//                bits 2-0 foreground, bits 6-4 background, bit 7 blink
//   $E800-$EFFF  Font: 256 characters, 8 bytes each, top row first,
//                the leftmost pixel in bit 7
//
// Colors are 3 bits: bit 2 red, bit 1 green, bit 0 blue.
// In text mode, each cell shows its character from the font. In bitmap mode,
// each pixel shows the foreground color of its cell if set, else background.

module r88_video (
	input clk,							// 50 MHz
	input reset,

	// CPU port. Reads and writes use the address registered at the edge
	// before; read data appears one clock after the address.
	input [15:0] cpu_addr,
	input [7:0] cpu_wdata,
	input cpu_we,						// write this clock
	output reg [7:0] cpu_rdata,

	input bitmap_mode,
	input [2:0] border,

	output reg [2:0] rgb = 3'b000,
	output reg hsync = 1'b1,		// active low
	output reg vsync = 1'b1,		// active low
	output [9:0] line,				// current line, 0-524 (0-479 visible)
	output reg frame = 1'b0			// pulses at the end of the picture (line 440)
);

// ---------------------------------------------------------------------------
// Memories: port A for the CPU, port B for the display
// ---------------------------------------------------------------------------
reg [7:0] bitmap_ram [0:8191];
reg [7:0] text_ram [0:1023];
reg [7:0] color_ram [0:1023];
reg [7:0] font_ram [0:2047];

initial begin
	$readmemh("system/font.mem", font_ram);
end

wire sel_bitmap = (cpu_addr[15:13] == 3'b110);
wire sel_text   = (cpu_addr[15:10] == 6'b111000);
wire sel_color  = (cpu_addr[15:10] == 6'b111001);
wire sel_font   = (cpu_addr[15:11] == 5'b11101);

reg [7:0] bitmap_qa, text_qa, color_qa, font_qa;
reg [1:0] rsel = 2'd0;

always @(posedge clk) begin
	if (cpu_we && sel_bitmap) bitmap_ram[cpu_addr[12:0]] <= cpu_wdata;
	bitmap_qa <= bitmap_ram[cpu_addr[12:0]];
end
always @(posedge clk) begin
	if (cpu_we && sel_text) text_ram[cpu_addr[9:0]] <= cpu_wdata;
	text_qa <= text_ram[cpu_addr[9:0]];
end
always @(posedge clk) begin
	if (cpu_we && sel_color) color_ram[cpu_addr[9:0]] <= cpu_wdata;
	color_qa <= color_ram[cpu_addr[9:0]];
end
always @(posedge clk) begin
	if (cpu_we && sel_font) font_ram[cpu_addr[10:0]] <= cpu_wdata;
	font_qa <= font_ram[cpu_addr[10:0]];
end

always @(posedge clk) rsel <= sel_bitmap ? 2'd0 : sel_text ? 2'd1 : sel_color ? 2'd2 : 2'd3;
always @(*) begin
	case (rsel)
		2'd0: cpu_rdata = bitmap_qa;
		2'd1: cpu_rdata = text_qa;
		2'd2: cpu_rdata = color_qa;
		default: cpu_rdata = font_qa;
	endcase
end

// ---------------------------------------------------------------------------
// Timing: 800 x 525 pixels per frame at 25 MHz
// ---------------------------------------------------------------------------
// The data for each 16-pixel group (one 8-pixel cell, doubled) is fetched
// while the group before it is shown, so the picture starts at h = 16 and the
// syncs are placed relative to that.
localparam H_START = 10'd16;					// first visible pixel
localparam H_END   = 10'd656;					// after the last visible pixel
localparam HS_START = 10'd672;				// 16 pixels of front porch
localparam HS_END  = 10'd768;					// 96 pixels of sync, then 48 of back porch
localparam H_TOTAL = 10'd800;
localparam V_END   = 10'd480;
localparam VS_START = 10'd490;
localparam VS_END  = 10'd492;
localparam V_TOTAL = 10'd525;
localparam PIC_TOP = 10'd40;					// first line of the 320x200 picture
localparam PIC_END = 10'd440;

reg pe = 1'b0;									// pixel clock enable
reg [9:0] h = 10'd0;
reg [9:0] v = 10'd0;
assign line = v;

wire in_picture = (v >= PIC_TOP) && (v < PIC_END);
wire [8:0] pic_y = v[8:0] - PIC_TOP[8:0];
wire [7:0] y = pic_y[8:1];						// picture row, 0-199
wire [5:0] fetch_col = h[9:4];				// cell being fetched, 0-39

// Display addresses: cells are 40 per row
wire [9:0] cell_addr = {y[7:3], 5'b0} + {2'b0, y[7:3], 3'b0} + {4'b0, fetch_col};
wire [12:0] bitmap_addr = {y, 5'b0} + {2'b0, y, 3'b0} + {7'b0, fetch_col};

reg [7:0] bitmap_qb, text_qb, color_qb, font_qb;
reg [10:0] font_addr = 11'd0;
always @(posedge clk) bitmap_qb <= bitmap_ram[bitmap_addr];
always @(posedge clk) text_qb <= text_ram[cell_addr];
always @(posedge clk) color_qb <= color_ram[cell_addr];
always @(posedge clk) font_qb <= font_ram[font_addr];

reg [7:0] next_pixels = 8'd0, pixels = 8'd0;
reg [7:0] next_color = 8'd0, color = 8'd0;
reg [5:0] blink = 6'd0;

wire [2:0] fg = (color[7] && blink[5]) ? color[6:4] : color[2:0];
wire pixel = pixels[~h[3:1]];

always @(posedge clk) begin
	pe <= ~pe;
	frame <= 1'b0;
	if (reset) begin
		h <= 10'd0;
		v <= 10'd0;
	end else if (pe) begin
		// Counters
		if (h == H_TOTAL - 10'd1) begin
			h <= 10'd0;
			if (v == V_TOTAL - 10'd1) v <= 10'd0;
			else v <= v + 10'd1;
			if (v == PIC_END - 10'd1) begin
				frame <= 1'b1;
				blink <= blink + 6'd1;
			end
		end else begin
			h <= h + 10'd1;
		end

		// Fetch: addresses are set from h at the start of the group, the
		// character and color arrive 2 pixels later, and the font byte 2 after that
		if (h[3:0] == 4'd2) font_addr <= {text_qb, y[2:0]};
		if (h[3:0] == 4'd4) begin
			next_pixels <= bitmap_mode ? bitmap_qb : font_qb;
			next_color <= color_qb;
		end
		if (h[3:0] == 4'd15) begin
			pixels <= next_pixels;
			color <= next_color;
		end

		// Outputs
		hsync <= ~((h >= HS_START) && (h < HS_END));
		vsync <= ~((v >= VS_START) && (v < VS_END));
		if ((h < H_START) || (h >= H_END) || (v >= V_END)) rgb <= 3'b000;
		else if (!in_picture) rgb <= border;
		else rgb <= pixel ? fg : color[6:4];
	end
end

endmodule
