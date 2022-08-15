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
	output	[15:0] extA,	// external address bus
);

wire [7:0] intD;				// internal data bus
wire mc_write_full;			// write full address to memory controller
wire mc_write_low;			// write low byte of address to memory controller
wire mc_write_high;			// write high byte of address to memory controller
wire [15:0] regAddr;			// address register value
wire [7:0] regRight;			// right register value
wire [7:0] regLeft;			// left register value
wire [2:0] aluOp;				// arithmetic logic unit (ALU) operation
wire [1:0] regRightSel;		// right register selection
wire [1:0] regLeftSel;		// left register selection
wire [1:0] regAddrSel;		// address register selection
wire carryIn;					// carry input value
wire carryOut;					// carry output value
wire invOut;					// invert ALU output
wire decMode;					// decimal mode
wire carryInEn;				// carry in enable
wire szOutEn;					// sign/zero out enable

r88_mc memory_controller (
	sysClock(sysClock),
	extA(extA),
	extD(extD),
	readMem(readMem),
	writeMem(writeMem),
	intD(intD),
	mc_write_full(mc_write_full),
	mc_write_low(mc_write_low),
	mc_write_high(mc_write_high),
	regAddr(regAddr)
);

r88_regblock registers (
	
};

endmodule
