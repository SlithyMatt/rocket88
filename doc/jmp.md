# JMP
"JuMP"

## Behavior
Continues execution at a new address. In Absolute mode, the address is the operand. In BC Indirect mode, the 16-bit address is read from memory at the address in BC (low byte first), which allows jumping through a table of addresses or a vector in RAM.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Absolute    | 45           | 4      |
| BC Indirect | 46           | 3      |

## Register Effects
PC will contain the new address.

## Flag Effects
None

## Stack Effects
None

## Example
The following code stores the address of `target` at $3000, then jumps through it.
```
lda #target.low
sta $3000
lda #target.high
sta $3001
ldb #$30
ldcz        ; BC = $3000
jmp (bc)    ; jump to the address stored at $3000
ldb #$EE    ; skipped
target:
lda #1      ; A = 1, B = $30
```

# JMPR
"JuMP Relative"

## Behavior
Continues execution at an address relative to the next instruction. The operand is a signed offset from -128 to +127, added to the address of the following instruction. The assembler calculates the offset from a label, so JMPR is a shorter and faster alternative to JMP for nearby addresses.

## Addressing Modes
| Mode     | Opcode (hex) | Cycles |
|----------|--------------|--------|
| Relative | 44           | 2      |

## Register Effects
PC will contain the new address.

## Flag Effects
None

## Stack Effects
None

## Example
```
ldbz        ; B = $00
jmpr skip   ; jump over the next instruction
ldb #$EE    ; skipped
skip:
ldc #1      ; B = $00, C = 1
```

# JPNZ
"JumP if Not Zero"

## Behavior
Same as [JMPR](#jmpr), but only jumps if the Zero flag is clear. Otherwise, execution continues with the next instruction.

## Addressing Modes
| Mode     | Opcode (hex) | Cycles |
|----------|--------------|--------|
| Relative | 54           | 2      |

## Example
The following code adds 3 to B in a loop, counting A down to zero.
```
lda #3      ; A = 3
ldbz        ; B = 0
loop:
inc b
dec a
jpnz loop   ; repeat until A == 0
stb $3000   ; ($3000) = 3
```

# JMPZ
"JuMP if Zero"

## Behavior
Same as [JMP](#jmp), but only jumps if the Zero flag is set. Otherwise, execution continues with the next instruction.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles                 |
|-------------|--------------|------------------------|
| Absolute    | 55           | 4                      |
| BC Indirect | 56           | 3 (2 if not taken)     |

## Example
```
ldbz        ; B = $00
lda #$42
cpa #$42    ; Z = 1
jmpz equal  ; jump, since the values are equal
ldb #$EE    ; skipped
equal:
ldc #1      ; B = $00
```

# JMPP
"JuMP if Positive"

## Behavior
Same as [JMPR](#jmpr), but only jumps if the Sign flag is clear. Otherwise, execution continues with the next instruction.

## Addressing Modes
| Mode     | Opcode (hex) | Cycles |
|----------|--------------|--------|
| Relative | 64           | 2      |

## Example
```
ldbz        ; B = $00
lda #$10    ; S = 0
jmpp positive
ldb #$EE    ; skipped
positive:
ldc #1      ; B = $00
```

# JMPN
"JuMP if Negative"

## Behavior
Same as [JMP](#jmp), but only jumps if the Sign flag is set. Otherwise, execution continues with the next instruction.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles                 |
|-------------|--------------|------------------------|
| Absolute    | 65           | 4                      |
| BC Indirect | 66           | 3 (2 if not taken)     |

## Example
```
ldbz        ; B = $00
lda #$80    ; S = 1
jmpn negative
ldb #$EE    ; skipped
negative:
ldc #1      ; B = $00
```

# JPNC
"JumP if Not Carry"

## Behavior
Same as [JMPR](#jmpr), but only jumps if the carry flag is clear. Otherwise, execution continues with the next instruction. After a compare, this jumps if the register was less than the operand (as unsigned values).

## Addressing Modes
| Mode     | Opcode (hex) | Cycles |
|----------|--------------|--------|
| Relative | 74           | 2      |

## Example
```
ldbz        ; B = $00
lda #$10
cpa #$20    ; carry = 0, since A < $20
jpnc less
ldb #$EE    ; skipped
less:
ldc #1      ; B = $00
```

# JMPC
"JuMP if Carry"

## Behavior
Same as [JMP](#jmp), but only jumps if the carry flag is set. Otherwise, execution continues with the next instruction. After a compare, this jumps if the register was greater than or equal to the operand (as unsigned values).

## Addressing Modes
| Mode        | Opcode (hex) | Cycles                 |
|-------------|--------------|------------------------|
| Absolute    | 75           | 4                      |
| BC Indirect | 76           | 3 (2 if not taken)     |

## Example
```
ldbz        ; B = $00
lda #$F0
add #$20    ; carry = 1
jmpc overflow
ldb #$EE    ; skipped
overflow:
ldc #1      ; B = $00
```
