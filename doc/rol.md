# ROL
"ROtate Left"

## Behavior
Same as [ASL](asl.md), but bit 0 is filled with the previous value of the carry flag instead of zero. Together with ASL, this allows values of more than 8 bits to be shifted left one byte at a time, starting with the least significant byte.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| A Register  | B9           | 2      |
| B Register  | BA           | 2      |
| C Register  | BB           | 2      |
| Absolute    | BD           | 4      |
| BC Indirect | BE           | 2      |

## Register Effects
The register rotated will contain the rotated value.

## Flag Effects
S is set when the rotated value is negative (i.e. bit 6 was set before the rotation)
Z is set when the rotated value is zero
C receives bit 7 of the value before the rotation
Other flags unaffected

## Stack Effects
None

## Example
The following code shifts the 16-bit value stored at $3000 (low byte) and $3001 (high byte) left by one bit, from $0180 to $0300.
```
lda #$80
sta $3000
lda #$01
sta $3001
ldb #$30
ldcz        ; BC = $3000
asl (bc)    ; ($3000) = $00, carry = 1
inc bc      ; BC = $3001
rol (bc)    ; ($3001) = $03, carry = 0
```
