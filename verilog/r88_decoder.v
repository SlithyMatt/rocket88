// Rocket88 - A New 8-Bit Architecture
// Module: r88_decoder
// Description: Instruction Decoder
// See https://github.com/SlithyMatt/rocket88 for current code and documentation

module r88_decoder (
	input 		sysClock,
	output 		readMem,
	output 		writeMem,
	inout 		[7:0] intD,
	input 		resetReq,
	input 		nmiReq,
	input			irq,
	output 		mc_use_regAddr,
	output		mc_write_low,
	output   	mc_write_high,
	output 		[2:0] aluOp,
	output		[1:0] regRightSel,
	output		[1:0] regLeftSel,
	output		regLeft16,
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
	output		aluResult,
	output 		loadResult,
	output 		incPC 		// can only be set when regRead and regWrite are clear
);

// flags
reg r_szOutEn = 0;				// sign/zero out enable
reg r_carryFlag = 0;
reg r_signFlag = 0;
reg r_zeroFlag = 1;
reg r_breakFlag = 0;
reg r_irqEn = 1;
reg r_decMode = 0;
reg r_regLeft16 = 0;

// internal
reg [7:0] r_opcode = 8'00h;
reg [3:0] r_cycle = 4'0h;			// cycle within instruction
reg r_outputIntD = 0;
reg r_init = 1;

// control outputs
reg r_readMem = 1;
reg r_writeMem = 0;
reg r_mc_use_regAddr = 1;
reg r_mc_write_low = 0;
reg r_mc_write_high = 0;
reg [2:0] r_aluOp = 3'000b;
reg [1:0] r_regRightSel = 2'00b;
reg [1:0] r_regLeftSel = 2'00b;
reg r_regLeft16 = 0;
reg [1:0] r_regAddrSel = 2'00b;
reg r_carryIn = 0;
reg r_invOut = 0;
reg r_carryInEn = 0;
reg [3:0] r_regSel = 4'7h;
reg r_regWrite = 1;
reg r_regRead = 0;
reg r_rightSel = 0;
reg r_aluResult = 0;
reg r_incPC = 0;
reg r_intD = 0;

assign carryIn = r_carryFlag;
assign signFlag = r_signFlag;
assign zeroFlag = r_zeroFlag;
assign breakFlag = r_breakFlag;
assign irqEn = r_irqEn;
assign decMode = r_decMode;
assign regLeft16 = r_regLeft16;

assign readMem = r_readMem;
assign writeMem = r_writeMem;
assign mc_use_regAddr = r_mc_use_regAddr;
assign mc_write_low = r_mc_write_low;
assign mc_write_high = r_mc_write_high;
assign aluOp = r_aluOp;
assign regRightSel = r_regRightSel;
assign regLeftSel = r_regLeftSel;
assign regLeft16 = r_regLeft16;
assign regAddrSel = r_regAddrSel;
assign carryIn = r_carryIn;
assign invOut = r_invOut;
assign carryInEn = r_carryInEn;
assign regSel = r_regSel;
assign regWrite = r_regWrite;
assign regRead = r_regRead;
assign rightSel = r_rightSel;
assign aluResult = r_aluResult;
assign incPC = r_incPC;
assign intD = r_outputIntD ? r_intD : 8'Z;

always @ negedge sysClock begin
	if (r_init and (r_cycle == 4'0h)) r_cycle <= 4'1h;
end

always @ posedge sysClock begin
	if (r_init and (r_cycle == 4'1h)) begin
		r_regSel = 4'8h;
		r_regAddrSel = 1;
		r_init = 0;
		r_cycle = 4'0h;
	end
end

always @ sysClock begin
	if (!r_init) begin
		case (r_cycle)
			4'0h: begin
				r_outputIntD <= 0;
				r_readMem <= 1;
				r_writeMem <= 0;
				r_mc_use_regAddr <= 1;
				r_mc_write_low <= 0;
				r_mc_write_high <= 0;
				r_aluOp <= 3'0;
				r_regRightSel <= 2'0;
				r_regLeftSel <= 2'0;
				r_regLeft16 <= 0;
				r_regAddrSel <= 2'2;
				r_invOut <= 0;
				r_carryInEn <= 0;
				r_regSel <= 0;
				r_regWrite <= 0;
				r_regRead <= 0;
				r_szOutEn <= 0;
				r_rightSel <= 0;
				r_incPC <= 0;
				r_aluResult <= 0;
				r_loadResult <= 0;
				r_cycle <= 4'1h;			
			end
			4'1h: begin
				r_opcode = intD;
				r_readMem = 0;				
				r_incPC = 1;
				// TODO check for single byte NOPs
				r_cycle <= 4'2h
			end
		endcase
	end
end

endmodule
