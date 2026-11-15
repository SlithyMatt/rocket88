"""Assemble and run the example code in doc/*.md, checking the comments.

Every ``` code block in the instruction docs is assembled (starting at $0200,
with the RESET vector pointing there) and run on the Verilog core with Icarus
Verilog. Comments of the form `; A = $42, carry = 1, ($3000) = $12` are
checked against the state right after that line's instruction completes
(the first time it runs). Comment terms that aren't `name = number` are just
commentary and are ignored.

Checkable names: A, B, C, BC, DD, EE, SP, S, Z, carry, D, I, and (address).
Numbers: $hex, %binary or decimal.

Assembler syntax: one instruction per line, `label:` on its own line,
`.org address`, `.addr value` (16-bit little-endian), `.byte values`.
Operands: a, b, c, bc, dd, ee, (bc), (dd), #value, value or label;
label.low / label.high take one byte of a label. `lda #0` and similar
assemble to the Zero mode opcode. Execution stops when it reaches the end of
the first section (the code before the first .org), or after a timeout, which
is only an error if a checked comment was never reached.

It also runs every opcode listed in the docs' "| Mode | Opcode | Cycles |"
tables (taken and not taken, for conditional jumps) and checks its measured
cycle count, from its opcode fetch to the next one. HLT is skipped, since it
waits for an interrupt.

From the repository root:  python3 tools/check_doc_examples.py
"""

import glob
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from update_microcode_sheet import mnemonics  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERILOG = os.path.join(ROOT, "verilog")
START = 0x0200


def opcode_table():
    """{(mnemonic, form): opcode} where form is '', A, B, C, BC, DD, EE,
    (BC), (DD), #N, NN or REL."""
    table = {}
    for op, name in mnemonics().items():
        if name.startswith("NOP+"):
            continue
        if name.startswith("RST"):
            name = "RST"
        parts = name.split(" ", 1)
        mnem = parts[0].lower()
        form = parts[1] if len(parts) > 1 else ""
        if form == "label":
            form = "REL"
        table[(mnem, form)] = op
    return table


OPCODES = opcode_table()


class AsmError(Exception):
    pass


def parse_number(text):
    text = text.strip()
    if text.startswith("$"):
        return int(text[1:], 16)
    if text.startswith("%"):
        return int(text[1:], 2)
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    return None


def evaluate(expr, labels, final):
    """Evaluate label/number +/- terms, with optional .low/.high suffix."""
    expr = expr.strip()
    part = None
    m = re.fullmatch(r"(.*)\.(low|high)", expr)
    if m:
        expr, part = m.group(1), m.group(2)
    total = 0
    for sign, term in re.findall(r"([+-]?)\s*([^+-]+)", expr):
        term = term.strip()
        value = parse_number(term)
        if value is None:
            if term not in labels:
                if final:
                    raise AsmError("unknown label %r" % term)
                return None
            value = labels[term]
        total += -value if sign == "-" else value
    if part == "low":
        total &= 0xFF
    elif part == "high":
        total = (total >> 8) & 0xFF
    return total


def classify(mnem, operand, labels, final):
    """Return (opcode, operand bytes) for one instruction."""
    op_text = operand.strip()
    low = op_text.lower()
    if low in ("", "a", "b", "c", "bc", "dd", "ee", "(bc)", "(dd)"):
        form = low.upper()
        if (mnem, form) not in OPCODES:
            raise AsmError("no %s %s" % (mnem, op_text))
        return OPCODES[(mnem, form)], []
    if low.startswith("#"):
        if (mnem, "#N") not in OPCODES:
            raise AsmError("no immediate mode for %s" % mnem)
        op = OPCODES[(mnem, "#N")]
        value = evaluate(op_text[1:], labels, final)
        zero_op = op & 0xF8
        zero_name = mnemonics().get(zero_op, "")
        if value == 0 and " " not in zero_name:
            return zero_op, []
        return op, [0 if value is None else value & 0xFF]
    value = evaluate(op_text, labels, final)
    if (mnem, "REL") in OPCODES:
        return OPCODES[(mnem, "REL")], ["REL", value]
    if (mnem, "NN") in OPCODES:
        value = 0 if value is None else value
        return OPCODES[(mnem, "NN")], [value & 0xFF, (value >> 8) & 0xFF]
    raise AsmError("no address mode for %s %s" % (mnem, op_text))


