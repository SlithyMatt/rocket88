// Rocket88 - A New 8-Bit Architecture
// Module: r88_ps2
// Description: PS/2 port (keyboard or mouse) with an 8-byte receive FIFO
// See https://github.com/SlithyMatt/rocket88 for current code and documentation
//
// Receives bytes from the device into a FIFO, and sends bytes to the device
// (such as $F4 to make a mouse start reporting, or $ED to set keyboard LEDs).
// The clock and data lines are open drain: the pins are only ever driven low.

module r88_ps2 #(
	parameter CLK_HZ = 50000000
) (
	input clk,
	input reset,

	input ps2_clk_in,
	input ps2_dat_in,
	output reg ps2_clk_low = 1'b0,	// pull the clock line low
	output reg ps2_dat_low = 1'b0,	// pull the data line low

	output [7:0] rx_data,				// oldest byte in the FIFO
	output rx_ready,						// the FIFO is not empty
	input rx_pop,							// remove the oldest byte
	input [7:0] tx_data,
	input tx_start,						// send tx_data to the device
	output tx_busy,
	output reg error = 1'b0,			// parity, framing, timeout or overflow
	input clear_error
);

localparam FILTER     = 6'd40;						// 0.8 us at 50 MHz
localparam INHIBIT    = CLK_HZ / 8000;				// 125 us
localparam START      = CLK_HZ / 50000;			// 20 us
localparam RX_TIMEOUT = CLK_HZ / 500;				// 2 ms
localparam TX_TIMEOUT = CLK_HZ / 50;				// 20 ms

// Synchronize and filter the clock line; synchronize the data line
reg [2:0] clk_sync = 3'b111;
reg [2:0] dat_sync = 3'b111;
reg clk_f = 1'b1;
reg clk_prev = 1'b1;
reg [5:0] filter = 6'd0;
always @(posedge clk) begin
	clk_sync <= {clk_sync[1:0], ps2_clk_in};
	dat_sync <= {dat_sync[1:0], ps2_dat_in};
	clk_prev <= clk_f;
	if (clk_sync[2] == clk_f) filter <= 6'd0;
	else if (filter == FILTER) begin
		clk_f <= clk_sync[2];
		filter <= 6'd0;
	end else filter <= filter + 6'd1;
end
wire fall = clk_prev & ~clk_f;
wire dat = dat_sync[2];

// Receive FIFO
reg [7:0] fifo [0:7];
reg [2:0] rd_ptr = 3'd0;
reg [2:0] wr_ptr = 3'd0;
reg [3:0] count = 4'd0;
assign rx_data = fifo[rd_ptr];
assign rx_ready = (count != 4'd0);

// Receiver and transmitter state
reg [3:0] rx_bits = 4'd0;			// bits received so far
reg [9:0] rx_shift = 10'd0;
reg [21:0] timer = 22'd0;
reg sending = 1'b0;
reg [1:0] tx_state = 2'd0;
reg [3:0] tx_bits = 4'd0;
reg [8:0] tx_shift = 9'd0;			// data bits then parity
localparam TX_INHIBIT = 2'd0, TX_START = 2'd1, TX_BITS = 2'd2;
assign tx_busy = sending;

reg push;
reg [7:0] push_data;

always @(posedge clk) begin
	push = 1'b0;
	push_data = rx_shift[8:1];

	if (clear_error) error <= 1'b0;

	if (reset) begin
		rx_bits <= 4'd0;
		sending <= 1'b0;
		ps2_clk_low <= 1'b0;
		ps2_dat_low <= 1'b0;
		error <= 1'b0;
	end else if (tx_start && !sending) begin
		// Inhibit the device by holding the clock low, then send
		sending <= 1'b1;
		tx_state <= TX_INHIBIT;
		tx_shift <= {~^tx_data, tx_data};
		tx_bits <= 4'd0;
		timer <= 22'd0;
		rx_bits <= 4'd0;
		ps2_clk_low <= 1'b1;
	end else if (sending) begin
		timer <= timer + 22'd1;
		case (tx_state)
			TX_INHIBIT: if (timer == INHIBIT) begin
				ps2_dat_low <= 1'b1;				// start bit
				tx_state <= TX_START;
				timer <= 22'd0;
			end
			TX_START: if (timer == START) begin
				ps2_clk_low <= 1'b0;				// let the device clock the bits in
				tx_state <= TX_BITS;
				timer <= 22'd0;
			end
			default: begin
				// The device reads each bit on the rising edge of its clock,
				// so change the data line on each falling edge
				if (fall) begin
					tx_bits <= tx_bits + 4'd1;
					if (tx_bits < 4'd9) begin
						ps2_dat_low <= ~tx_shift[0];	// data bits, then parity
						tx_shift <= {1'b0, tx_shift[8:1]};
					end else if (tx_bits == 4'd9) begin
						ps2_dat_low <= 1'b0;			// stop bit
					end else begin
						// The device acknowledges by pulling data low
						if (dat) error <= 1'b1;
						sending <= 1'b0;
					end
				end
				if (timer == TX_TIMEOUT) begin
					ps2_dat_low <= 1'b0;
					sending <= 1'b0;
					error <= 1'b1;
				end
			end
		endcase
	end else begin
		// Receive: start bit, 8 data bits (LSB first), odd parity, stop bit
		if (fall) begin
			timer <= 22'd0;
			if (rx_bits == 4'd10) begin
				rx_bits <= 4'd0;
				if (!rx_shift[0] && dat && (^rx_shift[9:1])) begin
					push = 1'b1;
				end else begin
					error <= 1'b1;
				end
			end else begin
				rx_shift <= {dat, rx_shift[9:1]};
				rx_bits <= rx_bits + 4'd1;
			end
		end else if (rx_bits != 4'd0) begin
			// Give up on a byte that stops part way through
			timer <= timer + 22'd1;
			if (timer == RX_TIMEOUT) begin
				rx_bits <= 4'd0;
				error <= 1'b1;
			end
		end
	end

	// FIFO
	if (reset) begin
		rd_ptr <= 3'd0;
		wr_ptr <= 3'd0;
		count <= 4'd0;
	end else begin
		if (push) begin
			if (count == 4'd8 && !rx_pop) begin
				error <= 1'b1;							// overflow: drop the byte
			end else begin
				fifo[wr_ptr] <= push_data;
				wr_ptr <= wr_ptr + 3'd1;
			end
		end
		if (rx_pop && rx_ready) rd_ptr <= rd_ptr + 3'd1;
		case ({push && !(count == 4'd8 && !rx_pop), rx_pop && rx_ready})
			2'b10: count <= count + 4'd1;
			2'b01: count <= count - 4'd1;
			default: ;
		endcase
	end
end

endmodule
