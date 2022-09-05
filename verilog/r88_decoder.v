// Rocket88 - A New 8-Bit Architecture
// Module: r88_decoder
// Description: Instruction Decoder
// See https://github.com/SlithyMatt/rocket88 for current code and documentation

module r88_decoder (
	input 		sysClock,
	output 		readMem,
	output 		writeMem,
	input 		[7:0] intD,
	input 		resetReq,
	input 		nmiReq,
	input			irq,
	output 		mc_write_full,
	output		mc_write_low,
	output   	mc_write_high,
	output 		[2:0] aluOp,
	output		[1:0] regRightSel,
	output		[1:0] regLeftSel,
	output		[1:0] regAddrSel,
	output		carryIn,
	input    	carryOut,
	output		invOut,
	output		decMode,
	output		carryInEn,
	output		[3:0]	regSel,
	output		regWrite,
	output		regRead,
	output		signFlag,
	output		zeroFlag,
	output		rightSel,
	output		breakFlag,
	output		irqEn
);

reg szOutEn;					// sign/zero out enable


endmodule
