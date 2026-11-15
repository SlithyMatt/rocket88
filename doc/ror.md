# ROR
"ROtate Right"

## Behavior
Same as [LSR](lsr.md), but bit 7 is filled with the previous value of the carry flag instead of zero. Together with LSR, this allows values of more than 8 bits to be shifted right one byte at a time, starting with the most significant byte.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| A Register  | A9           | 2      |
| B Register  | AA           | 2      |
| C Register  | AB           | 2      |
| Absolute    | AD           | 4      |
| BC Indirect | AE           | 2      |

## Register Effects
The register rotated will contain the rotated value.

## Flag Effects
S is set to the previous value of the carry flag (now bit 7)
Z is set when the rotated value is zero
C receives bit 0 of the value before the rotation
Other flags unaffected

## Stack Effects
None

## Example
The following code shifts the 16-bit value in BC ($0103) right by one bit.
```
ldb #$01
ldc #$03    ; BC = $0103
lsr b       ; B = $00, carry = 1
ror c       ; C = $81, S = 1, carry = 1
```
