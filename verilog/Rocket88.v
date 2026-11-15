// Rocket88 - A New 8-Bit Architecture
// Module: Rocket88
// Description: Top-Level of Core
// See https://github.com/SlithyMatt/rocket88 for current code and documentation
//
// Each rising edge of sysClock is one microcode step (one row of the
// Microcode sheet in Rocket88.ods), so sysClock runs at twice the rate of a
// full n/p cycle. resetReq, nmiReq and irq are active low.
module Rocket88 (
	inout 	[7:0] extD, 	// external data bus
	output	readMem,			// read memory request
	output 	writeMem,		// write memory request
	input		resetReq,		// reset request (active low)
	input		nmiReq,			// non-maskable interrupt (NMI) request (active low)
	input		irq,				// maskable interrupt request (IRQ) (active low)
	input		sysClock,		// system clock
	output	[15:0] extA 	// external address bus
);

wire [7:0] intD;				// internal data bus
wire [7:0] highOut;			// ALU output high byte
wire mc_use_regAddr;			// route regAddr to address bus
wire mc_write_low;			// write low byte of address to memory controller
wire mc_write_high;			// write high byte of address to memory controller
wire mc_write_full;			// load full address from regAddr into memory controller
wire mc_inc;					// increment memory controller address
wire [15:0] mcAddr;			// memory controller address register value
wire [15:0] regAddr;			// address register value
wire [7:0] regRight;			// right register value
wire [15:0] regLeft;			// left register value
wire [2:0] aluOp;				// arithmetic logic unit (ALU) operation
wire [1:0] regRightSel;		// right register selection
wire [2:0] regLeftSel;		// left register selection
wire regLeft16;				// left register 16-bits
wire [1:0] regAddrSel;		// address register selection
wire carryIn;					// carry flag value
wire aluCarryIn;				// carry into ALU
wire carryOut;					// ALU carry output value
wire aluSign;					// ALU result sign
wire aluZero;					// ALU result zero (8-bit)
wire aluZero16;				// ALU result zero (16-bit)
wire invOut;					// invert ALU output
wire decMode;					// decimal flag
wire aluDecMode;				// decimal mode for ALU
wire carryInEn;				// carry in enable
wire [3:0] regSel;			// register select
wire regWrite;					// write to register
wire regRead;					// read from register
wire signFlag;					// sign flag
wire zeroFlag;					// zero flag
wire rightSel;					// right value select (regRight/intD)
wire breakFlag;				// break flag
wire irqEn;						// IRQ enable
wire aluResult;				// put ALU result on internal data bus
wire loadResult;				// disable ALU operation and load last ALU result
wire incPC;						// increment the Program Counter
wire pcLoadMC;					// load the Program Counter from the memory controller address
wire incSP;						// increment the Stack Pointer
wire decSP;						// decrement the Stack Pointer
wire [1:0] regExchange;		// exchange BC with DD or EE

r88_mc memory_controller (
	.sysClock(sysClock),
	.extA(extA),
	.extD(extD),
	.readMem(readMem),
	.writeMem(writeMem),
	.intD(intD),
	.mc_use_regAddr(mc_use_regAddr),
	.mc_write_low(mc_write_low),
	.mc_write_high(mc_write_high),
	.mc_write_full(mc_write_full),
	.mc_inc(mc_inc),
	.regAddr(regAddr),
	.mcAddr(mcAddr)
);

r88_regblock registers (
	.sysClock(sysClock),
	.intD(intD),
	.highOut(highOut),
	.regSel(regSel),
	.regRightSel(regRightSel),
	.regLeftSel(regLeftSel),
	.regLeft16(regLeft16),
	.regAddrSel(regAddrSel),
	.regWrite(regWrite),
	.regRead(regRead),
	.regAddr(regAddr),
	.regRight(regRight),
	.regLeft(regLeft),
	.signFlag(signFlag),
	.zeroFlag(zeroFlag),
	.carryIn(carryIn),
	.decMode(decMode),
	.breakFlag(breakFlag),
	.irqEn(irqEn),
	.incPC(incPC),
	.pcLoadMC(pcLoadMC),
	.mcAddr(mcAddr),
	.incSP(incSP),
	.decSP(decSP),
	.regExchange(regExchange)
);

r88_alu alu (
	.sysClock(sysClock),
	.intD(intD),
	.highOut(highOut),
	.regRight(regRight),
	.regLeft(regLeft),
	.regLeft16(regLeft16),
	.aluOp(aluOp),
	.carryIn(aluCarryIn),
	.carryOut(carryOut),
	.signOut(aluSign),
	.zeroOut(aluZero),
	.zero16Out(aluZero16),
	.invOut(invOut),
	.decMode(aluDecMode),
	.carryInEn(carryInEn),
	.rightSel(rightSel),
	.aluResult(aluResult),
	.loadResult(loadResult)
);

r88_decoder decoder (
	.sysClock(sysClock),
	.readMem(readMem),
	.writeMem(writeMem),
	.intD(intD),
	.resetReq(resetReq),
	.nmiReq(nmiReq),
	.irq(irq),
	.mc_use_regAddr(mc_use_regAddr),
	.mc_write_low(mc_write_low),
	.mc_write_high(mc_write_high),
	.mc_write_full(mc_write_full),
	.mc_inc(mc_inc),
	.aluOp(aluOp),
	.regRightSel(regRightSel),
	.regLeftSel(regLeftSel),
	.regLeft16(regLeft16),
	.regAddrSel(regAddrSel),
	.carryIn(carryIn),
	.aluCarryIn(aluCarryIn),
	.carryOut(carryOut),
	.aluSign(aluSign),
	.aluZero(aluZero),
	.aluZero16(aluZero16),
	.invOut(invOut),
	.decMode(decMode),
	.aluDecMode(aluDecMode),
	.carryInEn(carryInEn),
	.regSel(regSel),
	.regWrite(regWrite),
	.regRead(regRead),
	.signFlag(signFlag),
	.zeroFlag(zeroFlag),
	.rightSel(rightSel),
	.breakFlag(breakFlag),
	.irqEn(irqEn),
	.aluResult(aluResult),
	.loadResult(loadResult),
	.incPC(incPC),
	.pcLoadMC(pcLoadMC),
	.incSP(incSP),
	.decSP(decSP),
	.regExchange(regExchange)
);

endmodule