def assemble(lines):
    """Return (memory dict, {line index: address}, stop address)."""
    labels = {}
    for final in (False, True):
        mem = {}
        addrs = {}
        pc = START
        stop = None
        for i, raw in enumerate(lines):
            code = raw.split(";", 1)[0].strip()
            if not code:
                continue
            if code.endswith(":"):
                labels[code[:-1].strip()] = pc
                continue
            word, _, rest = code.partition(" ")
            word = word.lower()
            if word == ".org":
                if stop is None:
                    stop = pc
                pc = evaluate(rest, labels, True)
                continue
            if word == ".addr":
                value = evaluate(rest, labels, final) or 0
                mem[pc], mem[pc + 1] = value & 0xFF, value >> 8
                pc += 2
                continue
            if word == ".byte":
                for v in rest.split(","):
                    mem[pc] = (evaluate(v, labels, final) or 0) & 0xFF
                    pc += 1
                continue
            op, operand = classify(word, rest, labels, final)
            addrs[i] = pc
            mem[pc] = op
            if operand[:1] == ["REL"]:
                target = operand[1]
                if final:
                    offset = target - (pc + 2)
                    if not -128 <= offset <= 127:
                        raise AsmError("branch out of range: %s" % raw.strip())
                    mem[pc + 1] = offset & 0xFF
                pc += 2
            else:
                for j, b in enumerate(operand):
                    mem[pc + 1 + j] = b
                pc += 1 + len(operand)
        if stop is None:
            stop = pc
    mem.setdefault(0xFFFE, START & 0xFF)
    mem.setdefault(0xFFFF, START >> 8)
    return mem, addrs, stop


CHECK = re.compile(r"^\s*(\(\s*[^)]+\)|[A-Za-z]+)\s*=\s*([$%]?[0-9A-Fa-f]+)\s*$")
REGS = {"a": 1, "b": 2, "c": 3, "dd": 4, "ee": 5, "sp": 6, "s": 7, "z": 8, "carry": 9, "d": 10, "i": 11}


def checks_for(comment):
    out = []
    for term in re.split(r"[,;]", comment):
        m = CHECK.match(term)
        if not m:
            continue
        name, value = m.group(1), parse_number(m.group(2))
        if value is None:
            continue
        key = name.lower()
        if key.startswith("("):
            addr = parse_number(key[1:-1])
            if addr is None:
                continue
            out.append(("mem", addr, value, term.strip()))
        elif key == "bc" or key in REGS:
            out.append((key, None, value, term.strip()))
    return out


def run(mem, stop, workdir, max_clocks=20000):
    hex_path = os.path.join(workdir, "prog.hex")
    with open(hex_path, "w") as f:
        for addr in sorted(mem):
            f.write("@%04x %02x\n" % (addr, mem[addr]))
    vvp = os.path.join(workdir, "tb.vvp")
    out = subprocess.run(["vvp", "-n", vvp, "+hex=" + hex_path, "+stop=%04x" % stop, "+max=%d" % max_clocks],
                         capture_output=True, text=True, check=True).stdout
    return out.splitlines()


def check_block(lines, workdir, first_line):
    mem, addrs, stop = assemble(lines)
    log = run(mem, stop, workdir)
    pending = {}
    for i, addr in addrs.items():
        comment = lines[i].split(";", 1)[1] if ";" in lines[i] else ""
        cs = checks_for(comment)
        if cs:
            pending.setdefault(addr, []).append((i, cs))
    memory = dict(mem)
    failures = []
    prev = None
    for entry in log:
        parts = entry.split()
        if parts[0] == "W":
            memory[int(parts[1], 16)] = int(parts[2], 16)
        elif parts[0] == "F":
            state = [int(x, 16) for x in parts[1:13]]
            if prev in pending:
                for i, cs in pending.pop(prev):
                    for key, addr, value, text in cs:
                        if key == "mem":
                            got = memory.get(addr, 0)
                        elif key == "bc":
                            got = (state[REGS["b"]] << 8) | state[REGS["c"]]
                        else:
                            got = state[REGS[key]]
                        if got != value:
                            failures.append("line %d `%s`: %s, but got $%X" % (first_line + i, lines[i].strip(), text, got))
            prev = state[0]
    for addr, items in pending.items():
        for i, _ in items:
            failures.append("line %d `%s`: never completed" % (first_line + i, lines[i].strip()))
    return failures


# ---------------------------------------------------------------------------
# Cycle counts: every "| Mode | Opcode | Cycles |" table row is timed
# ---------------------------------------------------------------------------

TABLE_ROW = re.compile(r"^\| [^|]+\| ([0-9A-F]{2})\s+\| ([^|]+?)\s*\|$")
OPERAND = {"#N": "#1", "NN": "target", "REL": "target"}


