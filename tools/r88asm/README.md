# r88asm
An assembler for the ROCKET88 instruction set, written in portable C99 with no dependencies beyond the standard library. It builds with gcc on Linux, with MinGW on Windows, or with clang.

## Building
```
make
```
or, without make:
```
gcc -std=c99 -O2 -o r88asm r88asm.c
```

On macOS, `gcc` is Apple's clang; to build with GNU gcc from Homebrew, use `make CC=gcc-16` (or your installed version). `make test` runs the test suite, which needs Python 3 and [Icarus Verilog](https://steveicarus.github.io/iverilog/) (see [Tests](#tests)).

## Usage
```
r88asm [options] input.asm [more.asm ...]
  -o <file>    output file (default: first input with .bin/.hex/.mem)
  -f <format>  bin: raw binary from lowest to highest address (default)
               hex: Intel HEX
               mem: Verilog $readmemh image
  -l <file>    write a listing
  -p <byte>    pad value for gaps in bin output (default 0)
```
Multiple input files are assembled together as one program, in the order given, so they can share labels and constants.

A raw binary covers only the addresses that were assembled, from the lowest to the highest. For example, a ROM assembled at $F000-$FFFF produces a 4 KB file. Intel HEX and `$readmemh` images record the address of each byte, so they don't need padding.

Errors are reported as `file:line: error: message`, and no output is written if there are any.

## Syntax
One statement per line. Everything after a `;` is a comment. Mnemonics, register names and directives are not case sensitive, but labels and constants are.

```
SCREEN = $8000              ; constant

.org $F000                  ; set the address
start:                      ; label
   lds $1000                ; instruction
   lda #message.low         ; low byte of an address
   ldb #message.high
loop: jmpr loop             ; a label can share a line with an instruction

message:
   .byte "Hello", 0         ; data

.org $FFFE
   .addr start              ; RESET vector
```

### Instructions
Instructions are written as in the [instruction set reference](../../doc/instructions.md). The addressing mode comes from the operand:

| Operand              | Mode                                                  |
|----------------------|-------------------------------------------------------|
| (none)               | Implicit or Zero (`ldaz`, `pha`, `nop`)               |
| `a`, `b`, `c`        | Register                                              |
| `bc`, `dd`, `ee`     | 16-bit register (`inc bc`, `lds bc`)                  |
| `(bc)`, `(dd)`       | Indirect                                              |
| `#expression`        | Immediate                                             |
| `expression`         | Absolute, or Relative for the jumps and calls that take a label (`jmpr`, `jpnz`, `jsrr`, ...) |

An immediate value of zero (such as `lda #0`) assembles to the shorter Zero mode opcode (`ldaz`), as the reference recommends. Relative targets must be within -128 to +127 bytes of the next instruction.

### Numbers and expressions
| Form       | Meaning                    |
|------------|----------------------------|
| `255`      | decimal                    |
| `$FF`, `0xFF` | hexadecimal             |
| `%11111111`| binary                     |
| `'A'`      | character code             |
| `*`        | address of the current statement |
| `name`     | label or constant          |

Operators, from lowest to highest precedence: `|`, `^`, `&`, `<<` `>>`, `+` `-`, `*` `/`, then unary `-` `+` `~`. Parentheses group as usual, and a `.low` or `.high` suffix takes the low or high byte of a value, as in `label.low` or `(table+2).high`.

Labels and constants can be used before they are defined; the assembler makes as many passes as it needs.

### Directives
| Directive                  | Meaning                                                    |
|----------------------------|------------------------------------------------------------|
| `NAME = expression`        | Define a constant. It may be defined again only with the same value. |
| `.org expression`          | Set the address of the following code                      |
| `.byte value, ...`         | Bytes; a value can also be a `"string"` (also `.db`)        |
| `.word value, ...`         | 16-bit values, low byte first (also `.addr`, `.dw`)         |
| `.fill count [, value]`    | `count` copies of a byte (default 0)                       |

Strings and character constants support the escapes `\n`, `\r`, `\t`, `\0`, `\\`, `\'` and `\"`.

### Macros
A macro is a named block of code with any number of parameters. Each time it's used, it's replaced by its body, with each parameter replaced by the matching argument.
```
.macro STORE16 addr, value      ; store a 16-bit value at addr and addr+1
    lda #value.low
    sta addr
    lda #value.high
    sta addr+1
.endmacro

    STORE16 $3000, table+2      ; use it like an instruction
    STORE16 POINTER, BASE*2+$10 ; arguments can be any expression
```
* `.macro NAME [param, ...]` starts a definition, and `.endmacro` (or `.endm`) ends it. A macro can have no parameters, or as many as you like, and must be used with exactly that many arguments, separated by commas.
* An argument can be anything an operand or value can be: a number, a label, an expression, a register (`b`), an indirect operand (`(bc)`), a `#value`, or a `"string"`. Commas inside parentheses or quotes don't separate arguments.
* An argument that's an expression is put in parentheses where it's substituted, so it keeps its meaning: with `x` as `1+2`, `#x*2` is `(1+2)*2`, which is 6. Use `.low` and `.high` on parameters as on any value.
* Parameters aren't replaced inside comments, strings, character constants or numbers.
* Labels in a macro that start with `@` (`@loop:`, `jpnz @loop`) are local: each use of the macro gets its own copy, so a macro with a loop can be used more than once.
* A label can come before a macro use (`start: STORE16 $3000, 1`), and labels and constants used in arguments can be defined later.
* Macros can use other macros, but not themselves. A macro can be used before its definition, and can be defined in one input file and used in another.
* Macro names can't be instruction mnemonics, and parameter names can't be register names (`a`, `b`, `c`, `bc`, `dd`, `ee`).

In a listing, the line that uses a macro is followed by its expansion, with each expanded line marked with `+` and numbered by the line that used the macro. An error in an expansion is reported at the line that used the macro, followed by the macro name and the line of the definition, as in:
```
main.asm:42: error: value 261 does not fit in a byte (in macro 'STORE8', defs.asm:7)
```

## Example
[examples/showcase.asm](examples/showcase.asm) is a ROM image that tours the instruction set: it copies a string, does 16-bit and BCD arithmetic, multiplies in a subroutine, scans a table, works the stack, counts BRKs in an interrupt handler, dispatches through a jump table, and makes conditional subroutine calls, storing each result in RAM. It uses every documented instruction except RST, every operand form, and macros (`ADD16` with expression arguments, and `FILL` with a local label, used twice).
```
./r88asm -l examples/showcase.lst examples/showcase.asm
```
This writes `examples/showcase.bin`, a 4 KB image of $F000-$FFFF, and a listing showing the address and bytes of every line.

## Tests
`make test` runs [tests/run_tests.py](tests/run_tests.py), which checks:
* Every code example in the [instruction docs](../../doc) assembles to exactly the same bytes as the reference assembler in [tools/check_doc_examples.py](../check_doc_examples.py), whose output is run on the Verilog core to check the examples' results and cycle counts.
* The example ROM and RAM programs from the main [README](../../README.md) are assembled together and run on the Verilog core, checking the interrupt vectors they set up in RAM.
* Expressions, directives, Zero mode selection and all three output formats.
* Macros: many parameters, expression, register, string and label arguments, local labels, nesting, and their errors.
* Errors are reported, at the right line, for bad input.
* The showcase example is assembled and run on the Verilog core, and every result it stores is checked against values computed independently by the test.
