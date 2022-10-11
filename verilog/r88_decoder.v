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
wire extra_nop;

// internal
reg [7:0] r_opcode = 8'h00;
reg [3:0] r_cycle = 4'h0;			// cycle within instruction
reg r_outputIntD = 0;
reg r_init = 1;

// control outputs
reg r_readMem = 1;
reg r_writeMem = 0;
reg r_mc_use_regAddr = 1;
reg r_mc_write_low = 0;
reg r_mc_write_high = 0;
reg [2:0] r_aluOp = 3'b000;
reg [1:0] r_regRightSel = 2'b00;
reg [1:0] r_regLeftSel = 2'b00;
reg r_regLeft16 = 0;
reg [1:0] r_regAddrSel = 2'b00;
reg r_carryIn = 0;
reg r_invOut = 0;
reg r_carryInEn = 0;
reg [3:0] r_regSel = 4'h7;
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
	if (r_init and (r_cycle == 4'h0)) r_cycle <= 4'h1;
end

always @ posedge sysClock begin
	if (r_init and (r_cycle == 4'h1)) begin
		r_regSel = 4'h8;
		r_regAddrSel = 1;
		r_init = 0;
		r_cycle = 4'h0;
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
				r_cycle <= 4'h1;			
			end
			4'1h: begin
				r_opcode = intD;
				r_readMem = 0;				
				r_incPC = 1;
				// check for single byte NOPs [so much room for expansion!]
				if ((r_opcode[7:1] != 7'h02) and ((r_opcode[7:4] == 4'0) || 
					(r_opcode == 8'h41) || (r_opcode == 8'h42) || (r_opcode == 8'h43) || (r_opcode == 8'h47) || 
					(r_opcode == 8'h49) || (r_opcode == 8'h4A) || (r_opcode == 8'h4B) || (r_opcode == 8'h4F) || 
					(r_opcode == 8'h51) || (r_opcode == 8'h52) || (r_opcode == 8'h53) || (r_opcode == 8'h57) || 
					(r_opcode == 8'h59) || (r_opcode == 8'h5A) || (r_opcode == 8'h5B) || (r_opcode == 8'h5F) ||
					(r_opcode == 8'h61) || (r_opcode == 8'h62) || (r_opcode == 8'h63) || (r_opcode == 8'h67) || 
					(r_opcode == 8'h69) || (r_opcode == 8'h6A) || (r_opcode == 8'h6B) || (r_opcode == 8'h6F) || 
					(r_opcode == 8'h71) || (r_opcode == 8'h72) || (r_opcode == 8'h73) || (r_opcode == 8'h77) || 
					(r_opcode == 8'h79) || (r_opcode == 8'h7A) || (r_opcode == 8'h7B) || (r_opcode == 8'h7F) ||
					(r_opcode == 8'hA0) || (r_opcode == 8'hA4) || (r_opcode == 8'hA8) || (r_opcode == 8'hAC) ||
					(r_opcode == 8'hB0) || (r_opcode == 8'hB4) || (r_opcode == 8'hB8) || (r_opcode == 8'hBC)
				)) r_cycle = 4'h0;
				else r_cycle = 4'h2;
			end
			4'2: begin
				// TODO check for NN addressing (x5, xC, F7)
			end
		endcase
	end
end

endmodule
