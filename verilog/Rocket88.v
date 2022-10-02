// Rocket88 - A New 8-Bit Architecture
// Module: Rocket88
// Description: Top-Level of Core
// See https://github.com/SlithyMatt/rocket88 for current code and documentation
module Rocket88 (
	inout 	[7:0] extD, 	// external data bus
	output	readMem,			// read memory request
	output 	writeMem,		// write memory request
	input		resetReq,		// reset request
	input		nmiReq,			// non-maskable interrupt (NMI) request
	input		irq,				// maskable interrupt request (IRQ)
	input		sysClock,		// system clock
	output	[15:0] extA 	// external address bus
);

wire [7:0] intD;				// internal data bus
wire [7:0] highOut;			// ALU output high byte
wire mc_use_regAddr;			// route regAddr to address bus
wire mc_write_low;			// write low byte of address to memory controller
wire mc_write_high;			// write high byte of address to memory controller
wire [15:0] regAddr;			// address register value
wire [7:0] regRight;			// right register value
wire [15:0] regLeft;			// left register value
wire [2:0] aluOp;				// arithmetic logic unit (ALU) operation
wire [1:0] regRightSel;		// right register selection
wire [2:0] regLeftSel;		// left register selection
wire regLeft16;				// left register 16-bits
wire [1:0] regAddrSel;		// address register selection
wire carryIn;					// carry input value
wire carryOut;					// carry output value
wire invOut;					// invert ALU output
wire decMode;					// decimal mode
wire carryInEn;				// carry in enable
wire [3:0] regSel;			// register select
wire regWrite;					// write to register
wire regRead;					// read from register
wire signFlag;					// sign flag
wire zeroFlag;					// zero flag
wire rightSel;					// right value select (regLeft/intD)
wire breakFlag;				// break flag
wire irqEn;						// IRQ enable
wire aluResult;				// put ALU result on internal data bus
wire loadResult;				// disable ALU operation and load last ALU result
wire incPC;						// increment the Program Counter

r88_mc memory_controller (
	sysClock(sysClock),
	extA(extA),
	extD(extD),
	readMem(readMem),
	writeMem(writeMem),
	intD(intD),
	mc_use_regAddr(mc_use_regAddr),
	mc_write_low(mc_write_low),
	mc_write_high(mc_write_high),
	regAddr(regAddr)
);

r88_regblock registers (
	sysClock(sysClock),
	intD(intD),
	highOut(highOut),
	regSel(regSel),
	regRightSel(regRightSel),
	regLeftSel(regLeftSel),
	regLeft16(regLeft16),
	regAddrSel(regAddrSel),
	regWrite(regWrite),
	regRead(regRead),
	regAddr(regAddr),
	regRight(regRight),
	regLeft(regLeft),
	signFlag(signFlag),
	zeroFlag(zeroFlag),
	carryIn(carryIn),
	decMode(decMode),
	breakFlag(breakFlag),
	irqEn(irqEn),
	incPC(incPC)
};

r88_alu alu (
	sysClock(sysClock),
	intD(intD),
	highOut(highOut),
	regRight(regRight),
	regLeft(regLeft),
	regLeft16(regLeft16),
	aluOp(aluOp),
	carryIn(carryIn),
	carryOut(carryOut),
	invOut(invOut),
	decMode(decMode),
	carryInEn(carryInEn),
	rightSel(rightSel),
	aluResult(aluResult)
);

r88_decoder decoder (
	sysClock(sysClock),
	readMem(readMem),
	writeMem(writeMem),
	intD(intD),
	resetReq(resetReq),
	nmiReq(nmiReq),
	irq(irq),
	mc_write_full(mc_write_full),
	mc_write_low(mc_write_low),
	mc_write_high(mc_write_high),
	aluOp(aluOp),
	regRightSel(regRightSel),
	regLeftSel(regLeftSel),
	regLeft16(regLeft16),
	regAddrSel(regAddrSel),
	carryIn(carryIn),
	carryOut(carryOut),
	invOut(invOut),
	decMode(decMode),
	carryInEn(carryInEn),
	regSel(regSel),
	regWrite(regWrite),
	regRead(regRead),
	signFlag(signFlag),
	zeroFlag(zeroFlag),
	rightSel(rightSel),
	breakFlag(breakFlag),
	irqEn(irqEn),
	aluResult(aluResult),
	loadResult(loadResult)
};

endmodule
