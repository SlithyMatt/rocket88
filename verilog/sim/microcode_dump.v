// Rocket88 - A New 8-Bit Architecture
// Testbench: microcode_dump
// Description: Prints the decoder's microcode as a tab-separated table, one
//              row per step, for every opcode (plus Init, IRQ and NMI).
//              Used by tools/update_microcode_sheet.py to keep the Microcode
//              sheet of Rocket88.ods in sync with r88_decoder.v.
//
// Run from the verilog directory:
//   iverilog -g2005 -o sim/dump.vvp sim/microcode_dump.v r88_decoder.v && vvp -n sim/dump.vvp
//
// Row format: group <tab> variant <tab> step <tab> control values...
// group is the opcode in hex, or INIT / IRQ / NMI. variant is "-", or
// "taken" / "not taken" for conditional jumps and subroutine calls.

module microcode_dump;

wire [7:0] intD;
wire readMem, writeMem, mc_use_regAddr, mc_write_low, mc_write_high, mc_write_full, mc_inc;
wire [2:0] aluOp;
wire [1:0] regRightSel;
wire [2:0] regLeftSel;
wire regLeft16;
wire [1:0] regAddrSel;
wire carryIn, aluCarryIn, invOut, decMode, aluDecMode, carryInEn;
wire [3:0] regSel;
wire regWrite, regRead, signFlag, zeroFlag, rightSel, breakFlag, irqEn;
wire aluResult, loadResult, incPC, pcLoadMC, incSP, decSP;
wire [1:0] regExchange;

