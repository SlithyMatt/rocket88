// Rocket88 - A New 8-Bit Architecture
// Module: r88_alu
// Description: Arithmetic-Logic Unit
// See https://github.com/SlithyMatt/rocket88 for current code and documentation

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
	input invOut,
	input decMode,
	input carryInEn,
	input rightSel,
	input aluResult
);

reg [7:0] r_output = 8'h00;
reg r_carryOut = 0;
reg [7:0] r_highOut = 8'h00;
reg r_carrySink;

assign intD = aluResult? (invOut? ~r_output : r_output) : 8'Z;
assign carryOut = r_carryOut;

wire [7:0] r_rightOperand;
assign r_rightOperand = rightSel? intD : regRight;

always @ sysClock begin
	case (aluOp)
		3'd0: s_output <= r_rightOperand; // pass through
		3'd1: begin // shift left
			r_output[0] <= carryInEn? carryIn : 0;
			r_output[1] <= r_rightOperand[0];
			r_output[2] <= r_rightOperand[1];
			r_output[3] <= r_rightOperand[2];
			r_output[4] <= r_rightOperand[3];
			r_output[5] <= r_rightOperand[4];
			r_output[6] <= r_rightOperand[5];
			r_output[7] <= r_rightOperand[6];
			r_carryOut <= r_rightOperand[7];
			end
		3'd2: begin // shift right
			r_output[0] <= r_rightOperand[1];
			r_output[1] <= r_rightOperand[2];
			r_output[2] <= r_rightOperand[3];
			r_output[3] <= r_rightOperand[4];
			r_output[4] <= r_rightOperand[5];
			r_output[5] <= r_rightOperand[6];
			r_output[6] <= r_rightOperand[7];
			r_output[7] <= carryInEn? carryIn : 0;
			r_carryOut <= regRight[0];
			end
		3'd3: begin // add
				if (regLeft16)
					{r_carrySink, r_highOut, r_output} = regLeft + r_rightOperand;			
				else begin
					if (decMode) begin
						{r_carrySink, r_output[3:0]} = regLeft[3:0] + r_rightOperand[3:0] + carryInEn? carryIn : 0;
						if (r_carrySink or r_output[3:0] > 9) begin
							r_output[3:0] = r_output[3:0] + 6;
							r_carrySink = 1;
						end
						{r_carryOut, r_output[7:4]} = regLeft[7:4] + r_rightOperand[7:4] + r_carrySink;
						if (r_carryOut or r_output[7:4] > 9) begin
							r_output[7:4] = r_output[7:4] + 6;
							r_carryOut = 1;
						end
					end
					else
						{r_carryOut, r_output} = regLeft[7:0] + r_rightOperand + carryInEn? carryIn : 0;
				end
			end
		3'd4: begin // subtract
				if (regLeft16)
					{r_highOut, r_output} <= regLeft - r_rightOperand;
				else begin
					if (decMode) begin
						{r_carrySink, r_output[3:0]} = {1'b1,regLeft[3:0]} - r_rightOperand[3:0] - carryInEn? carryIn : 0;
						if (!r_carrySink) begin
							r_output[3:0] = r_output[3:0] - 6;
							r_carrySink = 1;
						end
						else
							r_carrySink = 0;
						{r_carryOut, r_output[7:4]} = {1'b1,regLeft[7:4]} - r_rightOperand[7:4] - r_carrySink;
						if (!r_carryOut) begin
							r_output[7:4] = r_output[7:4] - 6;
							r_carryOut = 1;
						end
						else
							r_carryOut = 0;
					end					
					else
						{r_carryOut, r_output} <= regLeft[7:0] + ~({r_rightOperand[7],r_rightOperand} + carryInEn? carryIn : 0) + 1;
			end
		3'd5: r_output <= regLeft[7:0] | r_rightOperand; // or
		3'd6: r_output <= regLeft[7:0] & r_rightOperand; // and
		3'd7: r_output <= regLeft[7:0] ^ r_rightOperand; // exclusive or
	endcase
end

endmodule
