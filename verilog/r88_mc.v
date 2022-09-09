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
	input mc_write_full,
	input mc_write_low,
	input mc_write_high,
	input [15:0] regAddr
);

// Data bus tri-state buffers
assign extD = writeMem? intD : 8'Z;
assign intD = readMem? extD : 8'Z;

// External address bus register
reg [15:0] r_extA;
assign extA = r_extA;

// Update address bus every clock edge
always @ edge sysClock begin
	if mc_write_full r_extA <= regAddr;
	else if mc_write_low r_extA[7:0] <= intD;
	else if mc_write_high r_extA[15:8] <= intD;
end

endmodule
