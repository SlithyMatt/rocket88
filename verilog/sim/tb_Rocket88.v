// Rocket88 - A New 8-Bit Architecture
// Testbench: tb_Rocket88
// Description: 64K memory model plus a self-checking program exercising
//              every documented instruction, the undocumented NOPs, and the
//              IRQ, NMI and RESET pins.
//
// Run from the verilog directory:
//   iverilog -g2005 -o sim/tb.vvp sim/tb_Rocket88.v Rocket88.v r88_*.v && vvp sim/tb.vvp
// Add +trace to print every instruction fetch.

module tb_Rocket88;

reg sysClock = 0;
always #10 sysClock = ~sysClock;

wire [7:0] extD;
wire [15:0] extA;
wire readMem, writeMem;

reg resetReq = 1'b1;
reg nmiReq = 1'b1;
reg irq = 1'b1;

reg [7:0] mem [0:65535];

// Memory model: asynchronous read, write latched at end of step
assign extD = readMem ? mem[extA] : 8'bz;
always @(posedge sysClock) if (writeMem) mem[extA] <= extD;

Rocket88 cpu (
	.extD(extD),
	.readMem(readMem),
	.writeMem(writeMem),
	.resetReq(resetReq),
	.nmiReq(nmiReq),
	.irq(irq),
	.sysClock(sysClock),
	.extA(extA)
);

// Shortcuts into the core
wire [7:0] A = cpu.registers.r_A;
wire [7:0] B = cpu.registers.r_B;
wire [7:0] C = cpu.registers.r_C;
wire [15:0] BC = {cpu.registers.r_B, cpu.registers.r_C};
wire [15:0] DD = cpu.registers.r_DD;
wire [15:0] EE = cpu.registers.r_EE;
wire [15:0] PC = cpu.registers.r_PC;
wire [15:0] SP = cpu.registers.r_SP;
wire fS = cpu.decoder.r_signFlag;
wire fZ = cpu.decoder.r_zeroFlag;
wire fC = cpu.decoder.r_carryFlag;
wire fD = cpu.decoder.r_decMode;
wire fIEn = cpu.decoder.r_irqEn;

