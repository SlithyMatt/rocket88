# RTS
"ReTurn from Subroutine"

## Behavior
Returns from a subroutine called by [JSR](jsr.md#jsr) or one of its variants. The return address is pulled from the stack (low byte first) into PC.

## Addressing Modes
| Mode     | Opcode (hex) | Cycles |
|----------|--------------|--------|
| Implicit | F2           | 2      |

## Register Effects
PC will contain the return address. SP is incremented by 2.

## Flag Effects
None

## Stack Effects
The return address is pulled from the stack.

## Example
```
lds $1000   ; SP = $1000
jsr sub     ; SP = $0FFE
ldb #2      ; A = 1, B = 2, SP = $1000

.org $0400
sub:
lda #1      ; A = 1
rts
```

# RTI
"ReTurn from Interrupt"

## Behavior
Returns from an interrupt service routine, entered by an IRQ, an NMI or [BRK](brk.md). The registers that were pushed when the interrupt was serviced are pulled from the stack, in this order: C, B, A, P, and then PC (low byte first). Since P is restored, the flags (including Interrupt Disable) are all returned to their state before the interrupt.

## Addressing Modes
| Mode     | Opcode (hex) | Cycles |
|----------|--------------|--------|
| Implicit | F3           | 4      |

## Register Effects
A, B, C and PC will contain the values pulled from the stack. SP is incremented by 6.

## Flag Effects
All flags are loaded from the value of P pulled from the stack.

## Stack Effects
C, B, A, P and PC are pulled from the stack.

## Example
```
lds $1000   ; SP = $1000
lda #$01
ldb #$02
sec         ; carry = 1
brk         ; SP = $0FFA
sta $3000   ; ($3000) = $01, B = $02, carry = 1, SP = $1000

.org $0400
irq_handler:
lda #$99    ; A = $99, I = 1
ldb #$98
clc
rti

.org $FFFA
.addr irq_handler
```
