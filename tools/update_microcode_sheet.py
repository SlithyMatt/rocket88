"""Regenerate the Microcode sheet of Rocket88.ods from the Verilog decoder.

The table comes from verilog/sim/microcode_dump.v, so the sheet always matches
r88_decoder.v. From the repository root:

    cd verilog
    iverilog -g2005 -o sim/dump.vvp sim/microcode_dump.v r88_decoder.v
    vvp -n sim/dump.vvp > sim/microcode.tsv
    cd ..
    python3 tools/update_microcode_sheet.py verilog/sim/microcode.tsv Rocket88.ods

Close Rocket88.ods in LibreOffice first. Only the Microcode sheet is changed.

This file plays two roles: run with python3 it is the launcher, which starts a
headless LibreOffice with a throwaway profile and runs this same file inside
it as a Python macro (the `run` function), where the UNO API is available.
"""

import os
import shutil
import subprocess
import sys
import tempfile

SOFFICE = os.environ.get("SOFFICE", "/Applications/LibreOffice.app/Contents/MacOS/soffice")
SHEET = "Microcode"

BORDER_GRAY = 0x808080
FETCH_COLOR = 0xFFFF00      # opcode fetch steps (1n, 1p)
OPERAND_COLOR = 0xFFBF00    # NN operand fetch steps

# Mnemonics for the documented opcodes (from the README opcode table),
# plus the representative NOPs 00, 04 and 05.
REG = {1: "A", 2: "B", 3: "C"}
MODE = {0: "Z", 1: "A", 2: "B", 3: "C", 4: "#N", 5: "NN", 6: "(BC)"}


def mnemonics():
    m = {0x00: "NOP", 0x04: "NOP+1", 0x05: "NOP+2"}
    for r in (1, 2, 3):
        x = REG[r]
        for mode in range(7):
            m[(r << 4) | mode] = "LD%sZ" % x if mode == 0 else "LD%s %s" % (x, MODE[mode])
        m[(r << 4) | 7] = "PL" + x
        for mode in range(5):
            m[(r << 4) | 8 | mode] = "CP%sZ" % x if mode == 0 else "CP%s %s" % (x, MODE[mode])
        m[(r << 4) | 0xD] = "ST%s NN" % x
        m[(r << 4) | 0xE] = "ST%s (BC)" % x
        m[(r << 4) | 0xF] = "PH" + x
    jumps = {4: ("JMPR", "JMP", "JSRR", "JSR"), 5: ("JPNZ", "JMPZ", "JSNZ", "JSRZ"),
             6: ("JMPP", "JMPN", "JSRP", "JSRN"), 7: ("JPNC", "JMPC", "JSNC", "JSRC")}
    for hi, (rel, ab, srel, sab) in jumps.items():
        m[(hi << 4) | 4] = rel + " label"
        m[(hi << 4) | 5] = ab + " NN"
        m[(hi << 4) | 6] = ab + " (BC)"
        m[(hi << 4) | 0xC] = srel + " label"
        m[(hi << 4) | 0xD] = sab + " NN"
        m[(hi << 4) | 0xE] = sab + " (BC)"
    m.update({0x40: "EXD", 0x48: "EXE", 0x50: "LDA (DD)", 0x58: "STA (DD)",
              0x60: "INC DD", 0x68: "DEC DD", 0x70: "INC EE", 0x78: "DEC EE"})
    alu = {0x8: ("ADD", "ADC", "ADDZ", "ADCZ"), 0x9: ("SUB", "SBC", "SUBZ", "SBCZ"),
           0xC: ("ORA", "NOR", "ORZ", "NORZ"), 0xD: ("AND", "NND", "ANDZ", "NNDZ"),
           0xE: ("XOR", "XNR", "XORZ", "XNRZ")}
    for hi, (a, b, az, bz) in alu.items():
        for opt, (name, zname) in enumerate(((a, az), (b, bz))):
            for mode in range(7):
                m[(hi << 4) | (opt << 3) | mode] = zname if mode == 0 else "%s %s" % (name, MODE[mode])
    shifts = {0xA: ("LSR", "ROR"), 0xB: ("ASL", "ROL")}
    for hi, names in shifts.items():
        for opt, name in enumerate(names):
            for mode in (1, 2, 3, 5, 6):
                m[(hi << 4) | (opt << 3) | mode] = "%s %s" % (name, MODE[mode])
    m.update({0x87: "INC A", 0x8F: "INC B", 0x97: "INC C", 0x9F: "DEC A",
              0xA7: "DEC B", 0xAF: "DEC C", 0xB7: "NEG", 0xBF: "INC (BC)",
              0xC7: "INV B", 0xCF: "INV C", 0xD7: "SED", 0xDF: "CLD",
              0xE7: "PHP", 0xEF: "PLP",
              0xF0: "SEI", 0xF1: "CLI", 0xF2: "RTS", 0xF3: "RTI", 0xF4: "HLT",
              0xF5: "BRK", 0xF6: "RST / RESET pin", 0xF7: "LDS NN", 0xF8: "LDS BC",
              0xF9: "LDS (BC)", 0xFA: "LBCS", 0xFB: "CLC", 0xFC: "SEC",
              0xFD: "INC BC", 0xFE: "DEC BC"})
    return m


