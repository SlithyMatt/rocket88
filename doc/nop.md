# NOP
"No OPeration"

## Behavior
NOP does literally nothing, except for taking up space in executable code. It has no affect on any registers, flags or memory, with the exception of PC, which will be incremented like it would for any implicit instruction. There are no arguments. NOP is generally useful for removing code from memory, replacing other opcodes and arguments with NOP opcodes to fill the space without changing the location of any other code. It can also be useful for introducing short delays into the code without having to deal with any sort of external timing, which can be useful for interfacing with slower hardware.

## Addressing Modes
| Mode     | Opcode (hex) |
|----------|--------------|
| Implicit | 00           |

## Register Effects
None

## Flag Effects
None

## Stack Effects
None

## Example
The following code uses NOP to kill time in a loop, ticking through the cycles to execute 10 NOP, DEC and JPNZ instructions.
```
   lda #10     ; init loop index for 10 iterations
loop:
   nop         ; do nothing
   dec a       ; decrement loop index
   jpnz loop   ; loop until index == 0
```

# "Undocumented" NOPs
There are many potential opcodes that are not supported by ROCKET88, and they are all effectively treated as NOPs, but it is recommended that assemblers only use the documented opcode for NOP. You can see in the [opcode table](../README.md#opcode-table) the empty cells that have no documented instruction, and each of them are effectively NOPs, but depending on the opcode, they may expect operands.

## Implicit
Most of the undocumented NOPs are implicit just like the official NOP, and don't require any arguments. Executing these opcodes will have the exact same result as executing an official NOP.

## Immediate
Certain undocumented NOPs are in a position in the [opcode table](../README.md#opcode-table) where they are supposed to be an Immediate Mode opcode, and therefore ROCKET88 will expect to fetch a single-byte operand after the opcode. This operand will be ignored, rather than being interpreted as another opcode.

## Absolute
Certain undocumented NOPs are in a position in the [opcode table](../README.md#opcode-table) where they are supposed to be an Absolute Mode opcode, and therefore ROCKET88 will expect to fetch a two-byte operand after the opcode. This operand will be ignored, rather than being interpreted as another instruction or two.