def cycle_rows():
    """Yield (doc path, line number, opcode, cycles taken, cycles not taken)."""
    for path in sorted(glob.glob(os.path.join(ROOT, "doc", "*.md"))):
        with open(path) as f:
            for n, line in enumerate(f, 1):
                m = TABLE_ROW.match(line)
                if not m:
                    continue
                text = m.group(2)
                c = re.fullmatch(r"(\d+)(?: \((\d+) if not taken\))?", text)
                if not c:
                    yield path, n, int(m.group(1), 16), None, text
                    continue
                taken = int(c.group(1))
                yield path, n, int(m.group(1), 16), taken, int(c.group(2) or taken)


def flag_setup(op, taken):
    """Instructions that make a conditional jump on row 5x/6x/7x go the given way."""
    hi, mode = op >> 4, op & 7
    if hi not in (5, 6, 7) or mode not in (4, 5, 6):
        return []
    want_set = (not taken) if mode == 4 else taken   # relative jumps when the flag is clear
    return {5: ["ldaz"] if want_set else ["lda #1"],
            6: ["lda #$80"] if want_set else ["lda #1"],
            7: ["sec"] if want_set else ["clc"]}[hi]


def time_opcode(op, taken, workdir):
    """Measure the clocks from the opcode's fetch to the next fetch, in cycles."""
    name = mnemonics()[op].split(" / ")[0]
    parts = name.split(" ", 1)
    form = parts[1] if len(parts) > 1 else ""
    operand = OPERAND.get("REL" if form == "label" else form, form.lower())
    sp = {0xF2: "$0FFE", 0xF3: "$0FFA"}.get(op, "$1000")
    setup = ["lds " + sp, "ldb #$30", "ldcz"] + flag_setup(op, taken)
    lines = (setup +
             [(parts[0].lower() + " " + operand).strip(), "target:", "nop", "nop",
              ".org $3000", ".addr target",                 # pointer for (BC) jumps
              ".org $0FFA", ".byte 0, 0, 0, 0", ".addr target",  # stack for RTS / RTI
              ".org $FFFA", ".addr target"])                # IRQ vector for BRK
    mem, addrs, stop = assemble(lines)
    test_addr = addrs[len(setup)]
    log = run(mem, stop, workdir, max_clocks=400)
    start = None
    for entry in log:
        parts = entry.split()
        if parts[0] != "F":
            continue
        pc, clock = int(parts[1], 16), int(parts[13])
        if start is not None:
            return (clock - start) / 2.0
        if pc == test_addr:
            start = clock
    return None


def check_cycles(workdir):
    failures, timed = [], 0
    for path, n, op, taken, not_taken in cycle_rows():
        where = "%s:%d (%02X)" % (os.path.relpath(path, ROOT), n, op)
        if taken is None:
            if op == 0xF4:      # HLT waits for an interrupt, which this bench never sends
                continue
            failures.append("%s: can't read cycle count %r" % (where, not_taken))
            continue
        cond = bool(flag_setup(op, True))
        for want_taken, expected in ((True, taken), (False, not_taken)) if cond else ((True, taken),):
            got = time_opcode(op, want_taken, workdir)
            timed += 1
            if got != expected:
                failures.append("%s%s: docs say %d cycles, measured %s" % (
                    where, (" taken" if want_taken else " not taken") if cond else "", expected, got))
    return timed, failures


def code_blocks(path):
    blocks, current, start = [], None, 0
    with open(path) as f:
        for n, line in enumerate(f, 1):
            if line.startswith("```"):
                if current is None:
                    current, start = [], n + 1
                else:
                    blocks.append((start, current))
                    current = None
            elif current is not None:
                current.append(line.rstrip("\n"))
    return blocks


def main():
    workdir = tempfile.mkdtemp(prefix="r88doc")
    sources = ["sim/tb_program.v"] + sorted(
        os.path.basename(p) for p in glob.glob(os.path.join(VERILOG, "*.v")))
    subprocess.run(["iverilog", "-g2005", "-o", os.path.join(workdir, "tb.vvp")] + sources,
                   cwd=VERILOG, check=True)
    total = bad = 0
    for path in sorted(glob.glob(os.path.join(ROOT, "doc", "*.md"))):
        for start, lines in code_blocks(path):
            total += 1
            name = "%s:%d" % (os.path.relpath(path, ROOT), start)
            try:
                failures = check_block(lines, workdir, start)
            except AsmError as e:
                failures = ["assembly error: %s" % e]
            if failures:
                bad += 1
                print("FAIL " + name)
                for f in failures:
                    print("     " + f)
    timed, cycle_failures = check_cycles(workdir)
    for f in cycle_failures:
        print("FAIL " + f)
    if bad or cycle_failures:
        print("%d of %d doc examples FAILED, %d of %d cycle counts FAILED" % (
            bad, total, len(cycle_failures), timed))
        sys.exit(1)
    print("PASS: all %d doc examples and %d cycle counts match the hardware" % (total, timed))


if __name__ == "__main__":
    main()
