# BRK
"BReaK"

## Behavior
Triggers a software interrupt, in the same way as an IRQ, but regardless of the Interrupt Disable flag. The following are pushed onto the stack, in this order: PC (the address of the next instruction, high byte first), P, A, B and C. Then the Interrupt Disable flag is set and execution continues at the address in the IRQ vector at $FFFA. The service routine returns with [RTI](ret.md#rti).

The Break (K) flag is set in the copy of P pushed to the stack, so the service routine can tell a BRK from a hardware IRQ by reading P from the stack. After the registers are pushed, P is 3 bytes above the stack pointer.

## Addressing Modes
| Mode     | Opcode (hex) | Cycles |
|----------|--------------|--------|
| Implicit | F5           | 6      |

## Register Effects
PC will contain the IRQ vector. SP is decremented by 6.

## Flag Effects
K is set (and pushed)
I is set (after P is pushed)
Other flags unaffected

## Stack Effects
PC, P, A, B and C are pushed onto the stack.

## Example
The following service routine checks whether it was entered by BRK.
```
lds $1000   ; SP = $1000
brk         ; SP = $0FFA
nop         ; SP = $1000

.org $0400
irq_handler:
lbcs        ; BC = $0FFA
inc bc
inc bc
inc bc      ; BC = $0FFD
lda (bc)    ; read P from the stack
and #$04    ; A = $04, so K was set: this is a BRK
rti

.org $FFFA
.addr irq_handler
```
