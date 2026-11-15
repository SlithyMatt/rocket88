// Rocket88 - A New 8-Bit Architecture
// Testbench: tb_program
// Description: Runs a program image and logs every instruction fetch and
//              memory write, for tools/check_doc_examples.py.
//
//   vvp -n tb.vvp +hex=<file for $readmemh> +stop=<hex address> [+max=<clocks>]
//
// Output lines:
//   F <PC> <A> <B> <C> <DD> <EE> <SP> <S> <Z> <C> <D> <I> <clock>   at each opcode fetch
//     (<clock> is the decimal clock count, for measuring instruction timing)
//   W <address> <data>                                       at each memory write
//   END | TIMEOUT

module tb_program;

reg sysClock = 0;
always #10 sysClock = ~sysClock;

wire [7:0] extD;
wire [15:0] extA;
wire readMem, writeMem;

reg [7:0] mem [0:65535];

assign extD = readMem ? mem[extA] : 8'bz;
always @(posedge sysClock) if (writeMem) mem[extA] <= extD;

Rocket88 cpu (
	.extD(extD),
	.readMem(readMem),
	.writeMem(writeMem),
	.resetReq(1'b1),
	.nmiReq(1'b1),
	.irq(1'b1),
	.sysClock(sysClock),
	.extA(extA)
);

reg [8*256-1:0] hexFile;
reg [15:0] stopAddr;
integer maxClocks;
integer clocks = 0;
integer i;

initial begin
	for (i = 0; i < 65536; i = i + 1) mem[i] = 8'h00;
	if (!$value$plusargs("hex=%s", hexFile)) begin
		$display("usage: +hex=<file> +stop=<address>");
		$finish;
	end
	if (!$value$plusargs("stop=%h", stopAddr)) stopAddr = 16'hFFFF;
	if (!$value$plusargs("max=%d", maxClocks)) maxClocks = 20000;
	$readmemh(hexFile, mem);
end

always @(negedge sysClock) begin
	clocks = clocks + 1;
	if (writeMem) $display("W %h %h", extA, extD);
	if (!cpu.decoder.r_init && (cpu.decoder.r_step == 0)) begin
		$display("F %h %h %h %h %h %h %h %b %b %b %b %b %0d",
			cpu.registers.r_PC, cpu.registers.r_A, cpu.registers.r_B, cpu.registers.r_C,
			cpu.registers.r_DD, cpu.registers.r_EE, cpu.registers.r_SP,
			cpu.decoder.r_signFlag, cpu.decoder.r_zeroFlag, cpu.decoder.r_carryFlag,
			cpu.decoder.r_decMode, ~cpu.decoder.r_irqEn, clocks);
		if (cpu.registers.r_PC == stopAddr) begin
			$display("END");
			$finish;
		end
	end
	if (clocks >= maxClocks) begin
		$display("TIMEOUT");
		$finish;
	end
end

endmodule
