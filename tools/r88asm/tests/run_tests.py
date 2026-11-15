"""Tests for r88asm. Run from tools/r88asm with `make test` (or python3 tests/run_tests.py).

1. Every code example in doc/*.md is assembled by r88asm and by the Python
   assembler in tools/check_doc_examples.py (whose output is run on the
   Verilog core by that tool); the bytes must match exactly.
2. The example ROM and RAM programs from the main README are assembled
   together and run on the Verilog core (Icarus Verilog), checking the RAM
   vectors they set up.
3. Feature tests: expressions, directives, zero-mode selection, output formats.
4. Error tests: each bad input must fail with the expected message and line.
5. examples/showcase.asm is assembled and run on the Verilog core, and every
   result it stores is checked against values computed here.
"""

import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ASM_DIR = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(ASM_DIR))
VERILOG = os.path.join(ROOT, "verilog")
R88ASM = os.path.join(ASM_DIR, "r88asm.exe" if os.name == "nt" else "r88asm")

sys.path.insert(0, os.path.join(ROOT, "tools"))
import check_doc_examples as ref  # noqa: E402

failures = []
passed = 0
work = tempfile.mkdtemp(prefix="r88asm_test")


def check(cond, what):
    global passed
    if cond:
        passed += 1
    else:
        failures.append(what)


def write(name, text):
    path = os.path.join(work, name)
    with open(path, "w") as f:
        f.write(text)
    return path


def r88asm(*args):
    return subprocess.run([R88ASM] + list(args), capture_output=True, text=True)


def read_mem(path):
    """Parse a $readmemh image into {address: byte}."""
    mem, addr = {}, 0
    with open(path) as f:
        for tok in f.read().split():
            if tok.startswith("@"):
                addr = int(tok[1:], 16)
            else:
                mem[addr] = int(tok, 16)
                addr += 1
    return mem


def assemble(text, *extra):
    src = write("t.asm", text)
    out = os.path.join(work, "t.mem")
    res = r88asm("-f", "mem", "-o", out, *extra, src)
    return res, (read_mem(out) if res.returncode == 0 else None)


# ---------------------------------------------------------------------------
# 1. Doc examples match the Python reference assembler byte for byte
# ---------------------------------------------------------------------------

def test_doc_examples():
    import glob
    count = 0
    for path in sorted(glob.glob(os.path.join(ROOT, "doc", "*.md"))):
        for start, lines in ref.code_blocks(path):
            name = "%s:%d" % (os.path.relpath(path, ROOT), start)
            expected, _, _ = ref.assemble(lines)
            res, got = assemble(".org $0200\n" + "\n".join(lines) + "\n")
            if res.returncode != 0:
                check(False, "%s: r88asm failed: %s" % (name, res.stderr.strip()))
                continue
            # the reference adds a RESET vector unless the example sets one
            for a in (0xFFFE, 0xFFFF):
                if a not in got:
                    expected.pop(a, None)
            check(got == expected, "%s: r88asm output differs from the reference assembler" % name)
            count += 1
    print("  %d doc examples compared" % count)


# ---------------------------------------------------------------------------
# 2. README example system, run on the Verilog core
# ---------------------------------------------------------------------------

def run_sim(mem_path, max_clocks):
    vvp = os.path.join(work, "tb.vvp")
    if not os.path.exists(vvp):
        sources = ["sim/tb_program.v"] + sorted(
            f for f in os.listdir(VERILOG) if f.endswith(".v"))
        subprocess.run(["iverilog", "-g2005", "-o", vvp] + sources, cwd=VERILOG, check=True)
    out = subprocess.run(["vvp", "-n", vvp, "+hex=" + mem_path, "+stop=ffff", "+max=%d" % max_clocks],
                         capture_output=True, text=True, check=True).stdout
    return out.splitlines()


