# ASL
"Arithmetic Shift Left"

## Behavior
Shifts every bit of the value in a register or in memory one place to the left. Bit 7 is shifted into the carry flag, and bit 0 is filled with zero. This multiplies a value by two, with the carry flag set if the result overflowed.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| A Register  | B1           | 2      |
| B Register  | B2           | 2      |
| C Register  | B3           | 2      |
| Absolute    | B5           | 4      |
| BC Indirect | B6           | 2      |

## Register Effects
The register shifted will contain the shifted value.

## Flag Effects
S is set when the shifted value is negative (i.e. bit 6 was set before the shift)
Z is set when the shifted value is zero
C receives bit 7 of the value before the shift
Other flags unaffected

## Stack Effects
None

## Example
```
lda #$C1    ; A = $C1
asl a       ; A = $82, S = 1, carry = 1
asl a       ; A = $04, S = 0, carry = 1
asl a       ; A = $08, carry = 0
```