LEGEND = [
    "Notes",
    "Each row is one sysClock (rising edge). Steps n/p of a cycle are consecutive clocks; every instruction ends on a p step.",
    "Yellow: opcode fetch (shared by every instruction). Orange: NN operand fetch into the memory controller (shared by every NN opcode).",
    "Other opcodes list only their own steps. Generated from verilog/r88_decoder.v by tools/update_microcode_sheet.py; do not edit by hand.",
    "intD: Z, or a constant driven by the decoder. carryIn: ALU carry in (X unused, C carry flag, 1 forced). decMode: ALU decimal (X unused, D flag, 0 binary).",
    "breakFlag, irqEn, setCarry, setDecimal: value written to that flag at end of step (X unchanged). Init shows power-on values. 1n of every fetch clears K.",
    "regLeftSel with regLeft16: 0 DD, 1 EE, 2 PC, 3 SP, 4 BC. regSel: 0 A, 1 B, 2 C, 3 DDL, 4 DDH, 5 EEL, 6 EEH, 7 PCL, 8 PCH, 9 SPL, 10 SPH, 11 P.",
    "regExchange: 1 BC<->DD, 2 BC<->EE. z16En: Z from 16-bit result. cOutEn/cInv: C from ALU carry (inverted for compares). stall: hold step (HLT).",
]


def read_rows(tsv_path):
    names = mnemonics()
    with open(tsv_path) as f:
        lines = [l.rstrip("\n").split("\t") for l in f if "\t" in l]
    header = lines[0]
    groups = []   # (label, [rows])
    current = None
    for fields in lines[1:]:
        group, variant, values = fields[0], fields[1], fields[2:]
        if group in ("INIT", "IRQ", "NMI"):
            label = {"INIT": "Init", "IRQ": "IRQ (pin)", "NMI": "NMI (pin)"}[group]
        else:
            op = int(group, 16)
            if op not in names:
                continue
            label = "%02X (%s)" % (op, names[op])
        if variant != "-":
            label += " " + variant
        if current is None or current[0] != label:
            current = (label, [])
            groups.append(current)
        current[1].append(values)
    return ["Opcode"] + header[2:], groups


def cell_value(text):
    try:
        return float(int(text))
    except ValueError:
        return text


# ---------------------------------------------------------------------------
# Macro side: runs inside LibreOffice
# ---------------------------------------------------------------------------

