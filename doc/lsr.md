# LSR
"Logical Shift Right"

## Behavior
Shifts every bit of the value in a register or in memory one place to the right. Bit 0 is shifted into the carry flag, and bit 7 is filled with zero. This divides an unsigned value by two, with the remainder in the carry flag.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| A Register  | A1           | 2      |
| B Register  | A2           | 2      |
| C Register  | A3           | 2      |
| Absolute    | A5           | 4      |
| BC Indirect | A6           | 2      |

## Register Effects
The register shifted will contain the shifted value.

## Flag Effects
S is cleared (bit 7 of the result is always zero)
Z is set when the shifted value is zero
C receives bit 0 of the value before the shift
Other flags unaffected

## Stack Effects
None

## Example
```
lda #$81    ; A = $81
lsr a       ; A = $40, carry = 1
lsr a       ; A = $20, carry = 0
lda #$01
sta $3000
lsr $3000   ; ($3000) = $00, Z = 1, carry = 1
```
