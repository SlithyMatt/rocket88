// Rocket88 - A New 8-Bit Architecture
// Testbench: tb_Rocket88
// Description: 64K memory model plus a short program exercising the
//              opcodes microcoded so far (NOPs and rows 1x-3x).
//
// Run from the verilog directory:
//   iverilog -g2005 -o sim/tb.vvp sim/tb_Rocket88.v Rocket88.v r88_*.v && vvp sim/tb.vvp

module tb_Rocket88;

reg sysClock = 0;
always #10 sysClock = ~sysClock;

wire [7:0] extD;
wire [15:0] extA;
wire readMem, writeMem;

reg [7:0] mem [0:65535];

// Memory model: asynchronous read, write latched at end of step
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

integer errors = 0;
integer i;
reg [15:0] pc;

// Bus contention monitor: an X (not Z) bit on intD means two drivers disagree
integer b;
always @(negedge sysClock) begin
	for (b = 0; b < 8; b = b + 1) begin
		if (cpu.intD[b] === 1'bx) begin
			$display("FAIL intD contention at t=%0t, step=%0d opcode=$%02h", $time, cpu.decoder.r_step, cpu.decoder.r_opcode);
			errors = errors + 1;
		end
	end
end

task load(input [7:0] b);
	begin
		mem[pc] = b;
		pc = pc + 1;
	end
endtask

task check8(input [8*24-1:0] name, input [7:0] actual, input [7:0] expected);
	begin
		if (actual !== expected) begin
			$display("FAIL %0s: got $%02h, expected $%02h", name, actual, expected);
			errors = errors + 1;
		end
		else $display("ok   %0s = $%02h", name, actual);
	end
endtask

task check1(input [8*24-1:0] name, input actual, input expected);
	begin
		if (actual !== expected) begin
			$display("FAIL %0s: got %b, expected %b", name, actual, expected);
			errors = errors + 1;
		end
		else $display("ok   %0s = %b", name, actual);
	end
endtask

// Run until PC reaches the given address at an opcode fetch
task run_to(input [15:0] addr);
	integer n;
	begin
		n = 0;
		while (!((cpu.decoder.r_step == 0) && !cpu.decoder.r_init && (cpu.registers.r_PC == addr)) && (n < 1000)) begin
			@(negedge sysClock);
			n = n + 1;
		end
		if (n >= 1000) begin
			$display("FAIL timeout waiting for PC=$%04h (PC=$%04h)", addr, cpu.registers.r_PC);
			errors = errors + 1;
		end
	end
endtask

initial begin
	for (i = 0; i < 65536; i = i + 1) mem[i] = 8'h00;

	// RESET vector -> $0200
	mem[16'hFFFE] = 8'h00;
	mem[16'hFFFF] = 8'h02;
	mem[16'h1234] = 8'h80;

	pc = 16'h0200;
	load(8'h14); load(8'h42);               // $0200 LDA #$42
	load(8'h24); load(8'h10);               // $0202 LDB #$10
	load(8'h34); load(8'h05);               // $0204 LDC #$05      BC = $1005
	load(8'h1E);                            // $0206 STA (BC)      [$1005] = $42
	load(8'h1D); load(8'h00); load(8'h30);  // $0207 STA $3000     [$3000] = $42
	load(8'h00);                            // $020A NOP
	load(8'h04); load(8'h99);               // $020B NOP+1
	load(8'h0D); load(8'h11); load(8'h22);  // $020D NOP+2
	load(8'h25); load(8'h34); load(8'h12);  // $0210 LDB $1234     B = $80, S=1
	load(8'h31);                            // $0213 LDC A         C = $42
	load(8'h3F);                            // $0214 PHC           SP = $FFF8, [$FFF8] = $42
	load(8'h10);                            // $0215 LDAZ          A = 0, Z=1
	load(8'h17);                            // $0216 PLA           A = $42, SP = $FFF9
	load(8'h1B);                            // $0217 CPA C         equal: Z=1 C=1
	load(8'h2D); load(8'h01); load(8'h30);  // $0218 STB $3001     [$3001] = $80
	load(8'h3C); load(8'h50);               // $021B CPC #$50      $42 < $50: Z=0 C=0 S=1
	load(8'h26);                            // $021D LDB (BC)      BC=$8042 -> B = 0
	load(8'h00);                            // $021E NOP

	run_to(16'h0200);
	$display("--- reset vector");
	check8("PCL after init", cpu.registers.r_PC[7:0], 8'h00);

	run_to(16'h0207);
	$display("--- LDx #N, STA (BC)");
	check8("A", cpu.registers.r_A, 8'h42);
	check8("B", cpu.registers.r_B, 8'h10);
	check8("C", cpu.registers.r_C, 8'h05);
	check8("[$1005]", mem[16'h1005], 8'h42);

	run_to(16'h020A);
	$display("--- STA NN");
	check8("[$3000]", mem[16'h3000], 8'h42);

	run_to(16'h0210);
	$display("--- NOP variants skip operands");
	check8("A unchanged", cpu.registers.r_A, 8'h42);

	run_to(16'h0213);
	$display("--- LDB NN");
	check8("B", cpu.registers.r_B, 8'h80);
	check1("S", cpu.decoder.r_signFlag, 1'b1);
	check1("Z", cpu.decoder.r_zeroFlag, 1'b0);

	run_to(16'h0215);
	$display("--- LDC A, PHC");
	check8("C", cpu.registers.r_C, 8'h42);
	check8("SPL", cpu.registers.r_SP[7:0], 8'hF8);
	check8("SPH", cpu.registers.r_SP[15:8], 8'hFF);
	check8("[$FFF8]", mem[16'hFFF8], 8'h42);

	run_to(16'h0216);
	$display("--- LDAZ");
	check8("A", cpu.registers.r_A, 8'h00);
	check1("Z", cpu.decoder.r_zeroFlag, 1'b1);

	run_to(16'h0217);
	$display("--- PLA");
	check8("A", cpu.registers.r_A, 8'h42);
	check8("SPL", cpu.registers.r_SP[7:0], 8'hF9);
	check1("Z", cpu.decoder.r_zeroFlag, 1'b0);

	run_to(16'h0218);
	$display("--- CPA C (equal)");
	check1("Z", cpu.decoder.r_zeroFlag, 1'b1);
	check1("C", cpu.decoder.r_carryFlag, 1'b1);
	check8("A unchanged", cpu.registers.r_A, 8'h42);

	run_to(16'h021B);
	$display("--- STB NN");
	check8("[$3001]", mem[16'h3001], 8'h80);

	run_to(16'h021D);
	$display("--- CPC #N (less than)");
	check1("Z", cpu.decoder.r_zeroFlag, 1'b0);
	check1("C", cpu.decoder.r_carryFlag, 1'b0);
	check1("S", cpu.decoder.r_signFlag, 1'b1);

	run_to(16'h021E);
	$display("--- LDB (BC)");
	check8("B", cpu.registers.r_B, 8'h00);
	check1("Z", cpu.decoder.r_zeroFlag, 1'b1);

	if (errors == 0) $display("PASS: all checks passed");
	else $display("%0d check(s) FAILED", errors);
	$finish;
end

endmodule
