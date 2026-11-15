# JSR
"Jump to SubRoutine"

## Behavior
Calls a subroutine. The return address (the address of the next instruction) is pushed onto the stack, high byte first, so that the low byte is at the new stack pointer. Then execution continues at the subroutine address, in the same way as [JMP](jmp.md#jmp). The subroutine returns with [RTS](ret.md#rts).

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Absolute    | 4D           | 5      |
| BC Indirect | 4E           | 4      |

## Register Effects
PC will contain the subroutine address. SP is decremented by 2.

## Flag Effects
None

## Stack Effects
The return address is pushed onto the stack.

## Example
```
lds $1000   ; SP = $1000
lda #5      ; A = 5
jsr double  ; SP = $0FFE
sta $3000   ; ($3000) = 10, SP = $1000

.org $0400
double:
add a       ; A = 10
rts
```

# JSRR
"Jump to SubRoutine Relative"

## Behavior
Same as [JSR](#jsr), but the subroutine address is relative to the next instruction, in the same way as [JMPR](jmp.md#jmpr).

## Addressing Modes
| Mode     | Opcode (hex) | Cycles |
|----------|--------------|--------|
| Relative | 4C           | 4      |

## Example
```
lds $1000   ; SP = $1000
lda #5      ; A = 5
jsrr double ; SP = $0FFE
sta $3000   ; ($3000) = 10, SP = $1000
jmpr done
double:
add a       ; A = 10
rts
done:
```

# JSNZ
"Jump to Subroutine if Not Zero"

## Behavior
Same as [JSRR](#jsrr), but only calls the subroutine if the Zero flag is clear. Otherwise, nothing is pushed and execution continues with the next instruction.

## Addressing Modes
| Mode     | Opcode (hex) | Cycles             |
|----------|--------------|--------------------|
| Relative | 5C           | 4 (2 if not taken) |

# JSRZ
"Jump to SubRoutine if Zero"

## Behavior
Same as [JSR](#jsr), but only calls the subroutine if the Zero flag is set. Otherwise, nothing is pushed and execution continues with the next instruction.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles             |
|-------------|--------------|--------------------|
| Absolute    | 5D           | 5 (4 if not taken) |
| BC Indirect | 5E           | 4 (2 if not taken) |

## Example
```
lds $1000   ; SP = $1000
lda #$00
sta $3000
ldaz        ; Z = 1
jsrz mark   ; called, since Z = 1
lda #1      ; Z = 0
jsrz mark   ; not called, SP = $1000
lda $3000   ; A = 1

.org $0400
mark:
inc a
sta $3000
rts
```

# JSRP
"Jump to SubRoutine if Positive"

## Behavior
Same as [JSRR](#jsrr), but only calls the subroutine if the Sign flag is clear. Otherwise, nothing is pushed and execution continues with the next instruction.

## Addressing Modes
| Mode     | Opcode (hex) | Cycles             |
|----------|--------------|--------------------|
| Relative | 6C           | 4 (2 if not taken) |

# JSRN
"Jump to SubRoutine if Negative"

## Behavior
Same as [JSR](#jsr), but only calls the subroutine if the Sign flag is set. Otherwise, nothing is pushed and execution continues with the next instruction.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles             |
|-------------|--------------|--------------------|
| Absolute    | 6D           | 5 (4 if not taken) |
| BC Indirect | 6E           | 4 (2 if not taken) |

# JSNC
"Jump to Subroutine if Not Carry"

## Behavior
Same as [JSRR](#jsrr), but only calls the subroutine if the carry flag is clear. Otherwise, nothing is pushed and execution continues with the next instruction.

## Addressing Modes
| Mode     | Opcode (hex) | Cycles             |
|----------|--------------|--------------------|
| Relative | 7C           | 4 (2 if not taken) |

## Example
```
lds $1000   ; SP = $1000
ldbz        ; B = 0
lda #$10
cpa #$20    ; carry = 0, since A < $20
jsnc count  ; called
cpa #$08    ; carry = 1, since A >= $08
jsnc count  ; not called
stb $3000   ; ($3000) = 1
jmpr done
count:
inc b
rts
done:
```

# JSRC
"Jump to SubRoutine if Carry"

## Behavior
Same as [JSR](#jsr), but only calls the subroutine if the carry flag is set. Otherwise, nothing is pushed and execution continues with the next instruction.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles             |
|-------------|--------------|--------------------|
| Absolute    | 7D           | 5 (4 if not taken) |
| BC Indirect | 7E           | 4 (2 if not taken) |
