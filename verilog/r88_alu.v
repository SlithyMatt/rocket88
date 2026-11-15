// Rocket88 - A New 8-Bit Architecture
// Module: r88_alu
// Description: Arithmetic-Logic Unit
// See https://github.com/SlithyMatt/rocket88 for current code and documentation
//
// Timing: the result is combinational from the current inputs, so it can be
// driven onto intD (aluResult) in the same microcode step it is computed.
// At the end of every step without loadResult, the result is also latched.
// With loadResult set, the latched result is output instead of computing,
// so a result can be computed in one step and written back in a later one
// (e.g. SP +/- 1 while SP itself is the left operand).
//
// Never set rightSel and aluResult together without loadResult: the ALU would
// then be driving the same bus it is reading from.
//
// Carry convention: for subtraction, carry = NOT borrow (C set when
// left >= right), which matches the compare definition in the README.

module r88_alu(
 	input sysClock,
	inout [7:0] intD,
	output [7:0] highOut,
	input [7:0] regRight,
	input [15:0] regLeft,
	input regLeft16,
	input [2:0] aluOp,
	input carryIn,
	output carryOut,
	output signOut,			// sign of (possibly latched) 8-bit result
	output zeroOut,			// zero of (possibly latched) 8-bit result
	input invOut,
	input decMode,
	input carryInEn,
	input rightSel,
	input aluResult,
	input loadResult
);

localparam ALU_PASS = 3'd0;
localparam ALU_SHL  = 3'd1;
localparam ALU_SHR  = 3'd2;
localparam ALU_ADD  = 3'd3;
localparam ALU_SUB  = 3'd4;
localparam ALU_OR   = 3'd5;
localparam ALU_AND  = 3'd6;
localparam ALU_XOR  = 3'd7;

wire [7:0] w_right = rightSel ? intD : regRight;

// Combinational result
reg [7:0] c_low;
reg [7:0] c_high;
reg c_carry;

// Scratch for arithmetic
reg [16:0] t_sum16;
reg [8:0] t_sum8;
reg [4:0] t_lo;
reg [4:0] t_hi;
reg t_cin;
reg t_borrowLo;
reg t_borrowHi;

always @(*) begin
	c_low = 8'h00;
	c_high = 8'h00;
	c_carry = carryIn;		// unchanged unless operation produces a carry
	t_sum16 = 17'h0;
	t_sum8 = 9'h0;
	t_lo = 5'h0;
	t_hi = 5'h0;
	t_cin = 1'b0;
	t_borrowLo = 1'b0;
	t_borrowHi = 1'b0;

	case (aluOp)
		ALU_PASS: c_low = w_right;
		ALU_SHL: begin
			c_low = {w_right[6:0], carryInEn & carryIn};
			c_carry = w_right[7];
		end
		ALU_SHR: begin
			c_low = {carryInEn & carryIn, w_right[7:1]};
			c_carry = w_right[0];
		end
		ALU_ADD: begin
			t_cin = carryInEn & carryIn;
			if (regLeft16) begin
				t_sum16 = {1'b0, regLeft} + {9'h000, w_right};
				{c_high, c_low} = t_sum16[15:0];
				c_carry = t_sum16[16];
			end
			else if (decMode) begin
				t_lo = {1'b0, regLeft[3:0]} + {1'b0, w_right[3:0]} + {4'h0, t_cin};
				if (t_lo > 5'd9) t_lo = t_lo + 5'd6;
				t_hi = {1'b0, regLeft[7:4]} + {1'b0, w_right[7:4]} + {4'h0, t_lo[4]};
				if (t_hi > 5'd9) t_hi = t_hi + 5'd6;
				c_low = {t_hi[3:0], t_lo[3:0]};
				c_carry = t_hi[4];
			end
			else begin
				t_sum8 = {1'b0, regLeft[7:0]} + {1'b0, w_right} + {8'h00, t_cin};
				c_low = t_sum8[7:0];
				c_carry = t_sum8[8];
			end
		end
		ALU_SUB: begin
			// carry in of 1 = no borrow; plain SUB/compare (carryInEn=0) never borrows in
			t_cin = carryInEn ? carryIn : 1'b1;
			if (regLeft16) begin
				t_sum16 = {1'b0, regLeft} - {9'h000, w_right};
				{c_high, c_low} = t_sum16[15:0];
				c_carry = ~t_sum16[16];
			end
			else if (decMode) begin
				t_lo = {1'b0, regLeft[3:0]} - {1'b0, w_right[3:0]} - {4'h0, ~t_cin};
				t_borrowLo = t_lo[4];
				if (t_borrowLo) t_lo = t_lo - 5'd6;
				t_hi = {1'b0, regLeft[7:4]} - {1'b0, w_right[7:4]} - {4'h0, t_borrowLo};
				t_borrowHi = t_hi[4];
				if (t_borrowHi) t_hi = t_hi - 5'd6;
				c_low = {t_hi[3:0], t_lo[3:0]};
				c_carry = ~t_borrowHi;
			end
			else begin
				t_sum8 = {1'b0, regLeft[7:0]} + {1'b0, ~w_right} + {8'h00, t_cin};
				c_low = t_sum8[7:0];
				c_carry = t_sum8[8];
			end
		end
		ALU_OR:  c_low = regLeft[7:0] | w_right;
		ALU_AND: c_low = regLeft[7:0] & w_right;
		ALU_XOR: c_low = regLeft[7:0] ^ w_right;
	endcase
end

wire [7:0] w_result = invOut ? ~c_low : c_low;

// Latched result
reg [7:0] r_low = 8'h00;
reg [7:0] r_high = 8'h00;
reg r_carry = 1'b0;

always @(posedge sysClock) begin
	if (!loadResult) begin
		r_low <= w_result;
		r_high <= c_high;
		r_carry <= c_carry;
	end
end

wire [7:0] w_out = loadResult ? r_low : w_result;

assign intD = aluResult ? w_out : 8'bz;
assign highOut = loadResult ? r_high : c_high;
assign carryOut = loadResult ? r_carry : c_carry;
assign signOut = w_out[7];
assign zeroOut = (w_out == 8'h00);

endmodule