r88_decoder dec (
	.sysClock(1'b0),
	.readMem(readMem),
	.writeMem(writeMem),
	.intD(intD),
	.resetReq(1'b1),
	.nmiReq(1'b1),
	.irq(1'b1),
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
	.carryOut(1'b0),
	.aluSign(1'b0),
	.aluZero(1'b0),
	.aluZero16(1'b0),
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

localparam FLAG_C = 3'd1, FLAG_D = 3'd2, FLAG_IEN = 3'd3, FLAG_K = 3'd4;

// Value of a flag-set column: the value written, or X if untouched
function [8*1-1:0] flagCol(input [2:0] which);
	flagCol = (dec.flagSel == which) ? (dec.flagVal ? "1" : "0") : "X";
endfunction

// Print the current step as one row
task row(input [8*8-1:0] group, input [8*10-1:0] variant, input isInit);
	reg [8*4-1:0] intDStr;
	reg [8*1-1:0] cinStr, decStr, kStr, ienStr, setCStr, setDStr;
	begin
		if (dec.r_intDOut) $sformat(intDStr, "$%02h", dec.r_intD);
		else intDStr = "Z";
		// ALU carry in: X when unused, 1 when forced, C when from the carry flag
		cinStr = !carryInEn ? "X" : (dec.forceCin ? "1" : "C");
		// ALU decimal mode: X unless an 8-bit add/subtract, then D (flag) or 0 (binary)
		decStr = (((aluOp == 3'd3) || (aluOp == 3'd4)) && !regLeft16) ? (dec.decEn ? "D" : "0") : "X";
		kStr = flagCol(FLAG_K);
		ienStr = flagCol(FLAG_IEN);
		setCStr = flagCol(FLAG_C);
		setDStr = flagCol(FLAG_D);
		if (isInit) begin
			// power-on flag values
			cinStr = "0"; decStr = "0"; kStr = "0"; ienStr = "1"; setCStr = "0"; setDStr = "0";
		end
		else if (dec.r_step == 0) kStr = "0";		// every opcode fetch clears K
		$display("%0s\t%0s\t%0d%0s\t%0s\t%b\t%b\t%b\t%b\t%b\t%0d\t%0d\t%0d\t%b\t%0d\t%0s\t%b\t%0s\t%b\t%0d\t%b\t%b\t%b\t%b\t%b\t%b\t%b\t%0s\t%0s\t%b\t%b\t%b\t%b\t%b\t%0d\t%b\t%b\t%b\t%0s\t%0s\t%b",
			group, variant,
			(dec.r_step >> 1) + 1, dec.r_step[0] ? "p" : "n",
			intDStr, readMem, writeMem, mc_use_regAddr, mc_write_low, mc_write_high,
			aluOp, regRightSel, regLeftSel, regLeft16, regAddrSel,
			cinStr, invOut, decStr, carryInEn,
			regSel, regWrite, regRead, dec.szOutEn, rightSel, incPC, aluResult, loadResult,
			kStr, ienStr,
			mc_write_full, mc_inc, pcLoadMC, incSP, decSP, regExchange,
			dec.z16En, dec.cOutEn, dec.cInv, setCStr, setDStr, dec.stall);
	end
endtask

// Print every step of one microcode sequence, starting at step `start`
task sequence(input [8*8-1:0] group, input [8*10-1:0] variant, input [7:0] op, input [3:0] start,
              input hwInt, input [7:0] vector);
	integer n;
	begin
		dec.r_init = 1'b0;
		dec.r_opcode = op;
		dec.r_hwInt = hwInt;
		dec.r_vector = vector;
		dec.r_step = start;
		#1;
		n = 0;
		while (n < 16) begin
			row(group, variant, 1'b0);
			if (dec.lastStep) n = 16;
			else begin
				dec.r_step = dec.r_step + 4'd1;
				#1;
				n = n + 1;
			end
		end
	end
endtask

// Set the flag a conditional jump on row 5x/6x/7x tests
task jumpFlag(input [3:0] hi, input value);
	begin
		dec.r_zeroFlag = (hi == 4'h5) ? value : 1'b0;
		dec.r_signFlag = (hi == 4'h6) ? value : 1'b0;
		dec.r_carryFlag = (hi == 4'h7) ? value : 1'b0;
	end
endtask

integer op;
reg [7:0] o;
reg [8*8-1:0] g;
reg isNN;
reg isCond;

initial begin
	$display("group\tvariant\tStep\tintD\treadMem\twriteMem\tmc_use_regAddr\tmc_write_low\tmc_write_high\taluOp\tregRightSel\tregLeftSel\tregLeft16\tregAddrSel\tcarryIn\tinvOut\tdecMode\tcarryInEn\tregSel\tregWrite\tregRead\tszOutEn\trightSel\tincPC\taluResult\tloadResult\tbreakFlag\tirqEn\tmc_write_full\tmc_inc\tpcLoadMC\tincSP\tdecSP\tregExchange\tz16En\tcOutEn\tcInv\tsetCarry\tsetDecimal\tstall");

	dec.r_zeroFlag = 1'b0;
	dec.r_signFlag = 1'b0;
	dec.r_carryFlag = 1'b0;

	// Power-on Init
	dec.r_init = 1'b1;
	dec.r_step = 4'd0;
	#1 row("INIT", "-", 1'b1);
	dec.r_step = 4'd1;
	#1 row("INIT", "-", 1'b1);

	for (op = 0; op < 256; op = op + 1) begin
		o = op;
		$sformat(g, "%02h", o);
		isNN = ((o[2:0] == 3'd5) && (o[7:4] != 4'hF)) || (o == 8'hF7);
		isCond = (o[7:4] >= 4'h5) && (o[7:4] <= 4'h7) && (o[2:0] >= 3'd4) && (o[2:0] <= 3'd6);
		if (o == 8'h00) sequence(g, "-", o, 4'd0, 1'b0, 8'hFA);					// opcode fetch
		else if ((o == 8'h05) || (o == 8'hF7)) sequence(g, "-", o, 4'd2, 1'b0, 8'hFA);	// NN fetch
		else if (isCond) begin
			// relative mode jumps when the flag is clear, NN/(BC) when it is set
			jumpFlag(o[7:4], o[2:0] != 3'd4);
			sequence(g, "taken", o, isNN ? 4'd6 : 4'd2, 1'b0, 8'hFA);
			jumpFlag(o[7:4], o[2:0] == 3'd4);
			sequence(g, "not taken", o, isNN ? 4'd6 : 4'd2, 1'b0, 8'hFA);
			jumpFlag(4'h0, 1'b0);
		end
		else sequence(g, "-", o, isNN ? 4'd6 : 4'd2, 1'b0, 8'hFA);
	end

	// Hardware interrupts run the BRK microcode with their own vector and no K
	sequence("IRQ", "-", 8'hF5, 4'd2, 1'b1, 8'hFA);
	sequence("NMI", "-", 8'hF5, 4'd2, 1'b1, 8'hFC);
	$finish;
end

endmodule
