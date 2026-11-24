// Rocket88 - A New 8-Bit Architecture
// Module: r88_sound
// Description: Four-voice sound generator with PWM output
// See https://github.com/SlithyMatt/rocket88 for current code and documentation
//
// Each voice has a 16-bit frequency, a 4-bit volume and a waveform (square,
// sawtooth, triangle or noise). The voices are updated at 48828 Hz (50 MHz /
// 1024), so a voice plays at frequency * 0.745 Hz: a frequency value of
// 590 is A440. The mixed 8-bit sample is output as PWM at 195 kHz.
//
// Registers (reg_addr), 4 per voice:
//   4n+0  frequency low byte
//   4n+1  frequency high byte
//   4n+2  volume, 0-15 (bits 3-0)
//   4n+3  waveform (bits 1-0): 0 = square, 1 = sawtooth, 2 = triangle, 3 = noise

module r88_sound (
	input clk,
	input reset,
	input [3:0] reg_addr,
	input [7:0] reg_data,
	input reg_write,
	output reg pwm = 1'b0				// high to drive the speaker
);

reg [15:0] freq [0:3];
reg [3:0] volume [0:3];
reg [1:0] wave [0:3];
reg [15:0] phase_acc [0:3];
reg [16:0] lfsr [0:3];

integer i;
initial begin
	for (i = 0; i < 4; i = i + 1) begin
		freq[i] = 16'd0;
		volume[i] = 4'd0;
		wave[i] = 2'd0;
		phase_acc[i] = 16'd0;
		lfsr[i] = 17'h1FFFF;
	end
end

// Register writes
always @(posedge clk) begin
	if (reset) begin
		for (i = 0; i < 4; i = i + 1) begin
			volume[i] <= 4'd0;
			freq[i] <= 16'd0;
			wave[i] <= 2'd0;
		end
	end else if (reg_write) begin
		case (reg_addr[1:0])
			2'd0: freq[reg_addr[3:2]][7:0] <= reg_data;
			2'd1: freq[reg_addr[3:2]][15:8] <= reg_data;
			2'd2: volume[reg_addr[3:2]] <= reg_data[3:0];
			2'd3: wave[reg_addr[3:2]] <= reg_data[1:0];
		endcase
	end
end

// Waveform of each voice, 0-255
function [7:0] waveform;
	input [1:0] w;
	input [15:0] acc;
	input [16:0] noise;
	begin
		case (w)
			2'd0: waveform = acc[15] ? 8'hFF : 8'h00;
			2'd1: waveform = acc[15:8];
			2'd2: waveform = acc[15] ? ~acc[14:7] : acc[14:7];
			default: waveform = noise[7:0];
		endcase
	end
endfunction

wire [11:0] level0 = waveform(wave[0], phase_acc[0], lfsr[0]) * volume[0];
wire [11:0] level1 = waveform(wave[1], phase_acc[1], lfsr[1]) * volume[1];
wire [11:0] level2 = waveform(wave[2], phase_acc[2], lfsr[2]) * volume[2];
wire [11:0] level3 = waveform(wave[3], phase_acc[3], lfsr[3]) * volume[3];
wire [13:0] mix = level0 + level1 + level2 + level3;

// Sample clock and voice update
reg [9:0] tick = 10'd0;
reg [7:0] sample = 8'd0;
reg [16:0] next_acc;
always @(posedge clk) begin
	tick <= tick + 10'd1;
	if (tick == 10'd0) begin
		for (i = 0; i < 4; i = i + 1) begin
			next_acc = {1'b0, phase_acc[i]} + {1'b0, freq[i]};
			phase_acc[i] <= next_acc[15:0];
			// Noise steps each time the accumulator passes half way
			if (phase_acc[i][15] != next_acc[15])
				lfsr[i] <= {lfsr[i][15:0], lfsr[i][16] ^ lfsr[i][13]};
		end
		// Two voices at full volume reach full scale; more saturate
		sample <= (mix[13:5] > 9'd255) ? 8'd255 : mix[12:5];
	end
end

// PWM: 256 steps at 50 MHz. A sample of 0 leaves the speaker off.
always @(posedge clk) begin
	pwm <= (tick[7:0] < sample);
end

endmodule