def test_readme_system():
    with open(os.path.join(ROOT, "README.md")) as f:
        blocks = re.findall(r"```\n(.*?)```", f.read(), re.S)
    rom = [b for b in blocks if ".org $F000" in b][0]
    ram = [b for b in blocks if ".org $1000" in b][0]
    rom_path, ram_path = write("rom.asm", rom), write("ram.asm", ram)
    mem_path = os.path.join(work, "system.mem")
    lst_path = os.path.join(work, "system.lst")
    res = r88asm("-f", "mem", "-o", mem_path, "-l", lst_path, rom_path, ram_path)
    check(res.returncode == 0, "README system: r88asm failed: " + res.stderr.strip())
    if res.returncode != 0:
        return
    symbols = {}
    with open(lst_path) as f:
        for line in f:
            m = re.match(r"\s+(\w+)\s+\$([0-9A-F]{4})", line)
            if m:
                symbols[m.group(1)] = int(m.group(2), 16)
    log = run_sim(mem_path, 3000)
    memory, fetches = {}, []
    for entry in log:
        parts = entry.split()
        if parts[0] == "W":
            memory[int(parts[1], 16)] = int(parts[2], 16)
        elif parts[0] == "F":
            fetches.append(parts)
    word = lambda a: memory.get(a, 0) | (memory.get(a + 1, 0) << 8)
    check(word(0x0100) == symbols["custom_irq_handler"],
          "README system: IRQ_RAM_VECTOR should point at custom_irq_handler")
    check(word(0x0102) == symbols["default_nmi_handler"],
          "README system: NMI_RAM_VECTOR should point at default_nmi_handler")
    last = fetches[-1]
    check(int(last[1], 16) == symbols["loop"],
          "README system: should be halted in the RAM program's loop")
    check(int(last[7], 16) == 0x1000, "README system: SP should be PROGRAM_START")


# ---------------------------------------------------------------------------
# 3. Features
# ---------------------------------------------------------------------------

def expect_bytes(text, addr, expected, what):
    res, mem = assemble(text)
    if res.returncode != 0:
        check(False, "%s: failed: %s" % (what, res.stderr.strip()))
        return
    got = [mem.get(addr + i) for i in range(len(expected))]
    check(got == expected, "%s: expected %s, got %s" % (
        what, " ".join("%02X" % b for b in expected),
        " ".join("--" if b is None else "%02X" % b for b in got)))


def test_features():
    expect_bytes("lda #2+3*4\nlda #(2+3)*4\nlda #%1010 | $05\nlda #'A'\nlda #-1\n"
                 "lda #$1234.high\nlda #~0 & $FF\nlda #1 << 4\nlda #$80 >> 3\n", 0,
                 [0x14, 14, 0x14, 20, 0x14, 0x0F, 0x14, 0x41, 0x14, 0xFF,
                  0x14, 0x12, 0x14, 0xFF, 0x14, 0x10, 0x14, 0x10], "expressions")
    expect_bytes(".org $10\nhere: .word *, here+2\n", 0x10, [0x10, 0, 0x12, 0], "* and labels")
    expect_bytes(".byte 1, \"Hi\", 'x', $FF\n.fill 3, $AA\n.addr $BEEF\n.db 2\n.dw 3\n", 0,
                 [1, ord("H"), ord("i"), ord("x"), 0xFF, 0xAA, 0xAA, 0xAA, 0xEF, 0xBE, 2, 3, 0],
                 "data directives")
    expect_bytes("LDA #ZERO\nadd #0\ncpa #0\nnor #0\nZERO = 0\n", 0, [0x10, 0x80, 0x18, 0xC8],
                 "#0 uses the Zero mode opcode, even for a forward constant")
    expect_bytes("x: jmpr x\njpnz y\nnop\ny: jsr y\njmp (bc)\nlds (bc)\nlds bc\ninc bc\ninc (bc)\n"
                 "lda (dd)\nsta (dd)\nexd\nrst\n", 0,
                 [0x44, 0xFE, 0x54, 0x01, 0x00, 0x4D, 0x05, 0x00, 0x46, 0xF9, 0xF8, 0xFD, 0xBF,
                  0x50, 0x58, 0x40, 0xF6], "operand forms")
    expect_bytes("  LdA  B ; mixed case\nLABEL:LDB #1\n", 0, [0x12, 0x24, 1], "case and spacing")
    expect_bytes("jmpr fwd\n.fill 125\nfwd: nop\n", 0, [0x44, 125], "longest forward branch")
    expect_bytes("back: .fill 126\njmpr back\n", 126, [0x44, 0x80], "longest backward branch")
    expect_bytes("A1 = 5\nA1 = 5\nlda #A1\n", 0, [0x14, 5], "constant redefined to the same value")

    # Output formats
    src = write("fmt.asm", ".org $10\n.byte 1, 2\n.org $14\n.byte 3\n")
    out = os.path.join(work, "fmt.bin")
    check(r88asm("-o", out, "-p", "0xEE", src).returncode == 0, "bin output")
    with open(out, "rb") as f:
        check(f.read() == bytes([1, 2, 0xEE, 0xEE, 3]), "bin output pads gaps with -p")
    out = os.path.join(work, "fmt.hex")
    check(r88asm("-f", "hex", "-o", out, src).returncode == 0, "hex output")
    with open(out) as f:
        records = f.read().split()
    check(records[-1] == ":00000001FF", "hex output ends with an EOF record")
    for rec in records:
        data = bytes.fromhex(rec[1:])
        check(sum(data) & 0xFF == 0, "hex record %s has a bad checksum" % rec)
    check(records[0].startswith(":020010000102"), "hex output data record")
    res = r88asm(write("default.asm", "nop\n"))
    check(res.returncode == 0 and os.path.exists(os.path.join(work, "default.bin")),
          "default output name")


