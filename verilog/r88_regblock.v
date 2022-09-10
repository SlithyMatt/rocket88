// Rocket88 - A New 8-Bit Architecture
// Module: r88_regblock
// Description: Register Block
// See https://github.com/SlithyMatt/rocket88 for current code and documentation

module r88_regblock (
	input 	sysClock,
	inout 	[7:0] intD,
	input 	[3:0] regSel,
	input    [1:0] regRightSel,
	input    [1:0] regLeftSel,
	input    [1:0] regAddrSel,
	input 	regWrite,
	input 	regRead,
	output	[15:0] regAddr,
	output 	[7:0] regRight,
	output 	[7:0] regLeft,
	input 	szOutEn,
	output 	signFlag,
	output 	zeroFlag
	input 	carryIn,
	input		decMode,
	input		breakFlag,
	input		irqEn
};

// Accumulator
reg [7:0] r_A = 8'h00;

// General Purpose Registers
reg [7:0] r_B = 8'h00;
reg [7:0] r_C = 8'h00;

// Auxiliary Address Register
reg [15:0] r_DD = 16'h0000;

// Long Index Register
reg [15:0] r_EE = 16'h0000;

// Program Counter
reg [15:0] r_PC = 16'hFFFE;

// Stack Pointer
reg [15:0] r_SP = 16'hFFF9;

// Output Buffers
reg [7:0] r_regRight = 8'h00;
reg [7:0] r_regLeft = 8'h00;
reg [15:0] r_regAddr = 8'h00;
reg [7:0] r_intD = 8'h00;

assign regRight = r_regRight;
assign regLeft = r_regLeft;
assign regAddr = r_regAddr;
assign intD = regRead? r_intD : 8'Z;

// Update outputs every clock edge
always @ edge sysClock begin
	if regRead begin
		case (regSel)
			3'd0: r_intD <= r_A;
			3'd1: r_intD <= r_B;
			3'd2: r_intD <= r_C;
			3'd3: r_intD <= r_DD[7:0];
			3'd4: r_intD <= r_DD[15:8];
			3'd5: r_intD <= r_EE[7:0];
			3'd6: r_intD <= r_EE[15:8];
			3'd7: r_intD <= r_PC[7:0];
			3'd8: r_intD <= r_PC[15:8];
			3'd9: r_intD <= r_SP[7:0];
			3'd10: r_intD <= r_SP[15:8];
			3'd11: begin
					r_intD[1:0] <= 2'b00;
					r_intD[2] <= breakFlag;
					r_intD[3] <= decMode;
					r_intD[4] <= irqEn;
					r_intD[5] <= carryIn;
					r_intD[6] <= zeroFlag;
					r_intD[7] <= signFlag;
				end
			default: r_intD <= 8'h00;
		endcase
	end
	else if regWrite begin
		case (regSel)
			3'd0: r_A <= intD;
			3'd1: r_B <= intD;
			3'd2: r_C <= intD;
			3'd3: r_DD[7:0] <= intD;
			3'd4: r_DD[15:8] <= intD;
			3'd5: r_EE[7:0] <= intD;
			3'd6: r_EE[15:8] <= intD;
			3'd7: r_PC[7:0] <= intD;
			3'd8: r_PC[15:8] <= intD;
			3'd9: r_SP[7:0] <= intD;
			3'd10: r_SP[15:8] <= intD;
			default: ; // do nothing
		endcase
	end
	
	case (regRightSel)
		2'd1: r_regRight <= r_A;
		2'd2: r_regRight <= r_B;
		2'd3: r_regRight <= r_C;
		default: r_regRight <= 8'h00;
	endcase
	
	case (regLeftSel)
		2'd1: r_regLeft <= r_A;
		2'd2: r_regLeft <= r_B;
		2'd3: r_regLeft <= r_C;
		default: r_regLeft <= 8'h00;
	endcase
			
	case (regAddrSel)
		2'd0: begin
				r_regAddr[15:8] <= r_B;
				r_regAddr[7:0] <= r_C;
			end
		2'd1: r_regAddr <= r_DD;
		2'd2: r_regAddr <= r_PC;
		2'd3: r_regAddr <= r_SP;
	endcase
	
end


endmodule
