// Rocket88 - A New 8-Bit Architecture
// Module: r88_regblock
// Description: Register Block
// See https://github.com/SlithyMatt/rocket88 for current code and documentation

module r88_regblock (
	input 	sysClock,
	inout 	[7:0] extD,
	input 	regSel,
	input 	regWrite,
	input 	regRead,
	output	regAddr,
	output 	regRight,
	output 	regLeft,
	input 	szOutEn,
	output 	signFlag,
	output 	zeroFlag
	input 	carryIn,
	input		decMode,
	input		breakFlag,
	input		irqEn
};



endmodule
