# DEC
"DECrement"

## Behavior
Subtracts one from the value in a register. Decrements are always binary, even when the Decimal flag is set.

For the 8-bit forms (A, B and C), the carry flag is set when a borrow is required (the value wraps around from $00 to $FF), and S and Z are set from the new value. For the 16-bit forms (BC, DD and EE), only the Zero flag is affected, being set when the new value is zero.

There is no form to decrement a value in memory.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| A Register  | 9F           | 2      |
| B Register  | A7           | 2      |
| C Register  | AF           | 2      |
| BC Register | FE           | 2      |
| DD Register | 68           | 2      |
| EE Register | 78           | 2      |

## Register Effects
The register decremented will contain its previous value minus one.

## Flag Effects
For A, B and C:
S is set when the new value is negative (i.e. bit 7 is set)
Z is set when the new value is zero
C is set when the value wrapped around from $00
Other flags unaffected

For BC, DD and EE:
Z is set when the new value is zero
Other flags unaffected

## Stack Effects
None

## Example
The following code counts B down from 3 to 0, then decrements BC past zero.
```
ldb #3      ; B = 3
loop:
dec b
jpnz loop   ; repeat until B == 0
stb $3000   ; ($3000) = 0
ldcz        ; BC = $0000
dec bc      ; BC = $FFFF, Z = 0
```
