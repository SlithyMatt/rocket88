# INV
"INVert"

## Behavior
Inverts every bit of the value in the B or C register (the one's complement). To invert the value in A, use [NORZ](or.md#nor-norz) or [XNRZ](xor.md#xnr-xnrz).

## Addressing Modes
| Mode       | Opcode (hex) | Cycles |
|------------|--------------|--------|
| B Register | C7           | 2      |
| C Register | CF           | 2      |

## Register Effects
The register inverted will contain the inverse of its previous value.

## Flag Effects
S is set when the new value is negative (i.e. bit 7 is set)
Z is set when the new value is zero
Other flags unaffected

## Stack Effects
None

## Example
```
ldb #$0F    ; B = $0F
inv b       ; B = $F0, S = 1
ldc #$FF    ; C = $FF
inv c       ; C = $00, Z = 1
```