// Count instruction fetches at the IRQ/BRK handler
integer irq_entries = 0;
always @(negedge sysClock)
	if (!cpu.decoder.r_init && cpu.decoder.r_step == 0 && cpu.registers.r_PC == 16'h0700)
		irq_entries = irq_entries + 1;

integer errors = 0;
integer checks = 0;
integer i;
integer b;

// Bus contention monitor: an X (not Z) bit on intD means two drivers disagree
always @(negedge sysClock) begin
	for (b = 0; b < 8; b = b + 1) begin
		if (cpu.intD[b] === 1'bx) begin
			$display("FAIL intD contention at t=%0t, step=%0d opcode=$%02h", $time, cpu.decoder.r_step, cpu.decoder.r_opcode);
			errors = errors + 1;
		end
	end
end

// Optional instruction trace
reg trace = 0;
always @(negedge sysClock) begin
	if (trace && !cpu.decoder.r_init && (cpu.decoder.r_step == 0))
		$display("  fetch $%04h: $%02h  A=%02h B=%02h C=%02h SP=%04h S%0dZ%0dC%0d",
			PC, mem[PC], A, B, C, SP, fS, fZ, fC);
end

// ---------------------------------------------------------------------------
// Mini assembler
// ---------------------------------------------------------------------------

reg [15:0] pc;

task e1(input [7:0] op);
	begin
		mem[pc] = op;
		pc = pc + 16'd1;
	end
endtask

task e2(input [7:0] op, input [7:0] n);
	begin
		mem[pc] = op;
		mem[pc + 16'd1] = n;
		pc = pc + 16'd2;
	end
endtask

task e3(input [7:0] op, input [15:0] nn);
	begin
		mem[pc] = op;
		mem[pc + 16'd1] = nn[7:0];
		mem[pc + 16'd2] = nn[15:8];
		pc = pc + 16'd3;
	end
endtask

task word(input [15:0] addr, input [15:0] value);
	begin
		mem[addr] = value[7:0];
		mem[addr + 16'd1] = value[15:8];
	end
endtask

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

task check8(input [8*28-1:0] name, input [7:0] actual, input [7:0] expected);
	begin
		checks = checks + 1;
		if (actual !== expected) begin
			$display("FAIL %0s: got $%02h, expected $%02h", name, actual, expected);
			errors = errors + 1;
		end
	end
endtask

task check16(input [8*28-1:0] name, input [15:0] actual, input [15:0] expected);
	begin
		checks = checks + 1;
		if (actual !== expected) begin
			$display("FAIL %0s: got $%04h, expected $%04h", name, actual, expected);
			errors = errors + 1;
		end
	end
endtask

task check1(input [8*28-1:0] name, input actual, input expected);
	begin
		checks = checks + 1;
		if (actual !== expected) begin
			$display("FAIL %0s: got %b, expected %b", name, actual, expected);
			errors = errors + 1;
		end
	end
endtask

task flags(input [8*20-1:0] name, input s, input z, input c);
	begin
		check1({name, " S"}, fS, s);
		check1({name, " Z"}, fZ, z);
		check1({name, " C"}, fC, c);
	end
endtask

// Run until the core is about to fetch the opcode at addr
task run_to(input [15:0] addr);
	integer n;
	begin
		n = 0;
		@(negedge sysClock);
		while (!((cpu.decoder.r_step == 0) && !cpu.decoder.r_init && (PC == addr)) && (n < 4000)) begin
			@(negedge sysClock);
			n = n + 1;
		end
		if (n >= 4000) begin
			$display("FAIL timeout waiting for PC=$%04h (PC=$%04h)", addr, PC);
			errors = errors + 1;
			$display("%0d of %0d checks FAILED", errors, checks);
			$finish;
		end
	end
endtask

task section(input [8*40-1:0] name);
	$display("--- %0s", name);
endtask

// ---------------------------------------------------------------------------
// Program marks (addresses to stop at)
// ---------------------------------------------------------------------------

reg [15:0] m_lds, m_lbcs, m_ldsi;
reg [15:0] m_ld1, m_ld2, m_st, m_cp1, m_cp2, m_cp3, m_cp4, m_stk;
reg [15:0] m_exd, m_exe, m_inc16, m_inc16z, m_dec16, m_dd, m_incbc, m_decbc, m_incbc0;
reg [15:0] m_add1, m_add2, m_adc, m_addnn, m_addbc, m_addz, m_bcd1, m_bcd2, m_cld;
reg [15:0] m_sub1, m_sub2, m_sbc, m_suba, m_sbca, m_bcds1, m_bcds2;
reg [15:0] m_inca, m_decb, m_incdec, m_neg, m_neg0, m_incm;
reg [15:0] m_lsr, m_ror, m_asl, m_rol, m_shreg, m_lsrnn, m_rolbc;
reg [15:0] m_or, m_and, m_xor, m_nor, m_nnd, m_xnr, m_xora, m_andz, m_inv, m_logm;
reg [15:0] m_php, m_plp;
reg [15:0] m_jmpr, m_jmprb, m_jmp, m_jmpi, m_jz, m_js, m_jc;
reg [15:0] m_jsr, m_jsrr, m_jsri, m_jsrz, m_jsnc, m_jsrn;
reg [15:0] m_brk, m_hlt, m_hlt_done, m_sei, m_masked, m_nmi0, m_nmi1, m_nops, m_rst;
reg [15:0] j_addr;

// ---------------------------------------------------------------------------
// Test
// ---------------------------------------------------------------------------

initial begin
	if ($test$plusargs("trace")) trace = 1;
	for (i = 0; i < 65536; i = i + 1) mem[i] = 8'h00;

	// Vectors
	word(16'hFFFA, 16'h0700);	// IRQ / BRK
	word(16'hFFFC, 16'h0780);	// NMI
	word(16'hFFFE, 16'h0200);	// RESET

	// IRQ/BRK handler: mark $3F00, clobber A/B/C/flags, return
	pc = 16'h0700;
	e2(8'h14, 8'h99); e3(8'h1D, 16'h3F00); e2(8'h24, 8'h98); e2(8'h34, 8'h97); e1(8'hFB); e1(8'hF3);

	// NMI handler: mark $3F01, return
	pc = 16'h0780;
	e2(8'h14, 8'h66); e3(8'h1D, 16'h3F01); e1(8'hF3);

	// Subroutine: A = $5A
	pc = 16'h0600;
	e2(8'h14, 8'h5A); e1(8'hF2);

	// RST target and RESET-pin target: set a register and spin
	pc = 16'h0F00;
	e2(8'h14, 8'hAB); e2(8'h44, 8'hFE);
	pc = 16'h0F10;
	e2(8'h34, 8'hCD); e2(8'h44, 8'hFE);

	// Data
	word(16'h1234, 16'h0500);	// for LDS (BC)
	mem[16'h3000] = 8'h05;
	mem[16'h3001] = 8'h02;
	mem[16'h3002] = 8'h80;

	pc = 16'h0200;

	// --- Stack pointer loads
	e3(8'hF7, 16'h0400);                                   m_lds = pc;   // LDS $0400
	e2(8'h24, 8'h12); e2(8'h34, 8'h34); e1(8'hF8);         // LDB #$12, LDC #$34, LDS BC
	e1(8'h20); e1(8'h30); e1(8'hFA);                       m_lbcs = pc;  // LDBZ, LDCZ, LBCS
	e1(8'hF9);                                             m_ldsi = pc;  // LDS (BC) -> $0500

	// --- Loads, stores, compares, push/pull
	e2(8'h14, 8'h42); e2(8'h24, 8'h30); e2(8'h34, 8'h02);  // LDA #$42, LDB #$30, LDC #$02
	e1(8'h16);                                             m_ld1 = pc;   // LDA (BC) -> $80
	e3(8'h25, 16'h3000); e1(8'h31);                        m_ld2 = pc;   // LDB $3000 -> 5, LDC A
	e3(8'h1D, 16'h3010); e2(8'h24, 8'h30); e2(8'h34, 8'h11);
	e1(8'h2E);                                             m_st = pc;    // STA $3010, STB (BC) at $3011
	e2(8'h14, 8'h42); e2(8'h24, 8'h42); e1(8'h1A);         m_cp1 = pc;   // CPA B (equal)
	e2(8'h34, 8'h10); e2(8'h3C, 8'h50);                    m_cp2 = pc;   // CPC #$50 (less)
	e2(8'h1C, 8'h10);                                      m_cp3 = pc;   // CPA #$10 (greater)
	e1(8'h18);                                             m_cp4 = pc;   // CPAZ
	e2(8'h14, 8'h5A); e1(8'h1F); e1(8'h10); e1(8'h17);     // PHA, LDAZ, PLA
	e2(8'h24, 8'h77); e1(8'h2F); e1(8'h37);                m_stk = pc;   // PHB, PLC

	// --- Exchange and 16-bit increment/decrement
	e2(8'h24, 8'hAB); e2(8'h34, 8'hCD); e1(8'h40);         m_exd = pc;   // EXD
	e2(8'h24, 8'h55); e2(8'h34, 8'h66); e1(8'h48);         m_exe = pc;   // EXE (EE was 0)
	e1(8'h60); e1(8'h78);                                  m_inc16 = pc; // INC DD, DEC EE
	e2(8'h24, 8'hFF); e2(8'h34, 8'hFF); e1(8'h40); e1(8'h60); m_inc16z = pc; // EXD, INC DD -> 0
	e1(8'h68); e1(8'h70);                                  m_dec16 = pc; // DEC DD, INC EE
	e2(8'h24, 8'h30); e2(8'h34, 8'h20); e1(8'h40);         // DD = $3020
	e2(8'h14, 8'h77); e1(8'h58); e1(8'h10); e1(8'h50);     m_dd = pc;    // STA (DD), LDAZ, LDA (DD)
	e1(8'h20); e2(8'h34, 8'hFF); e1(8'hFD);                m_incbc = pc; // INC BC $00FF
	e1(8'h20); e1(8'h30); e1(8'hFE);                       m_decbc = pc; // DEC BC $0000
	e1(8'hFD);                                             m_incbc0 = pc;// INC BC $FFFF

	// --- Addition
	e2(8'h14, 8'h10); e2(8'h84, 8'h20);                    m_add1 = pc;  // ADD #$20
	e2(8'h24, 8'hF0); e1(8'h82);                           m_add2 = pc;  // ADD B (carry)
	e2(8'h8C, 8'h01);                                      m_adc = pc;   // ADC #1
	e3(8'h85, 16'h3000);                                   m_addnn = pc; // ADD $3000
	e2(8'h24, 8'h30); e1(8'h30); e1(8'h86);                m_addbc = pc; // ADD (BC)
	e1(8'h80);                                             m_addz = pc;  // ADDZ
	e1(8'hD7); e2(8'h14, 8'h45); e2(8'h84, 8'h38);         m_bcd1 = pc;  // SED, BCD 45+38
	e2(8'h84, 8'h20);                                      m_bcd2 = pc;  // BCD 83+20
	e1(8'hDF);                                             m_cld = pc;   // CLD

	// --- Subtraction (carry = borrow)
	e2(8'h14, 8'h50); e2(8'h94, 8'h20);                    m_sub1 = pc;  // SUB #$20
	e2(8'h94, 8'h40);                                      m_sub2 = pc;  // SUB #$40 (borrow)
	e2(8'h9C, 8'h01);                                      m_sbc = pc;   // SBC #1 (with borrow)
	e1(8'h91);                                             m_suba = pc;  // SUB A
	e1(8'hFC); e1(8'h99);                                  m_sbca = pc;  // SEC, SBC A
	e1(8'hD7); e2(8'h14, 8'h42); e2(8'h94, 8'h15);         m_bcds1 = pc; // SED, BCD 42-15
	e2(8'h94, 8'h30); e1(8'hDF);                           m_bcds2 = pc; // BCD 27-30, CLD

	// --- 8-bit increment/decrement, NEG, INC (BC)
	e2(8'h14, 8'hFF); e1(8'h87);                           m_inca = pc;  // INC A
	e1(8'h20); e1(8'hA7);                                  m_decb = pc;  // LDBZ, DEC B
	e1(8'h8F); e2(8'h34, 8'h10); e1(8'h97); e1(8'hAF); e1(8'h9F); m_incdec = pc; // INC B, INC C, DEC C, DEC A
	e2(8'h14, 8'h01); e1(8'hB7);                           m_neg = pc;   // NEG
	e1(8'h10); e1(8'hB7);                                  m_neg0 = pc;  // NEG 0
	e2(8'h24, 8'h30); e1(8'h30); e1(8'hBF);                m_incm = pc;  // INC (BC) at $3000

	// --- Shifts and rotates
	e1(8'hFB); e2(8'h14, 8'h81); e1(8'hA1);                m_lsr = pc;   // CLC, LSR A
	e1(8'hA9);                                             m_ror = pc;   // ROR A
	e1(8'hB1);                                             m_asl = pc;   // ASL A
	e1(8'hB9);                                             m_rol = pc;   // ROL A
	e2(8'h24, 8'h03); e1(8'hA2); e2(8'h34, 8'hC0); e1(8'hB3); m_shreg = pc; // LSR B, ASL C
	e3(8'hA5, 16'h3001);                                   m_lsrnn = pc; // LSR $3001
	e2(8'h24, 8'h30); e2(8'h34, 8'h01); e1(8'hFC); e1(8'hBE); m_rolbc = pc; // SEC, ROL (BC)

	// --- Logic
	e2(8'h14, 8'hF0); e2(8'hC4, 8'h0F);                    m_or = pc;    // ORA #$0F
	e2(8'hD4, 8'h3C);                                      m_and = pc;   // AND #$3C
	e2(8'hE4, 8'hFF);                                      m_xor = pc;   // XOR #$FF
	e2(8'hCC, 8'h00);                                      m_nor = pc;   // NOR #0
	e2(8'h24, 8'h0F); e1(8'hDA);                           m_nnd = pc;   // NND B
	e2(8'h34, 8'hF3); e1(8'hEB);                           m_xnr = pc;   // XNR C
	e1(8'hE1);                                             m_xora = pc;  // XOR A
	e1(8'hC8); e1(8'hD0);                                  m_andz = pc;  // NORZ, ANDZ
	e2(8'h24, 8'h0F); e1(8'hC7); e1(8'h30); e1(8'hCF);     m_inv = pc;   // INV B, LDCZ, INV C
	e3(8'hC5, 16'h3000); e2(8'h24, 8'h30); e2(8'h34, 8'h01); e1(8'hD6); m_logm = pc; // ORA $3000, AND (BC)

	// --- Flags and P on the stack
	e1(8'hFC); e1(8'hD7); e1(8'hF0); e1(8'hE7);            // SEC, SED, SEI, PHP
	e1(8'hFB); e1(8'hDF); e1(8'hF1);                       m_php = pc;   // CLC, CLD, CLI
	e1(8'hEF);                                             m_plp = pc;   // PLP
	e1(8'hFB); e1(8'hDF);                                  // CLC, CLD (I stays disabled)

	// --- Jumps
	// Poison = INC EE ($70), placed where a taken jump must skip it: EE must stay 0.
	// A not-taken jump falls into INC DD ($60): DD counts the expected fall-throughs.
	e1(8'h20); e1(8'h30); e1(8'h40);                       // DD = 0
	e1(8'h20); e1(8'h30); e1(8'h48);                       // EE = 0
	e2(8'h44, 8'h01); e1(8'h70);                           m_jmpr = pc;  // JMPR forward
	e2(8'h44, 8'h03); e1(8'h60); e2(8'h44, 8'h02); e2(8'h44, 8'hFB); m_jmprb = pc; // JMPR back (DD=1)
	e3(8'h45, pc + 16'd4); e1(8'h70);                      m_jmp = pc;   // JMP NN
	e2(8'h24, 8'h31); e2(8'h34, 8'h00); word(16'h3100, pc + 16'd2);
	e1(8'h46); e1(8'h70);                                  m_jmpi = pc;  // JMP (BC)
	// Zero: JPNZ taken, JPNZ not taken, JMPZ NN taken, JMPZ NN not taken, JMPZ (BC) taken
	e2(8'h14, 8'h01); e2(8'h54, 8'h01); e1(8'h70);
	e1(8'h10); e2(8'h54, 8'h01); e1(8'h60);                // DD=2
	e1(8'h10); e3(8'h55, pc + 16'd4); e1(8'h70);
	e2(8'h14, 8'h01); e3(8'h55, pc + 16'd4); e1(8'h60);    // DD=3
	e2(8'h24, 8'h31); e2(8'h34, 8'h02); e1(8'h10); word(16'h3102, pc + 16'd2);
	e1(8'h56); e1(8'h70);                                  m_jz = pc;
	// Sign: JMPP taken, JMPN NN taken, JMPN (BC) not taken
	e2(8'h14, 8'h01); e2(8'h64, 8'h01); e1(8'h70);
	e2(8'h14, 8'h80); e3(8'h65, pc + 16'd4); e1(8'h70);
	e2(8'h24, 8'h31); e2(8'h34, 8'h02); e2(8'h14, 8'h01); e1(8'h66); e1(8'h60); m_js = pc; // DD=4
	// Carry: JPNC taken, JMPC NN taken, JMPC (BC) taken, JPNC not taken
	e1(8'hFB); e2(8'h74, 8'h01); e1(8'h70);
	e1(8'hFC); e3(8'h75, pc + 16'd4); e1(8'h70);
	e2(8'h24, 8'h31); e2(8'h34, 8'h04); word(16'h3104, pc + 16'd2);
	e1(8'h76); e1(8'h70);
	e1(8'hFC); e2(8'h74, 8'h01); e1(8'h60);                m_jc = pc;    // DD=5

	// --- Subroutines
	e1(8'h10); e3(8'h4D, 16'h0600);                        m_jsr = pc;   // JSR $0600
	e2(8'h4C, 8'h02); e2(8'h44, 8'h03); e2(8'h34, 8'h5B); e1(8'hF2); m_jsrr = pc; // JSRR inline
	e2(8'h24, 8'h31); e2(8'h34, 8'h06); word(16'h3106, 16'h0600);
	e1(8'h10); e1(8'h4E);                                  m_jsri = pc;  // JSR (BC)
	e2(8'h14, 8'h01); e3(8'h5D, 16'h0600);                 m_jsrz = pc;  // JSRZ NN not taken
	e1(8'hFB); e2(8'h7C, 8'h02); e2(8'h44, 8'h03); e2(8'h34, 8'h5C); e1(8'hF2); m_jsnc = pc; // JSNC taken
	e2(8'h24, 8'h31); e2(8'h34, 8'h06); e2(8'h14, 8'h80); e1(8'h6E); m_jsrn = pc; // JSRN (BC) taken

	// --- BRK / RTI
	e2(8'h14, 8'h01); e2(8'h24, 8'h02); e2(8'h34, 8'h03); e1(8'hFC); e1(8'hF1); // SEC, CLI
	e1(8'hF5);                                             m_brk = pc;   // BRK

	// --- HLT woken by IRQ, masked IRQ, NMI
	m_hlt = pc; e1(8'hF4);                                 m_hlt_done = pc;
	e1(8'h00);
	e1(8'hF0);                                             m_sei = pc;   // SEI
	e1(8'h00); e1(8'h00); e1(8'h00); e1(8'h00);            m_masked = pc;
	e1(8'h00);                                             m_nmi0 = pc;
	e1(8'h00); e1(8'h00); e1(8'h00); e1(8'h00);            m_nmi1 = pc;

	// --- Undocumented NOPs
	e2(8'h14, 8'h3C); e2(8'h24, 8'h3D);
	e1(8'h41); e2(8'hA4, 8'hEE); e1(8'hFF); e1(8'hA8); e3(8'h0D, 16'hEEEE); e2(8'h0C, 8'hEE); m_nops = pc;

	// --- RST
	e1(8'hF6);                                             m_rst = pc;

	// =======================================================================

	section("stack pointer loads");
	run_to(m_lds);   check16("LDS NN SP", SP, 16'h0400);
	run_to(m_lbcs);  check16("LDS BC SP", SP, 16'h1234); check16("LBCS BC", BC, 16'h1234);
	run_to(m_ldsi);  check16("LDS (BC) SP", SP, 16'h0500);

	section("loads, stores, compares, push/pull");
	run_to(m_ld1);   check8("LDA (BC)", A, 8'h80); flags("LDA (BC)", 1, 0, 0);
	run_to(m_ld2);   check8("LDB NN", B, 8'h05); check8("LDC A", C, 8'h80);
	run_to(m_st);    check8("STA NN", mem[16'h3010], 8'h80); check8("STB (BC)", mem[16'h3011], 8'h30);
	run_to(m_cp1);   flags("CPA B equal", 0, 1, 1);
	run_to(m_cp2);   flags("CPC #N less", 1, 0, 0);
	run_to(m_cp3);   flags("CPA #N greater", 0, 0, 1);
	run_to(m_cp4);   flags("CPAZ", 0, 0, 1); check8("CPAZ A unchanged", A, 8'h42);
	run_to(m_stk);   check8("PLA", A, 8'h5A); check8("PLC", C, 8'h77); check16("push/pull SP", SP, 16'h0500);

	section("exchange, 16-bit inc/dec, DD indirect");
	run_to(m_exd);   check16("EXD DD", DD, 16'hABCD); check16("EXD BC", BC, 16'hFFFF); check1("EXD Z", fZ, 0);
	run_to(m_exe);   check16("EXE EE", EE, 16'h5566); check16("EXE BC", BC, 16'h0000); check1("EXE Z", fZ, 1);
	run_to(m_inc16); check16("INC DD", DD, 16'hABCE); check16("DEC EE", EE, 16'h5565); check1("DEC EE Z", fZ, 0);
	run_to(m_inc16z);check16("INC DD wrap", DD, 16'h0000); check1("INC DD Z", fZ, 1); check16("EXD BC", BC, 16'hABCE);
	run_to(m_dec16); check16("DEC DD wrap", DD, 16'hFFFF); check16("INC EE", EE, 16'h5566); check1("INC EE Z", fZ, 0);
	run_to(m_dd);    check8("STA (DD)", mem[16'h3020], 8'h77); check8("LDA (DD)", A, 8'h77);
	run_to(m_incbc); check16("INC BC", BC, 16'h0100); check1("INC BC Z", fZ, 0);
	run_to(m_decbc); check16("DEC BC", BC, 16'hFFFF); check1("DEC BC Z", fZ, 0);
	run_to(m_incbc0);check16("INC BC wrap", BC, 16'h0000); check1("INC BC Z", fZ, 1);

	section("addition");
	run_to(m_add1);  check8("ADD #N", A, 8'h30); flags("ADD #N", 0, 0, 0);
	run_to(m_add2);  check8("ADD B", A, 8'h20); flags("ADD B", 0, 0, 1);
	run_to(m_adc);   check8("ADC #N", A, 8'h22); flags("ADC #N", 0, 0, 0);
	run_to(m_addnn); check8("ADD NN", A, 8'h27);
	run_to(m_addbc); check8("ADD (BC)", A, 8'h2C);
	run_to(m_addz);  check8("ADDZ", A, 8'h2C); flags("ADDZ", 0, 0, 0);
	run_to(m_bcd1);  check8("BCD 45+38", A, 8'h83); flags("BCD 45+38", 1, 0, 0);
	run_to(m_bcd2);  check8("BCD 83+20", A, 8'h03); flags("BCD 83+20", 0, 0, 1);
	run_to(m_cld);   check1("CLD", fD, 0);

	section("subtraction");
	run_to(m_sub1);  check8("SUB #N", A, 8'h30); flags("SUB #N", 0, 0, 0);
	run_to(m_sub2);  check8("SUB borrow", A, 8'hF0); flags("SUB borrow", 1, 0, 1);
	run_to(m_sbc);   check8("SBC #N", A, 8'hEE); flags("SBC #N", 1, 0, 0);
	run_to(m_suba);  check8("SUB A", A, 8'h00); flags("SUB A", 0, 1, 0);
	run_to(m_sbca);  check8("SBC A", A, 8'hFF); flags("SBC A", 1, 0, 1);
	run_to(m_bcds1); check8("BCD 42-15", A, 8'h27); flags("BCD 42-15", 0, 0, 0);
	run_to(m_bcds2); check8("BCD 27-30", A, 8'h97); check1("BCD 27-30 C", fC, 1);

	section("increment, decrement, negate");
	run_to(m_inca);  check8("INC A", A, 8'h00); flags("INC A", 0, 1, 1);
	run_to(m_decb);  check8("DEC B", B, 8'hFF); flags("DEC B", 1, 0, 1);
	run_to(m_incdec);check8("INC B", B, 8'h00); check8("INC/DEC C", C, 8'h10); check8("DEC A", A, 8'hFF);
	run_to(m_neg);   check8("NEG", A, 8'hFF); flags("NEG", 1, 0, 1);
	run_to(m_neg0);  check8("NEG 0", A, 8'h00); flags("NEG 0", 0, 1, 0);
	run_to(m_incm);  check8("INC (BC)", mem[16'h3000], 8'h06); flags("INC (BC)", 0, 0, 0);

	section("shifts and rotates");
	run_to(m_lsr);   check8("LSR A", A, 8'h40); flags("LSR A", 0, 0, 1);
	run_to(m_ror);   check8("ROR A", A, 8'hA0); flags("ROR A", 1, 0, 0);
	run_to(m_asl);   check8("ASL A", A, 8'h40); flags("ASL A", 0, 0, 1);
	run_to(m_rol);   check8("ROL A", A, 8'h81); flags("ROL A", 1, 0, 0);
	run_to(m_shreg); check8("LSR B", B, 8'h01); check8("ASL C", C, 8'h80); check1("ASL C carry", fC, 1);
	run_to(m_lsrnn); check8("LSR NN", mem[16'h3001], 8'h01); check1("LSR NN C", fC, 0);
	run_to(m_rolbc); check8("ROL (BC)", mem[16'h3001], 8'h03); check1("ROL (BC) C", fC, 0);

	section("logic");
	run_to(m_or);    check8("ORA #N", A, 8'hFF); check1("ORA S", fS, 1);
	run_to(m_and);   check8("AND #N", A, 8'h3C);
	run_to(m_xor);   check8("XOR #N", A, 8'hC3);
	run_to(m_nor);   check8("NOR #N", A, 8'h3C);
	run_to(m_nnd);   check8("NND B", A, 8'hF3);
	run_to(m_xnr);   check8("XNR C", A, 8'hFF);
	run_to(m_xora);  check8("XOR A", A, 8'h00); check1("XOR A Z", fZ, 1);
	run_to(m_andz);  check8("ANDZ", A, 8'h00); check1("ANDZ Z", fZ, 1);
	run_to(m_inv);   check8("INV B", B, 8'hF0); check8("INV C", C, 8'hFF); check1("INV C S", fS, 1);
	run_to(m_logm);  check8("ORA NN / AND (BC)", A, 8'h02);

	section("flags and PHP/PLP");
	run_to(m_php);   check8("PHP C,I,D bits", mem[16'h04FF] & 8'h38, 8'h38); check16("PHP SP", SP, 16'h04FF);
	                 check1("CLC", fC, 0); check1("CLD", fD, 0); check1("CLI", fIEn, 1);
	run_to(m_plp);   check1("PLP C", fC, 1); check1("PLP D", fD, 1); check1("PLP I", fIEn, 0); check16("PLP SP", SP, 16'h0500);

	section("jumps");
	run_to(m_jmpr);  check16("JMPR skipped poison", EE, 16'h0000);
	run_to(m_jmprb); check16("JMPR backward", DD, 16'h0001);
	run_to(m_jmp);   check16("JMP NN skipped poison", EE, 16'h0000);
	run_to(m_jmpi);  check16("JMP (BC) skipped poison", EE, 16'h0000);
	run_to(m_jz);    check16("Z jumps poison", EE, 16'h0000); check16("Z jumps fall-through", DD, 16'h0003);
	run_to(m_js);    check16("S jumps poison", EE, 16'h0000); check16("S jumps fall-through", DD, 16'h0004);
	run_to(m_jc);    check16("C jumps poison", EE, 16'h0000); check16("C jumps fall-through", DD, 16'h0005);

	section("subroutines");
	run_to(m_jsr);   check8("JSR NN", A, 8'h5A); check16("JSR SP", SP, 16'h0500);
	                 check16("JSR return addr", {mem[16'h04FF], mem[16'h04FE]}, m_jsr);
	run_to(m_jsrr);  check8("JSRR", C, 8'h5B); check16("JSRR SP", SP, 16'h0500);
	                 check16("JSRR return addr", {mem[16'h04FF], mem[16'h04FE]}, m_jsr + 16'd2);
	run_to(m_jsri);  check8("JSR (BC)", A, 8'h5A); check16("JSR (BC) SP", SP, 16'h0500);
	run_to(m_jsrz);  check8("JSRZ not taken", A, 8'h01); check16("JSRZ SP", SP, 16'h0500);
	run_to(m_jsnc);  check8("JSNC taken", C, 8'h5C);
	run_to(m_jsrn);  check8("JSRN (BC) taken", A, 8'h5A);

	section("BRK / RTI");
	mem[16'h3F00] = 8'h00;
	run_to(m_brk);   check8("BRK handler ran", mem[16'h3F00], 8'h99);
	                 check8("RTI A", A, 8'h01); check8("RTI B", B, 8'h02); check8("RTI C", C, 8'h03);
	                 check1("RTI carry", fC, 1); check1("RTI I", fIEn, 1); check16("RTI SP", SP, 16'h0500);
	                 check16("BRK return addr", {mem[16'h04FF], mem[16'h04FE]}, m_brk);
	                 check8("BRK pushed K", mem[16'h04FD] & 8'h04, 8'h04);
	                 check8("BRK pushed A", mem[16'h04FC], 8'h01);
	                 check8("BRK pushed C", mem[16'h04FA], 8'h03);

	section("HLT, IRQ, NMI");
	mem[16'h3F00] = 8'h00;
	// already stopped at the HLT fetch (it directly follows BRK)
	check16("at HLT", PC, m_hlt);
	repeat (20) @(negedge sysClock);
	check16("HLT holds", PC, m_hlt_done);
	// Hold IRQ low until the handler is running, as a device does until
	// it's serviced: the handler must be entered only once
	irq_entries = 0;
	irq = 1'b0;
	while (mem[16'h3F00] != 8'h99) @(negedge sysClock);
	irq = 1'b1;
	run_to(m_hlt_done);  check8("IRQ handler ran", mem[16'h3F00], 8'h99); check8("IRQ RTI A", A, 8'h01);
	                     check8("IRQ handler entered once", irq_entries, 8'd1);
	                     check8("IRQ pushed K clear", mem[16'h04FD] & 8'h04, 8'h00);
	run_to(m_sei);
	mem[16'h3F00] = 8'h00;
	irq = 1'b0;
	run_to(m_masked);    check8("masked IRQ ignored", mem[16'h3F00], 8'h00);
	irq = 1'b1;
	run_to(m_nmi0);
	nmiReq = 1'b0;
	repeat (2) @(negedge sysClock);
	nmiReq = 1'b1;
	run_to(m_nmi1);      check8("NMI handler ran", mem[16'h3F01], 8'h66); check8("NMI RTI A", A, 8'h01);
	                     check16("NMI SP", SP, 16'h0500);

	section("undocumented NOPs");
	run_to(m_nops);  check8("NOPs A", A, 8'h3C); check8("NOPs B", B, 8'h3D);

	section("RST and RESET pin");
	word(16'hFFFE, 16'h0F00);
	run_to(16'h0F02); check8("RST", A, 8'hAB);
	word(16'hFFFE, 16'h0F10);
	resetReq = 1'b0;
	repeat (3) @(negedge sysClock);
	resetReq = 1'b1;
	run_to(16'h0F12); check8("RESET pin", C, 8'hCD);

	if (errors == 0) $display("PASS: all %0d checks passed", checks);
	else $display("%0d of %0d checks FAILED", errors, checks);
	$finish;
end

endmodule
