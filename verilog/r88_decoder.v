// Rocket88 - A New 8-Bit Architecture
// Module: r88_decoder
// Description: Instruction Decoder
// See https://github.com/SlithyMatt/rocket88 for current code and documentation
//
// Timing model
// ------------
// Each rising edge of sysClock ends one microcode step. The steps in the
// Microcode sheet of Rocket88.ods (1n, 1p, 2n, 2p, ...) are consecutive
// clocks, so one "cycle" (n + p) of the sheet is two sysClocks. Everything is
// clocked on posedge only, since FPGA fabric has no dual-edge flip-flops.
//
// Within a step, the control outputs below are a combinational function of
// (r_init, r_step, r_opcode). The datapath muxes and ALU settle during the
// step, and every register (including the ones here) latches at its end.
//
// Status flags
// ------------
// S and Z always come from the ALU result (signOut/zeroOut) when szOutEn is
// set. To set flags from a value that comes straight off the bus (a load from
// memory), the microcode passes it through the ALU with aluOp=pass and
// rightSel=1. C is updated alongside S/Z when the ALU op is shift/add/sub.

module r88_decoder (
	input 		sysClock,
	output reg	readMem,
	output reg	writeMem,
	inout 		[7:0] intD,
	input 		resetReq,
	input 		nmiReq,
	input			irq,
	output reg	mc_use_regAddr,
	output reg	mc_write_low,
	output reg 	mc_write_high,
	output reg	[2:0] aluOp,
	output reg	[1:0] regRightSel,
	output reg	[1:0] regLeftSel,
	output reg	regLeft16,
	output reg	[1:0] regAddrSel,
	output		carryIn,
	input    	carryOut,
	input			aluSign,
	input			aluZero,
	output reg	invOut,
	output		decMode,
	output reg	carryInEn,
	output reg	[3:0]	regSel,
	output reg	regWrite,
	output reg	regRead,
	output		signFlag,
	output		zeroFlag,
	output reg	rightSel,
	output		breakFlag,
	output		irqEn,
	output reg	aluResult,
	output reg	loadResult,
	output reg	incPC 		// can only be set when regWrite is clear
);

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Microcode steps
localparam S1N = 4'd0;
localparam S1P = 4'd1;
localparam S2N = 4'd2;
localparam S2P = 4'd3;
localparam S3N = 4'd4;
localparam S3P = 4'd5;
localparam S4N = 4'd6;

// regSel values (see r88_regblock)
localparam REG_PCL = 4'd7;
localparam REG_PCH = 4'd8;
localparam REG_SPL = 4'd9;
localparam REG_P   = 4'd11;

// regAddrSel values
localparam ADDR_BC = 2'd0;
localparam ADDR_DD = 2'd1;
localparam ADDR_PC = 2'd2;
localparam ADDR_SP = 2'd3;

// regLeftSel value for SP when regLeft16 is set
localparam LEFT16_SP = 2'd3;

// ALU operations (see r88_alu)
localparam ALU_PASS = 3'd0;
localparam ALU_SHL  = 3'd1;
localparam ALU_SHR  = 3'd2;
localparam ALU_ADD  = 3'd3;
localparam ALU_SUB  = 3'd4;

// Addressing modes (opcode[2:0])
localparam MODE_ZERO = 3'd0;
localparam MODE_IMM  = 3'd4;
localparam MODE_ABS  = 3'd5;
localparam MODE_IND  = 3'd6;
localparam MODE_STK  = 3'd7;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

reg r_init = 1'b1;					// running power-on Init microcode
reg [3:0] r_step = S1N;				// current microcode step
reg [7:0] r_opcode = 8'h00;

// flags
reg r_carryFlag = 1'b0;
reg r_signFlag = 1'b0;
reg r_zeroFlag = 1'b1;
reg r_breakFlag = 1'b0;
reg r_irqEn = 1'b1;
reg r_decMode = 1'b0;

assign carryIn = r_carryFlag;
assign signFlag = r_signFlag;
assign zeroFlag = r_zeroFlag;
assign breakFlag = r_breakFlag;
assign irqEn = r_irqEn;
assign decMode = r_decMode;

// Constant driven onto intD by the decoder (the "intD" column of the sheet)
reg r_intDOut;
reg [7:0] r_intD;
assign intD = r_intDOut ? r_intD : 8'bz;

// Microcode-only controls
reg szOutEn;					// latch S/Z (and C for shift/add/sub) at end of step
reg lastStep;					// this is the final step of the instruction

// ---------------------------------------------------------------------------
// Opcode classification
// ---------------------------------------------------------------------------

wire [2:0] op_mode = r_opcode[2:0];
wire op_opt = r_opcode[3];
wire [3:0] op_hi = r_opcode[7:4];

