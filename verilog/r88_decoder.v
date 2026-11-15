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
// the decoder state (r_init, r_step, r_opcode, flags). The datapath muxes and
// ALU settle during the step, and every register latches at its end.
//
// Every instruction starts with the opcode fetch (1n) and PC increment (1p).
// Opcodes with an NN operand then fetch it into the memory controller address
// register (2n-3p). The opcode-specific steps follow, numbered from 0 by "ex"
// below (ex 0 = 2n, or 4n after an NN fetch). Instructions always end on a "p"
// step (odd ex), so each takes a whole number of n/p cycles.
//
// Status flags
// ------------
// Flags are updated at the end of a step by these microcode-only controls:
//   szOutEn - S and Z from the 8-bit ALU result
//   z16En   - Z from the 16-bit ALU result
//   cOutEn  - C from the ALU carry/borrow out (inverted when cInv is set, so
//             compares set C when the register is >= the operand)
//   flagSel - set/clear C, D, I or K directly
// To set flags from a value straight off the bus (a load from memory), the
// microcode passes it through the ALU with aluOp=pass and rightSel=1.
//
// Interrupts
// ----------
// RESET, NMI and IRQ are active low. RESET aborts the current instruction and
// runs the RST microcode. NMI is latched on its falling edge; IRQ is a level,
// honored while interrupts are enabled. Both are taken between instructions
// and run the BRK microcode (without setting K) using their own vector.

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
	output reg	mc_write_full,
	output reg	mc_inc,
	output reg	[2:0] aluOp,
	output reg	[1:0] regRightSel,
	output reg	[2:0] regLeftSel,
	output reg	regLeft16,
	output reg	[1:0] regAddrSel,
	output		carryIn,				// carry flag (for P)
	output		aluCarryIn,			// carry into the ALU
	input    	carryOut,
	input			aluSign,
	input			aluZero,
	input			aluZero16,
	output reg	invOut,
	output		decMode,				// decimal flag (for P)
	output		aluDecMode,			// decimal mode for the ALU
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
	output reg	incPC,
	output reg	pcLoadMC,
	output reg	incSP,
	output reg	decSP,
	output reg	[1:0] regExchange
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
localparam REG_A   = 4'd0;
localparam REG_B   = 4'd1;
localparam REG_C   = 4'd2;
localparam REG_DDL = 4'd3;
localparam REG_EEL = 4'd5;
localparam REG_PCL = 4'd7;
localparam REG_PCH = 4'd8;
localparam REG_SPL = 4'd9;
localparam REG_SPH = 4'd10;
localparam REG_P   = 4'd11;

// regAddrSel values
localparam ADDR_BC = 2'd0;
localparam ADDR_DD = 2'd1;
localparam ADDR_PC = 2'd2;
localparam ADDR_SP = 2'd3;

// regLeftSel values when regLeft16 is set
localparam LEFT16_DD = 3'd0;
localparam LEFT16_EE = 3'd1;
localparam LEFT16_PC = 3'd2;
localparam LEFT16_SP = 3'd3;
localparam LEFT16_BC = 3'd4;

// regLeftSel/regRightSel values for 8-bit operands
localparam OPD_ZERO = 2'd0;
localparam OPD_A    = 2'd1;
localparam OPD_B    = 2'd2;
localparam OPD_C    = 2'd3;

// ALU operations (see r88_alu)
localparam ALU_PASS = 3'd0;
localparam ALU_SHL  = 3'd1;
localparam ALU_SHR  = 3'd2;
localparam ALU_ADD  = 3'd3;
localparam ALU_SUB  = 3'd4;
localparam ALU_OR   = 3'd5;
localparam ALU_AND  = 3'd6;
localparam ALU_XOR  = 3'd7;

// Addressing modes (opcode[2:0])
localparam MODE_ZERO = 3'd0;
localparam MODE_IMM  = 3'd4;
localparam MODE_ABS  = 3'd5;
localparam MODE_IND  = 3'd6;
localparam MODE_STK  = 3'd7;

// flagSel values
localparam FLAG_NONE = 3'd0;
localparam FLAG_C    = 3'd1;
localparam FLAG_D    = 3'd2;
localparam FLAG_IEN  = 3'd3;	// interrupt enable (inverse of P's I bit)
localparam FLAG_K    = 3'd4;

