// Rocket88 - A New 8-Bit Architecture
// Testbench model: ps2_device
// Description: PS/2 keyboard or mouse: sends bytes to the host, and receives
//              host commands, answering each with $FA (acknowledge)
//
// The clock runs at 12.5 kHz (40 us low, 40 us high). Lines are open drain,
// with pull-ups in the testbench.

`timescale 1ns / 100ps

module ps2_device #(
	parameter NAME = "device"
) (
	inout ps2_clk,
	inout ps2_dat
);

reg clk_low = 1'b0;
reg dat_low = 1'b0;
assign ps2_clk = clk_low ? 1'b0 : 1'bz;
assign ps2_dat = dat_low ? 1'b0 : 1'bz;

localparam HALF = 40000;				// ns

reg [7:0] received [0:15];			// commands from the host
integer received_count = 0;
integer errors = 0;
reg busy = 1'b0;

// Send one byte: start, 8 data bits (LSB first), odd parity, stop. The
// device changes data while the clock is high, and the host reads it on the
// falling edge.
task send;
	input [7:0] data;
	reg [10:0] frame;
	integer i;
	begin
		wait (!busy);
		busy = 1'b1;
		wait (ps2_clk === 1'b1);		// not inhibited by the host
		#(HALF);
		frame = {1'b1, ~^data, data, 1'b0};
		for (i = 0; i < 11; i = i + 1) begin
			dat_low = ~frame[i];
			#(HALF / 2);
			clk_low = 1'b1;
			#(HALF);
			clk_low = 1'b0;
			#(HALF / 2);
		end
		dat_low = 1'b0;
		#(HALF);
		busy = 1'b0;
	end
endtask

// Host to device: the host holds the clock low, pulls data low (start bit)
// and releases the clock. The device then clocks in 8 data bits, parity and
// stop, reading each on the rising edge, and acknowledges by pulling data
// low for one more clock.
reg [9:0] bits;
integer n;
always @(negedge ps2_clk) begin
	if (!clk_low && !busy) begin
		// The host is pulling the clock low
		#(1000);
		wait (ps2_clk === 1'b1);
		if (ps2_dat === 1'b0) begin
			busy = 1'b1;
			#(HALF / 2);
			for (n = 0; n < 10; n = n + 1) begin
				clk_low = 1'b1;
				#(HALF);
				clk_low = 1'b0;
				#(HALF / 2);
				bits[n] = (ps2_dat !== 1'b0);
				#(HALF / 2);
			end
			// bits[7:0] data, bits[8] parity, bits[9] stop
			if (!bits[9] || (^bits[8:0]) !== 1'b1) begin
				$display("PS/2 ERROR: %0s received a bad frame %b", NAME, bits);
				errors = errors + 1;
			end
			// Acknowledge
			dat_low = 1'b1;
			clk_low = 1'b1;
			#(HALF);
			clk_low = 1'b0;
			#(HALF / 2);
			dat_low = 1'b0;
			#(HALF);
			busy = 1'b0;
			if (received_count < 16) received[received_count] = bits[7:0];
			received_count = received_count + 1;
			send(8'hFA);
		end
	end
end

endmodule
