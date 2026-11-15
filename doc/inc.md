# INC
"INCrement"

## Behavior
Adds one to the value in a register or in memory. Increments are always binary, even when the Decimal flag is set.

For the 8-bit forms (A, B, C, and memory at BC), the carry flag is set when the value wraps around from $FF to $00, and S and Z are set from the new value. For the 16-bit forms (BC, DD and EE), only the Zero flag is affected, being set when the value wraps around from $FFFF to $0000.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| A Register  | 87           | 2      |
| B Register  | 8F           | 2      |
| C Register  | 97           | 2      |
| BC Indirect | BF           | 2      |
| BC Register | FD           | 2      |
| DD Register | 60           | 2      |
| EE Register | 70           | 2      |

## Register Effects
The register incremented will contain its previous value plus one.

## Flag Effects
For A, B, C and (BC):
S is set when the new value is negative (i.e. bit 7 is set)
Z is set when the new value is zero
C is set when the value wrapped around from $FF
Other flags unaffected

For BC, DD and EE:
Z is set when the new value is zero
Other flags unaffected

## Stack Effects
None

## Example
```
lda #$FF    ; A = $FF
inc a       ; A = $00, Z = 1, carry = 1
ldb #$12
ldc #$FF    ; BC = $12FF
inc bc      ; BC = $1300, Z = 0
lda #$41
sta (bc)    ; ($1300) = $41
inc (bc)    ; ($1300) = $42, carry = 0
```