# ---------------------------------------------------------------------------
# 4. Errors
# ---------------------------------------------------------------------------

ERRORS = [
    ("nop\nlda missing\n", 2, "undefined symbol 'missing'"),
    ("nop\nfoo a\n", 2, "unknown instruction 'foo'"),
    ("ldb (dd)\n", 1, "'ldb' does not support the operand '(dd)'"),
    ("sta #1\n", 1, "does not support the operand"),
    ("x:\nx:\n", 2, "'x' is already defined"),
    ("lda #256\n", 1, "does not fit in a byte"),
    ("jmpr far\n.fill 200\nfar: nop\n", 1, "relative target is out of range"),
    (".org $10\nnop\n.org $10\nnop\n", 4, "written more than once"),
    (".bogus 1\n", 1, "unknown directive .bogus"),
    ("lda #1 +\n", 1, "expected a value"),
    ("lda #(1\n", 1, "missing ')'"),
    ("lda #1 2\n", 1, "unexpected text in expression"),
    ("A1 = 1\nA1 = 2\n", 2, "'A1' is already defined"),
    (".org $FFFF\nnop\nnop\n", 3, "address past $FFFF"),
    ("lda #1/0\n", 1, "division by zero"),
    ("lda #$12G\n", 1, "invalid number"),
]


def test_errors():
    for text, line, message in ERRORS:
        res, _ = assemble(text)
        ok = res.returncode != 0 and ("t.asm:%d: error: " % line) in res.stderr and message in res.stderr
        check(ok, "error test %r: expected line %d '%s', got: %s" % (text, line, message, res.stderr.strip()))


# ---------------------------------------------------------------------------
# 5. examples/showcase.asm, run on the Verilog core
# ---------------------------------------------------------------------------

def bcd(n):
    return int(str(n), 16)


