# HLT
"HaLT"

## Behavior
Stops executing instructions until an interrupt is requested on the IRQ, NMI or RESET pin. This is useful for waiting on hardware without running a busy loop.

When an IRQ or NMI is serviced, the address of the instruction after HLT is pushed, so execution continues there after RTI. If an IRQ is requested while the Interrupt Disable flag is set, HLT stops waiting but the IRQ is not serviced, so execution simply continues with the next instruction.

## Addressing Modes
| Mode     | Opcode (hex) | Cycles                          |
|----------|--------------|---------------------------------|
| Implicit | F4           | 2, plus the time spent waiting  |

## Register Effects
None

## Flag Effects
None

## Stack Effects
None

## Example
The following loop does its work once each time an interrupt is serviced.
```
cli         ; allow IRQs
loop:
hlt         ; wait for an interrupt
jmpr loop
```
