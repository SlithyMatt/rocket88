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


endmodule