// Interrupt vectors (low byte; high byte is $FF)
localparam VEC_IRQ   = 8'hFA;
localparam VEC_NMI   = 8'hFC;
localparam VEC_RESET = 8'hFE;

// Opcodes with dedicated microcode used by the sequencer
localparam OP_BRK = 8'hF5;
localparam OP_RST = 8'hF6;
localparam OP_LDS_NN = 8'hF7;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

reg r_init = 1'b1;					// running power-on Init microcode
reg [3:0] r_step = S1N;				// current microcode step
reg [7:0] r_opcode = 8'h00;
reg r_hwInt = 1'b0;					// BRK microcode is running for a hardware interrupt
reg [7:0] r_vector = VEC_IRQ;		// vector low byte for BRK microcode
reg r_nmiPrev = 1'b1;
reg r_nmiPending = 1'b0;

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
reg szOutEn;					// latch S/Z from 8-bit ALU result at end of step
reg z16En;						// latch Z from 16-bit ALU result at end of step
reg cOutEn;						// latch C from ALU carry out at end of step
reg cInv;						// invert carry out when latching (compares)
reg forceCin;					// force ALU carry in to 1 (increment/decrement)
reg decEn;						// allow decimal mode in the ALU
reg [2:0] flagSel;			// flag to set/clear at end of step
reg flagVal;					// value for flagSel
reg stall;						// hold this step (HLT)
reg lastStep;					// this is the final step of the instruction

assign aluCarryIn = forceCin | r_carryFlag;
assign aluDecMode = r_decMode & decEn;