def test_showcase():
    src = os.path.join(ASM_DIR, "examples", "showcase.asm")
    mem_path = os.path.join(work, "showcase.mem")
    lst_path = os.path.join(work, "showcase.lst")
    res = r88asm("-f", "mem", "-o", mem_path, "-l", lst_path, src)
    check(res.returncode == 0, "showcase: r88asm failed: " + res.stderr.strip())
    if res.returncode != 0:
        return
    symbols = {}
    with open(lst_path) as f:
        for line in f:
            m = re.match(r"\s+(\w+)\s+\$([0-9A-F]{4})", line)
            if m:
                symbols[m.group(1)] = int(m.group(2), 16)
    image = read_mem(mem_path)

    vvp = os.path.join(work, "tb.vvp")
    run_sim(mem_path, 1)    # make sure the testbench is built
    log = subprocess.run(["vvp", "-n", vvp, "+hex=" + mem_path, "+stop=%04x" % symbols["done"],
                          "+max=20000"], capture_output=True, text=True, check=True).stdout.splitlines()
    check("END" in log, "showcase: did not reach 'done'")
    memory, executed = {}, set()
    for entry in log:
        parts = entry.split()
        if parts[0] == "W":
            memory[int(parts[1], 16)] = int(parts[2], 16)
        elif parts[0] == "F":
            executed.add(image.get(int(parts[1], 16), 0))

    # Expected results, computed independently of the program
    message = "HELLO, ROCKET88!"
    s, d, p = 0x12F0 + 0x0F25, 0x1234 - 0x0567, 0xB7 * 0x5D
    score = bcd(995 + 27)
    a = 0b11001010 & 0b11110000
    bits = [a, a | 0b101, (a | 0b101) ^ 0xFF]
    bits.append(~(bits[2] & 0x0F) & 0xFF)
    bits.append(~(bits[3] | 0xF0) & 0xFF)
    bits.append(-bits[4] & 0xFF)
    bits.append(~(bits[5] ^ (~0x5A & 0xFF)) & 0xFF)
    table = [23, 200, 7, 99, 150, 64]
    expected = {
        0: len(message),
        1: s & 0xFF, 2: s >> 8,
        3: d & 0xFF, 4: d >> 8,
        5: score & 0xFF, 6: score >> 8,
        7: p & 0xFF, 8: p >> 8,
        9: max(table), 10: min(table),
        18: 2,
        19: 0x11, 20: 0x22, 21: 0x33,
        22: 0xC3, 23: 0xC4, 24: 0x04, 25: 0x00, 26: 0x77,
        27: 0x03, 28: 0x02, 29: 0x01, 30: 0x81,
        31: 4,
        32: 0xAA,
        33: 0xB0,
        34: 0x5A, 35: 0xA5, 36: 0xFF, 37: 0xFE,
        38: 4,
    }
    for i, b in enumerate(bits):
        expected[11 + i] = b
    for offset, value in sorted(expected.items()):
        got = memory.get(0x0300 + offset, 0)
        check(got == value, "showcase: RESULTS+%d should be $%02X, got $%02X" % (offset, value, got))
    copied = bytes(memory.get(0x0340 + i, 0) for i in range(len(message) + 1))
    check(copied == message.encode() + b"\0", "showcase: string copy")
    check(memory.get(0x01FF) == 0xEE, "showcase: push on the second stack")

    documented = {op for op in ref.mnemonics() if not ref.mnemonics()[op].startswith("NOP+")}
    names = ref.mnemonics()
    ran = executed & documented
    mnem = lambda op: names[op].split(" ")[0]
    modes = lambda ops: {names[op].split(" / ")[0].split(" ", 1)[1] if " " in names[op].split(" / ")[0]
                         else "implied" for op in ops}
    print("  showcase executed %d of %d documented opcodes, %d of %d mnemonics, %d of %d operand forms" % (
        len(ran), len(documented), len({mnem(o) for o in ran}), len({mnem(o) for o in documented}),
        len(modes(ran)), len(modes(documented))))


def main():
    if not os.path.exists(R88ASM):
        sys.exit("build r88asm first (make)")
    for name, fn in (("doc examples", test_doc_examples), ("README system", test_readme_system),
                     ("features", test_features), ("errors", test_errors),
                     ("showcase example", test_showcase)):
        print("- " + name)
        fn()
    for f in failures:
        print("FAIL " + f)
    if failures:
        print("%d of %d checks FAILED" % (len(failures), len(failures) + passed))
        sys.exit(1)
    print("PASS: all %d checks passed" % passed)


if __name__ == "__main__":
    main()
