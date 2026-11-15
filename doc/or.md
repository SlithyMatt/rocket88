# ORA, ORZ
"OR with A", "OR with Zero"

## Behavior
Performs a bitwise OR of the A register and the value referenced by the operand, and stores the result in A. Each bit of the result is set if that bit is set in either value, so ORA is typically used to set bits.

Assemblers should support two different mnemonics for the Zero mode opcode:
```
orz
ora #0
```
ORZ leaves A unchanged, but sets S and Z from the value in A without affecting the carry flag.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Zero        | C0           | 2      |
| A Register  | C1           | 2      |
| B Register  | C2           | 2      |
| C Register  | C3           | 2      |
| Immediate   | C4           | 2      |
| Absolute    | C5           | 4      |
| BC Indirect | C6           | 2      |

## Register Effects
A will contain the result.

## Flag Effects
S is set when the result is negative (i.e. bit 7 is set)
Z is set when the result is zero
Other flags unaffected

## Stack Effects
None

## Example
```
lda #$30    ; A = $30
ora #$05    ; A = $35
ldc #$80    ; C = $80
ora c       ; A = $B5, S = 1
```

# NOR, NORZ
"Not OR", "Not OR with Zero"

## Behavior
Same as [ORA](#ora-orz), but the result is inverted, so each bit of the result is set only if that bit is clear in both values.

Assemblers should support two different mnemonics for the Zero mode opcode:
```
norz
nor #0
```
NORZ (like NOR A) inverts the value in A.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Zero        | C8           | 2      |
| A Register  | C9           | 2      |
| B Register  | CA           | 2      |
| C Register  | CB           | 2      |
| Immediate   | CC           | 2      |
| Absolute    | CD           | 4      |
| BC Indirect | CE           | 2      |

## Register Effects
A will contain the result.

## Flag Effects
S is set when the result is negative (i.e. bit 7 is set)
Z is set when the result is zero
Other flags unaffected

## Stack Effects
None

## Example
```
lda #$F0    ; A = $F0
nor #$0F    ; A = $00, Z = 1
norz        ; A = $FF, S = 1
```