def _write_sheet(desktop, tsv_path, ods_path):
    import uno
    from com.sun.star.beans import PropertyValue
    from com.sun.star.table import BorderLine2

    def prop(name, value):
        p = PropertyValue()
        p.Name = name
        p.Value = value
        return p

    header, groups = read_rows(tsv_path)
    doc = desktop.loadComponentFromURL(uno.systemPathToFileUrl(ods_path), "_blank", 0,
                                       (prop("Hidden", True),))
    try:
        sheet = doc.Sheets.getByName(SHEET)

        # Clear old contents and hard formatting
        sheet.getCellRangeByPosition(0, 0, 63, 2047).clearContents(1023)

        ncols = len(header)
        data = [tuple(header)]
        fills = []      # (row index, color)
        tops = []       # row indexes starting a group
        for label, rows in groups:
            tops.append(len(data))
            for i, values in enumerate(rows):
                if label.startswith("00 "):
                    fills.append((len(data), FETCH_COLOR))
                elif label.startswith(("05 ", "F7 ")):
                    fills.append((len(data), OPERAND_COLOR))
                data.append(tuple([label if i == 0 else ""] + [cell_value(v) for v in values]))
        sheet.getCellRangeByPosition(0, 0, ncols - 1, len(data) - 1).DataArray = tuple(data)

        line = BorderLine2()
        line.Color = BORDER_GRAY
        line.OuterLineWidth = 26    # 0.74pt in 1/100 mm
        line.LineWidth = 26
        head = sheet.getCellRangeByPosition(0, 0, ncols - 1, 0)
        head.CharWeight = 150.0
        head.BottomBorder = line
        for r in tops:
            sheet.getCellRangeByPosition(0, r, ncols - 1, r).TopBorder = line
        for r, color in fills:
            sheet.getCellRangeByPosition(1, r, ncols - 1, r).CellBackColor = color
        sheet.getCellRangeByPosition(0, len(data) - 1, ncols - 1, len(data) - 1).BottomBorder = line

        # Size the columns to fit the table (before adding the long legend lines)
        cols = sheet.Columns
        for c in range(ncols):
            cols.getByIndex(c).OptimalWidth = True

        # Legend below the table
        start = len(data) + 1
        for i, text in enumerate(LEGEND):
            sheet.getCellByPosition(0, start + i).String = text
        sheet.getCellByPosition(0, start).CharWeight = 150.0

        doc.storeToURL(uno.systemPathToFileUrl(ods_path), (prop("FilterName", "calc8"),))
        return "wrote %d rows in %d groups" % (len(data) - 1, len(groups))
    finally:
        doc.close(True)


def run(*args):
    """Macro entry point; arguments come from environment variables."""
    log = os.environ["R88_LOG"]
    desktop = XSCRIPTCONTEXT.getDesktop()  # noqa: F821 (provided by LibreOffice)
    try:
        message = "OK " + _write_sheet(desktop, os.environ["R88_TSV"], os.environ["R88_ODS"])
    except Exception:
        import traceback
        message = "ERROR\n" + traceback.format_exc()
    with open(log, "w") as f:
        f.write(message)
    desktop.terminate()


g_exportedScripts = (run,)


# ---------------------------------------------------------------------------
# Launcher side: runs with python3
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    tsv_path = os.path.abspath(sys.argv[1])
    ods_path = os.path.abspath(sys.argv[2])
    lock = os.path.join(os.path.dirname(ods_path), ".~lock.%s#" % os.path.basename(ods_path))
    if os.path.exists(lock):
        sys.exit("%s is open in LibreOffice; close it first" % ods_path)

    profile = tempfile.mkdtemp(prefix="r88lo")
    try:
        scripts = os.path.join(profile, "user", "Scripts", "python")
        os.makedirs(scripts)
        shutil.copy(os.path.abspath(__file__), os.path.join(scripts, "r88_microcode.py"))
        log = os.path.join(profile, "result.log")
        env = dict(os.environ, R88_TSV=tsv_path, R88_ODS=ods_path, R88_LOG=log)
        subprocess.run([SOFFICE, "--headless", "--invisible", "--norestore",
                        "-env:UserInstallation=file://" + profile,
                        "vnd.sun.star.script:r88_microcode.py$run?language=Python&location=user"],
                       env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)
        if not os.path.exists(log):
            sys.exit("LibreOffice did not run the macro")
        with open(log) as f:
            result = f.read()
        print(result)
        if not result.startswith("OK"):
            sys.exit(1)
    finally:
        shutil.rmtree(profile, ignore_errors=True)


if __name__ == "__main__":
    main()
