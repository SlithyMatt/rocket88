# AND, ANDZ
"AND", "AND with Zero"

## Behavior
Performs a bitwise AND of the A register and the value referenced by the operand, and stores the result in A. Each bit of the result is set only if that bit is set in both values, so AND is typically used to clear bits, keeping only the ones set in a mask.

Assemblers should support two different mnemonics for the Zero mode opcode:
```
andz
and #0
```
ANDZ always results in zero.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Zero        | D0           | 2      |
| A Register  | D1           | 2      |
| B Register  | D2           | 2      |
| C Register  | D3           | 2      |
| Immediate   | D4           | 2      |
| Absolute    | D5           | 4      |
| BC Indirect | D6           | 2      |

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
lda #$F5    ; A = $F5
and #$0F    ; A = $05, S = 0
ldb #$04    ; B = $04
and b       ; A = $04, Z = 0
andz        ; A = $00, Z = 1
```

# NND, NNDZ
"Not AND", "Not AND with Zero"

## Behavior
Same as [AND](#and-andz), but the result is inverted, so each bit of the result is clear only if that bit is set in both values.

Assemblers should support two different mnemonics for the Zero mode opcode:
```
nndz
nnd #0
```
NNDZ always results in $FF. NND A inverts the value in A.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Zero        | D8           | 2      |
| A Register  | D9           | 2      |
| B Register  | DA           | 2      |
| C Register  | DB           | 2      |
| Immediate   | DC           | 2      |
| Absolute    | DD           | 4      |
| BC Indirect | DE           | 2      |

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
nnd #$3C    ; A = $CF, S = 1
nnd a       ; A = $30, S = 0
nndz        ; A = $FF
```
