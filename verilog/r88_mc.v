// Rocket88 - A New 8-Bit Architecture
// Module: r88_mc
// Description: Memory Controller
// See https://github.com/SlithyMatt/rocket88 for current code and documentation

module r88_mc (
	input sysClock,
	output [15:0] extA,
	inout [7:0] extD,
	input readMem,
	input writeMem,
	inout [7:0] intD,
	input mc_use_regAddr,		// drive extA from regAddr instead of internal address register
	input mc_write_low,			// load address low byte from intD
	input mc_write_high,			// load address high byte from intD
	input mc_write_full,			// load full address from regAddr (MC_WRITE_FULL)
	input mc_inc,					// increment internal address register
	input [15:0] regAddr,
	output [15:0] mcAddr			// internal address register value (for loading PC)
);

// Data bus tri-state buffers
assign extD = writeMem ? intD : 8'bz;
assign intD = readMem ? extD : 8'bz;

// External address bus register
reg [15:0] r_extA = 16'h0000;
assign extA = mc_use_regAddr ? regAddr : r_extA;
assign mcAddr = r_extA;

// Latch address at the end of the step
always @(posedge sysClock) begin
	if (mc_write_full) r_extA <= regAddr;
	else if (mc_inc) r_extA <= r_extA + 16'd1;
	else begin
		if (mc_write_low) r_extA[7:0] <= intD;
		if (mc_write_high) r_extA[15:8] <= intD;
	end
end

endmodule
