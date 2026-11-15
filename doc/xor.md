# XOR, XORZ
"eXclusive OR", "eXclusive OR with Zero"

## Behavior
Performs a bitwise exclusive OR of the A register and the value referenced by the operand, and stores the result in A. Each bit of the result is set if that bit is set in one value but not both, so XOR is typically used to flip bits.

Assemblers should support two different mnemonics for the Zero mode opcode:
```
xorz
xor #0
```
XORZ leaves A unchanged, but sets S and Z from the value in A. XOR A always results in zero.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Zero        | E0           | 2      |
| A Register  | E1           | 2      |
| B Register  | E2           | 2      |
| C Register  | E3           | 2      |
| Immediate   | E4           | 2      |
| Absolute    | E5           | 4      |
| BC Indirect | E6           | 2      |

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
lda #$FF    ; A = $FF
xor #$0F    ; A = $F0, S = 1
xor a       ; A = $00, Z = 1
```

# XNR, XNRZ
"eXclusive Not oR", "eXclusive Not oR with Zero"

## Behavior
Same as [XOR](#xor-xorz), but the result is inverted, so each bit of the result is set if that bit is the same in both values.

Assemblers should support two different mnemonics for the Zero mode opcode:
```
xnrz
xnr #0
```
XNRZ inverts the value in A. XNR A always results in $FF.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Zero        | E8           | 2      |
| A Register  | E9           | 2      |
| B Register  | EA           | 2      |
| C Register  | EB           | 2      |
| Immediate   | EC           | 2      |
| Absolute    | ED           | 4      |
| BC Indirect | EE           | 2      |

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
xnr #$0F    ; A = $00, Z = 1
xnr a       ; A = $FF, S = 1
```
