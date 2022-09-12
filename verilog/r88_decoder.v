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
	output		irqEn,
	output		aluResult
);

reg szOutEn = 0;					// sign/zero out enable
reg r_carryFlag = 0;
reg r_signFlag = 0;
reg r_zeroFlag = 1;
reg r_breakFlag = 0;
reg r_irqEn = 1;
reg r_decMode = 0;

assign carryIn = r_carryFlag;
assign signFlag = r_signFlag;
assign zeroFlag = r_zeroFlag;
assign breakFlag = r_breakFlag;
assign irqEn = r_irqEn;
assign decMode = r_decMode;



endmodule