// Single-byte NOPs: end after the opcode fetch
wire isNop0 =
	((op_hi == 4'h0) && (op_mode != MODE_IMM) && (op_mode != MODE_ABS)) ||
	((r_opcode[7:6] == 2'b01) && ((op_mode == 3'd1) || (op_mode == 3'd2) ||
	                              (op_mode == 3'd3) || (op_mode == 3'd7))) ||
	(r_opcode == 8'hA0) || (r_opcode == 8'hA8) ||
	(r_opcode == 8'hB0) || (r_opcode == 8'hB8) ||
	(r_opcode == 8'hFF);

// NOPs that fetch and ignore a one-byte operand
wire isNop1 =
	((op_hi == 4'h0) && (op_mode == MODE_IMM)) ||
	(r_opcode == 8'hA4) || (r_opcode == 8'hAC) ||
	(r_opcode == 8'hB4) || (r_opcode == 8'hBC);

// NOPs that fetch and ignore a two-byte operand
wire isNop2 = (op_hi == 4'h0) && (op_mode == MODE_ABS);

// Opcodes with a two-byte NN operand, fetched into the MC address register
// in steps 2n-3p before the opcode-specific steps begin (includes NOP+2)
wire isNN = ((op_mode == MODE_ABS) && (op_hi != 4'hF)) || (r_opcode == 8'hF7);

// Index of the step within the opcode-specific part of the microcode:
// 0 = first "n" step after the opcode (and NN operand) fetch, 1 = its "p", ...
wire [3:0] execBase = isNN ? S4N : S2N;
wire [3:0] ex = r_step - execBase;

// For load/store/compare rows 1x-3x: opcode[5:4] = 1/2/3 for A/B/C.
// regLeftSel/regRightSel use 1/2/3 for A/B/C, regSel uses 0/1/2.
wire [1:0] op_reg = r_opcode[5:4];
wire [3:0] op_regSel = {2'b00, op_reg - 2'd1};

// ---------------------------------------------------------------------------
// Microcode
// ---------------------------------------------------------------------------

always @(*) begin
	// Default: idle step (matches the all-zero rows of the Microcode sheet)
	r_intDOut = 1'b0;
	r_intD = 8'h00;
	readMem = 1'b0;
	writeMem = 1'b0;
	mc_use_regAddr = 1'b1;
	mc_write_low = 1'b0;
	mc_write_high = 1'b0;
	aluOp = ALU_PASS;
	regRightSel = 2'd0;
	regLeftSel = 2'd0;
	regLeft16 = 1'b0;
	regAddrSel = ADDR_PC;
	invOut = 1'b0;
	carryInEn = 1'b0;
	regSel = 4'd0;
	regWrite = 1'b0;
	regRead = 1'b0;
	szOutEn = 1'b0;
	rightSel = 1'b0;
	incPC = 1'b0;
	aluResult = 1'b0;
	loadResult = 1'b0;
	lastStep = 1'b0;

	if (r_init) begin
		// Load PC from RESET vector. BC = $FFFE and DD = $FFFF at power-on.
		readMem = 1'b1;
		regWrite = 1'b1;
		if (r_step == S1N) begin
			regAddrSel = ADDR_BC;
			regSel = REG_PCL;
		end
		else begin
			regAddrSel = ADDR_DD;
			regSel = REG_PCH;
			lastStep = 1'b1;
		end
	end
	else if (r_step == S1N) begin
		// Opcode fetch from PC; latched into r_opcode at end of step
		readMem = 1'b1;
	end
	else if (r_step == S1P) begin
		incPC = 1'b1;
		lastStep = isNop0;
	end
	else if (isNN && (r_step < S4N)) begin
		// NN operand fetch into MC address register (low byte, then high byte)
		case (r_step)
			S2N: begin readMem = 1'b1; mc_write_low = 1'b1; end
			S2P: incPC = 1'b1;
			S3N: begin readMem = 1'b1; mc_write_high = 1'b1; end
			default: begin // S3P
				incPC = 1'b1;
				lastStep = isNop2;
			end
		endcase
	end
	else if (isNop1) begin
		// Fetch and ignore one operand byte
		if (ex == 4'd0) readMem = 1'b1;
		else begin
			incPC = 1'b1;
			lastStep = 1'b1;
		end
	end
	else if ((op_hi >= 4'h1) && (op_hi <= 4'h3)) begin
		// Load / compare / store / push / pull for A, B, C
		if (!op_opt) begin
			case (op_mode)
				MODE_IMM: case (ex) // LDx #N
					4'd0: begin
						readMem = 1'b1;
						aluOp = ALU_PASS; rightSel = 1'b1; szOutEn = 1'b1;
						regSel = op_regSel; regWrite = 1'b1;
					end
					default: begin incPC = 1'b1; lastStep = 1'b1; end
				endcase
				MODE_ABS: case (ex) // LDx NN
					4'd0: begin
						readMem = 1'b1; mc_use_regAddr = 1'b0;
						aluOp = ALU_PASS; rightSel = 1'b1; szOutEn = 1'b1;
						regSel = op_regSel; regWrite = 1'b1;
					end
					default: lastStep = 1'b1;
				endcase
				MODE_IND: case (ex) // LDx (BC)
					4'd0: begin
						readMem = 1'b1; regAddrSel = ADDR_BC;
						aluOp = ALU_PASS; rightSel = 1'b1; szOutEn = 1'b1;
						regSel = op_regSel; regWrite = 1'b1;
					end
					default: lastStep = 1'b1;
				endcase
				MODE_STK: case (ex) // PLx
					4'd0: begin // read top of stack into register
						readMem = 1'b1; regAddrSel = ADDR_SP;
						aluOp = ALU_PASS; rightSel = 1'b1; szOutEn = 1'b1;
						regSel = op_regSel; regWrite = 1'b1;
					end
					4'd1: begin // compute SP + 1
						r_intDOut = 1'b1; r_intD = 8'h01;
						aluOp = ALU_ADD; regLeftSel = LEFT16_SP; regLeft16 = 1'b1; rightSel = 1'b1;
					end
					4'd2: begin // SP = result
						regLeft16 = 1'b1; regSel = REG_SPL; regWrite = 1'b1;
						aluResult = 1'b1; loadResult = 1'b1;
					end
					default: lastStep = 1'b1;
				endcase
				default: case (ex) // LDxZ, LDx A/B/C
					4'd0: begin
						aluOp = ALU_PASS; regRightSel = op_mode[1:0]; aluResult = 1'b1; szOutEn = 1'b1;
						regSel = op_regSel; regWrite = 1'b1;
					end
					default: lastStep = 1'b1;
				endcase
			endcase
		end
		else begin
			case (op_mode)
				MODE_IMM: case (ex) // CPx #N
					4'd0: begin
						// ALU reads the operand straight off the bus, so it must not drive it
						readMem = 1'b1;
						aluOp = ALU_SUB; regLeftSel = op_reg; rightSel = 1'b1; szOutEn = 1'b1;
					end
					default: begin incPC = 1'b1; lastStep = 1'b1; end
				endcase
				MODE_ABS: case (ex) // STx NN
					4'd0: begin
						writeMem = 1'b1; mc_use_regAddr = 1'b0;
						regSel = op_regSel; regRead = 1'b1;
					end
					default: lastStep = 1'b1;
				endcase
				MODE_IND: case (ex) // STx (BC)
					4'd0: begin
						writeMem = 1'b1; regAddrSel = ADDR_BC;
						regSel = op_regSel; regRead = 1'b1;
					end
					default: lastStep = 1'b1;
				endcase
				MODE_STK: case (ex) // PHx
					4'd0: begin // compute SP - 1
						r_intDOut = 1'b1; r_intD = 8'h01;
						aluOp = ALU_SUB; regLeftSel = LEFT16_SP; regLeft16 = 1'b1; rightSel = 1'b1;
					end
					4'd1: begin // SP = result
						regLeft16 = 1'b1; regSel = REG_SPL; regWrite = 1'b1;
						aluResult = 1'b1; loadResult = 1'b1;
					end
					4'd2: begin // write register to new top of stack
						writeMem = 1'b1; regAddrSel = ADDR_SP;
						regSel = op_regSel; regRead = 1'b1;
					end
					default: lastStep = 1'b1;
				endcase
				default: case (ex) // CPxZ, CPx A/B/C
					4'd0: begin
						aluOp = ALU_SUB; regLeftSel = op_reg; regRightSel = op_mode[1:0];
						aluResult = 1'b1; szOutEn = 1'b1;
					end
					default: lastStep = 1'b1;
				endcase
			endcase
		end
	end
	else begin
		// TODO: opcodes 4x-Fx not yet microcoded; treated as NOP (after any NN fetch)
		if (ex != 4'd0) lastStep = 1'b1;
	end
end

// ---------------------------------------------------------------------------
// Sequencing and flags
// ---------------------------------------------------------------------------

always @(posedge sysClock) begin
	// TODO: resetReq, nmiReq and irq handling

	if (lastStep) begin
		r_step <= S1N;
		r_init <= 1'b0;
	end
	else r_step <= r_step + 4'd1;

	if (!r_init && (r_step == S1N)) r_opcode <= intD;

	if (szOutEn) begin
		r_signFlag <= aluSign;
		r_zeroFlag <= aluZero;
		if ((aluOp == ALU_SHL) || (aluOp == ALU_SHR) || (aluOp == ALU_ADD) || (aluOp == ALU_SUB))
			r_carryFlag <= carryOut;
	end

	// Writing P (e.g. PLP) loads the flags from the bus: S Z C I D K - -
	if (regWrite && (regSel == REG_P)) begin
		r_signFlag <= intD[7];
		r_zeroFlag <= intD[6];
		r_carryFlag <= intD[5];
		r_irqEn <= ~intD[4];
		r_decMode <= intD[3];
		r_breakFlag <= intD[2];
	end
end

endmodule
