// Rocket88 - A New 8-Bit Architecture
// Module: r88_regblock
// Description: Register Block
// See https://github.com/SlithyMatt/rocket88 for current code and documentation
//
// Timing: register outputs (regRight, regLeft, regAddr, intD) are combinational
// from the current select lines, so they are valid within the same microcode
// step. Register writes are latched at the end of the step (posedge sysClock).

module r88_regblock (
	input 	sysClock,
	inout 	[7:0] intD,
	input		[7:0] highOut,
	input 	[3:0] regSel,
	input    [1:0] regRightSel,
	input    [2:0] regLeftSel,
	input		regLeft16,
	input    [1:0] regAddrSel,
	input 	regWrite,
	input 	regRead,
	output	reg [15:0] regAddr,
	output 	reg [7:0] regRight,
	output 	reg [15:0] regLeft,
	input 	signFlag,
	input 	zeroFlag,
	input 	carryIn,
	input		decMode,
	input		breakFlag,
	input		irqEn,
	input    incPC,			// PC = PC + 1 (ignored if writing PC)
	input		pcLoadMC,		// PC = memory controller address register (ignored if writing PC)
	input		[15:0] mcAddr,
	input		incSP,			// SP = SP + 1 (ignored if writing SP)
	input		decSP,			// SP = SP - 1 (ignored if writing SP)
	input		[1:0] regExchange	// 1: swap BC and DD, 2: swap BC and EE
);

// regSel values
localparam REG_A   = 4'd0;
localparam REG_B   = 4'd1;
localparam REG_C   = 4'd2;
localparam REG_DDL = 4'd3;
localparam REG_DDH = 4'd4;
localparam REG_EEL = 4'd5;
localparam REG_EEH = 4'd6;
localparam REG_PCL = 4'd7;
localparam REG_PCH = 4'd8;
localparam REG_SPL = 4'd9;
localparam REG_SPH = 4'd10;
localparam REG_P   = 4'd11;

// Accumulator
reg [7:0] r_A = 8'h00;

// General Purpose Registers
// BC powers on as $FFFE (RESET vector low byte), used by the Init microcode
reg [7:0] r_B = 8'hFF;
reg [7:0] r_C = 8'hFE;

// Auxiliary Address Register
// DD powers on as $FFFF (RESET vector high byte), used by the Init microcode
reg [15:0] r_DD = 16'hFFFF;

// Long Index Register
reg [15:0] r_EE = 16'h0000;

// Program Counter
reg [15:0] r_PC = 16'h0000;

// Stack Pointer
reg [15:0] r_SP = 16'hFFF9;

// Processor status as seen on the bus: S Z C I D K - -
// (I is Interrupt *Disable*, so it is the inverse of irqEn)
wire [7:0] w_P = {signFlag, zeroFlag, carryIn, ~irqEn, decMode, breakFlag, 2'b00};

// Register read onto internal data bus
reg [7:0] r_intD;
assign intD = regRead ? r_intD : 8'bz;

always @(*) begin
	case (regSel)
		REG_A:   r_intD = r_A;
		REG_B:   r_intD = r_B;
		REG_C:   r_intD = r_C;
		REG_DDL: r_intD = r_DD[7:0];
		REG_DDH: r_intD = r_DD[15:8];
		REG_EEL: r_intD = r_EE[7:0];
		REG_EEH: r_intD = r_EE[15:8];
		REG_PCL: r_intD = r_PC[7:0];
		REG_PCH: r_intD = r_PC[15:8];
		REG_SPL: r_intD = r_SP[7:0];
		REG_SPH: r_intD = r_SP[15:8];
		REG_P:   r_intD = w_P;
		default: r_intD = 8'h00;
	endcase
end

// ALU right operand (8-bit)
always @(*) begin
	case (regRightSel)
		2'd1: regRight = r_A;
		2'd2: regRight = r_B;
		2'd3: regRight = r_C;
		default: regRight = 8'h00;
	endcase
end

// ALU left operand (8-bit or 16-bit)
always @(*) begin
	if (regLeft16) begin
		case (regLeftSel)
			3'd0: regLeft = r_DD;
			3'd1: regLeft = r_EE;
			3'd2: regLeft = r_PC;
			3'd3: regLeft = r_SP;
			default: regLeft = {r_B, r_C};
		endcase
	end
	else begin
		case (regLeftSel)
			3'd1: regLeft = {8'h00, r_A};
			3'd2: regLeft = {8'h00, r_B};
			3'd3: regLeft = {8'h00, r_C};
			default: regLeft = 16'h0000;
		endcase
	end
end

// Memory controller address source
always @(*) begin
	case (regAddrSel)
		2'd0: regAddr = {r_B, r_C};
		2'd1: regAddr = r_DD;
		2'd2: regAddr = r_PC;
		default: regAddr = r_SP;
	endcase
end

// Register writes, latched at end of step
always @(posedge sysClock) begin
	if (regWrite) begin
		case (regSel)
			REG_A:   r_A <= intD;
			REG_B:   r_B <= intD;
			REG_C:   r_C <= intD;
			REG_DDL: r_DD[7:0] <= intD;
			REG_DDH: r_DD[15:8] <= intD;
			REG_EEL: r_EE[7:0] <= intD;
			REG_EEH: r_EE[15:8] <= intD;
			REG_PCL: r_PC[7:0] <= intD;
			REG_PCH: r_PC[15:8] <= intD;
			REG_SPL: r_SP[7:0] <= intD;
			REG_SPH: r_SP[15:8] <= intD;
			default: ; // P lives in the decoder
		endcase
		// 16-bit write: low byte from intD (above), high byte from ALU highOut
		if (regLeft16) begin
			case (regSel)
				REG_C:   r_B <= highOut;
				REG_DDL: r_DD[15:8] <= highOut;
				REG_EEL: r_EE[15:8] <= highOut;
				REG_PCL: r_PC[15:8] <= highOut;
				REG_SPL: r_SP[15:8] <= highOut;
				default: ; // do nothing
			endcase
		end
	end

	// PC and SP counters, unless that register is being written this step
	if (!(regWrite && ((regSel == REG_PCL) || (regSel == REG_PCH)))) begin
		if (pcLoadMC) r_PC <= mcAddr;
		else if (incPC) r_PC <= r_PC + 16'd1;
	end
	if (!(regWrite && ((regSel == REG_SPL) || (regSel == REG_SPH)))) begin
		if (incSP) r_SP <= r_SP + 16'd1;
		else if (decSP) r_SP <= r_SP - 16'd1;
	end

	if (!regWrite) begin
		case (regExchange)
			2'd1: begin
				r_DD <= {r_B, r_C};
				{r_B, r_C} <= r_DD;
			end
			2'd2: begin
				r_EE <= {r_B, r_C};
				{r_B, r_C} <= r_EE;
			end
			default: ; // do nothing
		endcase
	end
end

endmodule