// NMI falling edge, and wake-up condition for HLT
wire nmiEdge = r_nmiPrev & ~nmiReq;
wire wake = ~irq | r_nmiPending | nmiEdge;

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
wire isNN = ((op_mode == MODE_ABS) && (op_hi != 4'hF)) || (r_opcode == OP_LDS_NN);

// Index of the step within the opcode-specific part of the microcode
wire [3:0] execBase = isNN ? S4N : S2N;
wire [3:0] ex = r_step - execBase;

// For load/store/compare rows 1x-3x: opcode[5:4] = 1/2/3 for A/B/C.
// regLeftSel/regRightSel use 1/2/3 for A/B/C, regSel uses 0/1/2.
wire [1:0] op_reg = r_opcode[5:4];
wire [3:0] op_regSel = {2'b00, op_reg - 2'd1};

// Jump condition for rows 4x-7x: always, Z, S, C
wire jmpFlag = (op_hi == 4'h5) ? r_zeroFlag :
               (op_hi == 4'h6) ? r_signFlag :
               (op_hi == 4'h7) ? r_carryFlag : 1'b1;
// Relative jumps are taken when the flag is clear, NN/(BC) jumps when it is set
wire jmpTaken = (op_hi == 4'h4) ? 1'b1 : ((op_mode == MODE_IMM) ? ~jmpFlag : jmpFlag);

// ---------------------------------------------------------------------------
// Microcode helpers
// ---------------------------------------------------------------------------

// Read an operand from memory onto intD for the ALU right side:
// #N (PC, then advance PC), NN (MC address register) or (BC)
task memSrc(input [2:0] mode);
	begin
		readMem = 1'b1;
		rightSel = 1'b1;
		case (mode)
			MODE_IMM: incPC = 1'b1;
			MODE_ABS: mc_use_regAddr = 1'b0;
			default:  regAddrSel = ADDR_BC;
		endcase
	end
endtask

// Write the latched ALU result back to memory at NN or (BC)
task memDst(input [2:0] mode);
	begin
		writeMem = 1'b1;
		aluResult = 1'b1;
		loadResult = 1'b1;
		if (mode == MODE_ABS) mc_use_regAddr = 1'b0;
		else regAddrSel = ADDR_BC;
	end
endtask

// Write the latched ALU result to a register
task writeLatched(input [3:0] sel);
	begin
		aluResult = 1'b1;
		loadResult = 1'b1;
		regSel = sel;
		regWrite = 1'b1;
	end
endtask

// Push one register using the ALU to decrement SP (PHA/PHB/PHC/PHP)
task pushReg(input [3:0] sel);
	begin
		case (ex)
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
				regSel = sel; regRead = 1'b1;
			end
			default: lastStep = 1'b1;
		endcase
	end
endtask

// Pull one register using the ALU to increment SP (PLA/PLB/PLC/PLP)
task pullReg(input [3:0] sel, input setFlags);
	begin
		case (ex)
			4'd0: begin // read top of stack into register
				readMem = 1'b1; regAddrSel = ADDR_SP;
				aluOp = ALU_PASS; rightSel = 1'b1; szOutEn = setFlags;
				regSel = sel; regWrite = 1'b1;
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
	end
endtask

// Write a register to the stack at SP (SP already decremented), then
// decrement SP again if more bytes follow
task pushByte(input [3:0] sel, input more);
	begin
		writeMem = 1'b1; regAddrSel = ADDR_SP;
		regSel = sel; regRead = 1'b1;
		decSP = more;
	end
endtask

// Read the stack at SP into a register, then increment SP
task pullByte(input [3:0] sel);
	begin
		readMem = 1'b1; regAddrSel = ADDR_SP;
		regSel = sel; regWrite = 1'b1;
		incSP = 1'b1;
	end
endtask

// Read a byte at the MC address register into a register, then increment it
task readMC(input [3:0] sel);
	begin
		readMem = 1'b1; mc_use_regAddr = 1'b0;
		regSel = sel; regWrite = 1'b1;
		mc_inc = 1'b1;
	end
endtask

// 8-bit increment/decrement of A, B or C: one step
task incDec8(input sub, input [1:0] opd);
	begin
		case (ex)
			4'd0: begin
				aluOp = sub ? ALU_SUB : ALU_ADD;
				regLeftSel = {1'b0, opd}; regRightSel = OPD_ZERO;
				carryInEn = 1'b1; forceCin = 1'b1;
				aluResult = 1'b1; szOutEn = 1'b1; cOutEn = 1'b1;
				regSel = {2'b00, opd - 2'd1}; regWrite = 1'b1;
			end
			default: lastStep = 1'b1;
		endcase
	end
endtask

// 16-bit increment/decrement of DD, EE or BC: one step
task incDec16(input sub, input [2:0] left, input [3:0] lowSel);
	begin
		case (ex)
			4'd0: begin
				aluOp = sub ? ALU_SUB : ALU_ADD;
				regLeft16 = 1'b1; regLeftSel = left; regRightSel = OPD_ZERO;
				carryInEn = 1'b1; forceCin = 1'b1;
				aluResult = 1'b1; z16En = 1'b1;
				regSel = lowSel; regWrite = 1'b1;
			end
			default: lastStep = 1'b1;
		endcase
	end
endtask

// Set or clear a flag: one cycle
task setFlag(input [2:0] sel, input val);
	begin
		if (ex == 4'd0) begin
			flagSel = sel;
			flagVal = val;
		end
		else lastStep = 1'b1;
	end
endtask

// 16-bit copy through the ALU (left + 0) into a register pair: one step
task copy16(input [2:0] left, input [3:0] lowSel);
	begin
		if (ex == 4'd0) begin
			aluOp = ALU_ADD; regLeft16 = 1'b1; regLeftSel = left; regRightSel = OPD_ZERO;
			aluResult = 1'b1; regSel = lowSel; regWrite = 1'b1;
		end
		else lastStep = 1'b1;
	end
endtask

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
	mc_write_full = 1'b0;
	mc_inc = 1'b0;
	aluOp = ALU_PASS;
	regRightSel = 2'd0;
	regLeftSel = 3'd0;
	regLeft16 = 1'b0;
	regAddrSel = ADDR_PC;
	invOut = 1'b0;
	carryInEn = 1'b0;
	regSel = 4'd0;
	regWrite = 1'b0;
	regRead = 1'b0;
	rightSel = 1'b0;
	incPC = 1'b0;
	pcLoadMC = 1'b0;
	incSP = 1'b0;
	decSP = 1'b0;
	regExchange = 2'd0;
	aluResult = 1'b0;
	loadResult = 1'b0;
	szOutEn = 1'b0;
	z16En = 1'b0;
	cOutEn = 1'b0;
	cInv = 1'b0;
	forceCin = 1'b0;
	decEn = 1'b0;
	flagSel = FLAG_NONE;
	flagVal = 1'b0;
	stall = 1'b0;
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
		// LDS NN also writes the bytes straight into SP.
		case (r_step)
			S2N: begin
				readMem = 1'b1; mc_write_low = 1'b1;
				if (r_opcode == OP_LDS_NN) begin regSel = REG_SPL; regWrite = 1'b1; end
			end
			S2P: incPC = 1'b1;
			S3N: begin
				readMem = 1'b1; mc_write_high = 1'b1;
				if (r_opcode == OP_LDS_NN) begin regSel = REG_SPH; regWrite = 1'b1; end
			end
			default: begin // S3P
				incPC = 1'b1;
				lastStep = isNop2 || (r_opcode == OP_LDS_NN);
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
	else if (isNop0) begin
		// Unreachable (ends at 1p); keeps the sequencer safe
		lastStep = 1'b1;
	end
	else begin
		case (op_hi)
		// -------------------------------------------------------------------
		// 1x-3x: load / compare / store / push / pull for A, B, C
		// -------------------------------------------------------------------
		4'h1, 4'h2, 4'h3: begin
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
					MODE_STK: pullReg(op_regSel, 1'b1); // PLx
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
							aluOp = ALU_SUB; regLeftSel = {1'b0, op_reg}; rightSel = 1'b1;
							szOutEn = 1'b1; cOutEn = 1'b1; cInv = 1'b1;
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
					MODE_STK: pushReg(op_regSel); // PHx
					default: case (ex) // CPxZ, CPx A/B/C
						4'd0: begin
							aluOp = ALU_SUB; regLeftSel = {1'b0, op_reg}; regRightSel = op_mode[1:0];
							aluResult = 1'b1; szOutEn = 1'b1; cOutEn = 1'b1; cInv = 1'b1;
						end
						default: lastStep = 1'b1;
					endcase
				endcase
			end
		end

		// -------------------------------------------------------------------
		// 4x-7x: exchange, DD indirect, 16-bit inc/dec, jumps and subroutines
		// -------------------------------------------------------------------
		4'h4, 4'h5, 4'h6, 4'h7: begin
			case (op_mode)
				MODE_ZERO: begin
					case ({op_hi[1:0], op_opt})
						3'b000, 3'b001: begin // EXD, EXE: Z from new BC (old DD/EE)
							if (ex == 4'd0) begin
								regExchange = op_opt ? 2'd2 : 2'd1;
								aluOp = ALU_ADD; regLeft16 = 1'b1;
								regLeftSel = op_opt ? LEFT16_EE : LEFT16_DD;
								z16En = 1'b1;
							end
							else lastStep = 1'b1;
						end
						3'b010: begin // LDA (DD)
							if (ex == 4'd0) begin
								readMem = 1'b1; regAddrSel = ADDR_DD;
								aluOp = ALU_PASS; rightSel = 1'b1; szOutEn = 1'b1;
								regSel = REG_A; regWrite = 1'b1;
							end
							else lastStep = 1'b1;
						end
						3'b011: begin // STA (DD)
							if (ex == 4'd0) begin
								writeMem = 1'b1; regAddrSel = ADDR_DD;
								regSel = REG_A; regRead = 1'b1;
							end
							else lastStep = 1'b1;
						end
						3'b100: incDec16(1'b0, LEFT16_DD, REG_DDL); // INC DD
						3'b101: incDec16(1'b1, LEFT16_DD, REG_DDL); // DEC DD
						3'b110: incDec16(1'b0, LEFT16_EE, REG_EEL); // INC EE
						default: incDec16(1'b1, LEFT16_EE, REG_EEL); // DEC EE
					endcase
				end

				MODE_IMM: begin // JMPR/JPNZ/JMPP/JPNC, JSRR/JSNZ/JSRP/JSNC
					if (!jmpTaken) begin
						if (ex == 4'd0) incPC = 1'b1; // skip offset
						else lastStep = 1'b1;
					end
					else if (!op_opt) begin
						case (ex)
							4'd0: begin // target = PC + 1 + offset
								readMem = 1'b1; rightSel = 1'b1;
								aluOp = ALU_ADD; regLeft16 = 1'b1; regLeftSel = LEFT16_PC;
								carryInEn = 1'b1; forceCin = 1'b1;
							end
							default: begin // PC = target
								regLeft16 = 1'b1; writeLatched(REG_PCL);
								lastStep = 1'b1;
							end
						endcase
					end
					else begin
						case (ex)
							4'd0: begin // target = PC + 1 + offset; PC = return address
								readMem = 1'b1; rightSel = 1'b1;
								aluOp = ALU_ADD; regLeft16 = 1'b1; regLeftSel = LEFT16_PC;
								carryInEn = 1'b1; forceCin = 1'b1;
								incPC = 1'b1;
							end
							4'd1: begin decSP = 1'b1; loadResult = 1'b1; end
							4'd2: begin pushByte(REG_PCH, 1'b1); loadResult = 1'b1; end
							4'd3: begin pushByte(REG_PCL, 1'b0); loadResult = 1'b1; end
							4'd4: begin regLeft16 = 1'b1; writeLatched(REG_PCL); end
							default: lastStep = 1'b1;
						endcase
					end
				end

				MODE_ABS: begin // JMP/JMPZ/JMPN/JMPC NN, JSR/JSRZ/JSRN/JSRC NN
					if (!jmpTaken) begin
						if (ex != 4'd0) lastStep = 1'b1;
					end
					else if (!op_opt) begin
						if (ex == 4'd0) pcLoadMC = 1'b1;
						else lastStep = 1'b1;
					end
					else begin
						case (ex)
							4'd0: decSP = 1'b1;
							4'd1: pushByte(REG_PCH, 1'b1);
							4'd2: begin pushByte(REG_PCL, 1'b0); pcLoadMC = 1'b1; end
							default: lastStep = 1'b1;
						endcase
					end
				end

				MODE_IND: begin // JMP/JMPZ/JMPN/JMPC (BC), JSR/JSRZ/JSRN/JSRC (BC)
					if (!jmpTaken) begin
						if (ex != 4'd0) lastStep = 1'b1;
					end
					else if (!op_opt) begin
						case (ex)
							4'd0: begin regAddrSel = ADDR_BC; mc_write_full = 1'b1; end
							4'd1: readMC(REG_PCL);
							4'd2: readMC(REG_PCH);
							default: lastStep = 1'b1;
						endcase
					end
					else begin
						case (ex)
							4'd0: begin decSP = 1'b1; regAddrSel = ADDR_BC; mc_write_full = 1'b1; end
							4'd1: pushByte(REG_PCH, 1'b1);
							4'd2: pushByte(REG_PCL, 1'b0);
							4'd3: readMC(REG_PCL);
							4'd4: readMC(REG_PCH);
							default: lastStep = 1'b1;
						endcase
					end
				end

				default: lastStep = 1'b1; // NOPs, handled above
			endcase
		end

		// -------------------------------------------------------------------
		// 8x-Ex: ALU operations on A; x7/xF are other math/logic
		// -------------------------------------------------------------------
		4'h8, 4'h9, 4'hC, 4'hD, 4'hE: begin
			if (op_mode == MODE_STK) begin
				case (r_opcode)
					8'h87: incDec8(1'b0, OPD_A); // INC A
					8'h8F: incDec8(1'b0, OPD_B); // INC B
					8'h97: incDec8(1'b0, OPD_C); // INC C
					8'h9F: incDec8(1'b1, OPD_A); // DEC A
					8'hC7, 8'hCF: begin // INV B, INV C
						if (ex == 4'd0) begin
							aluOp = ALU_PASS; invOut = 1'b1;
							regRightSel = op_opt ? OPD_C : OPD_B;
							aluResult = 1'b1; szOutEn = 1'b1;
							regSel = op_opt ? REG_C : REG_B; regWrite = 1'b1;
						end
						else lastStep = 1'b1;
					end
					8'hD7: setFlag(FLAG_D, 1'b1); // SED
					8'hDF: setFlag(FLAG_D, 1'b0); // CLD
					8'hE7: pushReg(REG_P); // PHP
					default: pullReg(REG_P, 1'b0); // PLP (EF)
				endcase
			end
			else begin
				// ADD/ADC, SUB/SBC, ORA/NOR, AND/NND, XOR/XNR
				case (op_hi)
					4'h8: begin aluOp = ALU_ADD; carryInEn = op_opt; decEn = 1'b1; end
					4'h9: begin aluOp = ALU_SUB; carryInEn = op_opt; decEn = 1'b1; end
					4'hC: begin aluOp = ALU_OR;  invOut = op_opt; end
					4'hD: begin aluOp = ALU_AND; invOut = op_opt; end
					default: begin aluOp = ALU_XOR; invOut = op_opt; end
				endcase
				regLeftSel = {1'b0, OPD_A};
				if (op_mode < MODE_IMM) begin
					// Zero, A, B, C: one step
					if (ex == 4'd0) begin
						regRightSel = op_mode[1:0];
						aluResult = 1'b1; szOutEn = 1'b1;
						cOutEn = (op_hi == 4'h8) || (op_hi == 4'h9);
						regSel = REG_A; regWrite = 1'b1;
					end
					else lastStep = 1'b1;
				end
				else begin
					// #N, NN, (BC): compute while reading, then write A
					if (ex == 4'd0) begin
						memSrc(op_mode);
						szOutEn = 1'b1;
						cOutEn = (op_hi == 4'h8) || (op_hi == 4'h9);
					end
					else begin
						writeLatched(REG_A);
						lastStep = 1'b1;
					end
				end
			end
		end

		// -------------------------------------------------------------------
		// Ax-Bx: shifts and rotates; x7/xF are other math
		// -------------------------------------------------------------------
		4'hA, 4'hB: begin
			if (op_mode == MODE_STK) begin
				case (r_opcode)
					8'hA7: incDec8(1'b1, OPD_B); // DEC B
					8'hAF: incDec8(1'b1, OPD_C); // DEC C
					8'hB7: begin // NEG: A = 0 - A
						if (ex == 4'd0) begin
							aluOp = ALU_SUB; regLeftSel = {1'b0, OPD_ZERO}; regRightSel = OPD_A;
							aluResult = 1'b1; szOutEn = 1'b1; cOutEn = 1'b1;
							regSel = REG_A; regWrite = 1'b1;
						end
						else lastStep = 1'b1;
					end
					default: begin // INC (BC) (BF)
						if (ex == 4'd0) begin
							memSrc(MODE_IND);
							aluOp = ALU_ADD; regLeftSel = {1'b0, OPD_ZERO};
							carryInEn = 1'b1; forceCin = 1'b1;
							szOutEn = 1'b1; cOutEn = 1'b1;
						end
						else begin
							memDst(MODE_IND);
							lastStep = 1'b1;
						end
					end
				endcase
			end
			else begin
				// LSR/ROR (Ax), ASL/ROL (Bx); option bit rotates through carry
				aluOp = (op_hi == 4'hA) ? ALU_SHR : ALU_SHL;
				carryInEn = op_opt;
				if (op_mode < MODE_IMM) begin
					// A, B, C: one step
					if (ex == 4'd0) begin
						regRightSel = op_mode[1:0];
						aluResult = 1'b1; szOutEn = 1'b1; cOutEn = 1'b1;
						regSel = {2'b00, op_mode[1:0] - 2'd1}; regWrite = 1'b1;
					end
					else lastStep = 1'b1;
				end
				else begin
					// NN, (BC): read, shift, write back
					if (ex == 4'd0) begin
						memSrc(op_mode);
						szOutEn = 1'b1; cOutEn = 1'b1;
					end
					else begin
						memDst(op_mode);
						lastStep = 1'b1;
					end
				end
			end
		end

		// -------------------------------------------------------------------
		// Fx: other general
		// -------------------------------------------------------------------
		default: begin
			case (r_opcode)
				8'hF0: setFlag(FLAG_IEN, 1'b0); // SEI (disable IRQ)
				8'hF1: setFlag(FLAG_IEN, 1'b1); // CLI (enable IRQ)
				8'hF2: begin // RTS
					case (ex)
						4'd0: pullByte(REG_PCL);
						default: begin pullByte(REG_PCH); lastStep = 1'b1; end
					endcase
				end
				8'hF3: begin // RTI: pull C, B, A, P, PCL, PCH
					case (ex)
						4'd0: pullByte(REG_C);
						4'd1: pullByte(REG_B);
						4'd2: pullByte(REG_A);
						4'd3: pullByte(REG_P);
						4'd4: pullByte(REG_PCL);
						default: begin pullByte(REG_PCH); lastStep = 1'b1; end
					endcase
				end
				8'hF4: begin // HLT: wait for an interrupt request
					if (ex == 4'd0) stall = ~wake;
					else lastStep = 1'b1;
				end
				OP_BRK: begin // BRK / IRQ / NMI: push PC, P, A, B, C; jump to vector
					case (ex)
						4'd0: begin
							decSP = 1'b1;
							r_intDOut = 1'b1; r_intD = r_vector; mc_write_low = 1'b1;
							if (!r_hwInt) begin flagSel = FLAG_K; flagVal = 1'b1; end
						end
						4'd1: pushByte(REG_PCH, 1'b1);
						4'd2: pushByte(REG_PCL, 1'b1);
						4'd3: pushByte(REG_P, 1'b1);
						4'd4: pushByte(REG_A, 1'b1);
						4'd5: pushByte(REG_B, 1'b1);
						4'd6: pushByte(REG_C, 1'b0);
						4'd7: begin r_intDOut = 1'b1; r_intD = 8'hFF; mc_write_high = 1'b1; end
						4'd8: readMC(REG_PCL);
						default: begin
							readMC(REG_PCH);
							flagSel = FLAG_IEN; flagVal = 1'b0;
							lastStep = 1'b1;
						end
					endcase
				end
				OP_RST: begin // RST / RESET: jump to RESET vector
					case (ex)
						4'd0: begin r_intDOut = 1'b1; r_intD = VEC_RESET; mc_write_low = 1'b1; end
						4'd1: begin r_intDOut = 1'b1; r_intD = 8'hFF; mc_write_high = 1'b1; end
						4'd2: readMC(REG_PCL);
						default: begin readMC(REG_PCH); lastStep = 1'b1; end
					endcase
				end
				8'hF8: copy16(LEFT16_BC, REG_SPL); // LDS BC
				8'hF9: begin // LDS (BC)
					case (ex)
						4'd0: begin regAddrSel = ADDR_BC; mc_write_full = 1'b1; end
						4'd1: readMC(REG_SPL);
						4'd2: readMC(REG_SPH);
						default: lastStep = 1'b1;
					endcase
				end
				8'hFA: copy16(LEFT16_SP, REG_C); // LBCS
				8'hFB: setFlag(FLAG_C, 1'b0); // CLC
				8'hFC: setFlag(FLAG_C, 1'b1); // SEC
				8'hFD: incDec16(1'b0, LEFT16_BC, REG_C); // INC BC
				8'hFE: incDec16(1'b1, LEFT16_BC, REG_C); // DEC BC
				default: lastStep = 1'b1; // LDS NN ends during fetch; FF handled above
			endcase
		end
		endcase
	end
end

// ---------------------------------------------------------------------------
// Sequencing and flags
// ---------------------------------------------------------------------------

always @(posedge sysClock) begin
	r_nmiPrev <= nmiReq;
	if (nmiEdge) r_nmiPending <= 1'b1;

	// Opcode fetch; K is cleared by every instruction except BRK
	if (!r_init && (r_step == S1N)) begin
		r_opcode <= intD;
		r_breakFlag <= 1'b0;
	end

	if (!resetReq) begin
		// RESET: abort and run the RST microcode (repeats while held low)
		r_init <= 1'b0;
		r_opcode <= OP_RST;
		r_step <= S2N;
		r_hwInt <= 1'b1;
	end
	else if (stall) begin
		// hold step
	end
	else if (lastStep) begin
		r_init <= 1'b0;
		if (r_nmiPending || nmiEdge) begin
			r_opcode <= OP_BRK;
			r_vector <= VEC_NMI;
			r_hwInt <= 1'b1;
			r_step <= S2N;
			r_nmiPending <= 1'b0;
		end
		else if (!irq && r_irqEn) begin
			r_opcode <= OP_BRK;
			r_vector <= VEC_IRQ;
			r_hwInt <= 1'b1;
			r_step <= S2N;
		end
		else begin
			r_vector <= VEC_IRQ;		// BRK uses the IRQ vector
			r_hwInt <= 1'b0;
			r_step <= S1N;
		end
	end
	else r_step <= r_step + 4'd1;

	if (szOutEn) begin
		r_signFlag <= aluSign;
		r_zeroFlag <= aluZero;
	end
	if (z16En) r_zeroFlag <= aluZero16;
	if (cOutEn) r_carryFlag <= cInv ? ~carryOut : carryOut;

	case (flagSel)
		FLAG_C:   r_carryFlag <= flagVal;
		FLAG_D:   r_decMode <= flagVal;
		FLAG_IEN: r_irqEn <= flagVal;
		FLAG_K:   r_breakFlag <= flagVal;
		default: ; // none
	endcase

	// Writing P (PLP, RTI) loads the flags from the bus: S Z C I D K - -
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
