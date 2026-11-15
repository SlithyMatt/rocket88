# RST
"ReSeT"

## Behavior
Restarts the program, by continuing execution at the address in the RESET vector at $FFFE, in the same way as when the RESET pin is pulled low. Nothing is pushed onto the stack, and no other registers or flags are changed, so the Reset routine should initialize anything it depends on (starting with the stack pointer).

## Addressing Modes
| Mode     | Opcode (hex) | Cycles |
|----------|--------------|--------|
| Implicit | F6           | 3      |

## Register Effects
PC will contain the RESET vector.

## Flag Effects
None

## Stack Effects
None

## Example
```
fatal_error:
rst         ; start over from the RESET vector
```
