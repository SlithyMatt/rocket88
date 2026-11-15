# ADD, ADDZ
"ADD", "ADD Zero"

## Behavior
Adds the value referenced by the operand to the A register, and stores the sum in A. The carry flag is set if the sum doesn't fit in a byte, and cleared otherwise. The previous value of the carry flag is not added; use [ADC](#adc-adcz) for that.

If the Decimal flag is set (see [SED](set.md#sed)), both values are treated as binary-coded decimal (BCD), the sum is BCD, and the carry flag is set if the sum is over 99.

Assemblers should support two different mnemonics for the Zero mode opcode:
```
addz
add #0
```
Adding zero leaves A unchanged, but it does set S and Z from the value in A and clears the carry flag, so ADDZ is a quick way to do both.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Zero        | 80           | 2      |
| A Register  | 81           | 2      |
| B Register  | 82           | 2      |
| C Register  | 83           | 2      |
| Immediate   | 84           | 2      |
| Absolute    | 85           | 4      |
| BC Indirect | 86           | 2      |

## Register Effects
A will contain the sum.

## Flag Effects
S is set when the sum is negative (i.e. bit 7 is set)
Z is set when the sum is zero
C is set when the sum is over 255 (or over 99 in decimal mode)
Other flags unaffected

## Stack Effects
None

## Example
```
lda #$70    ; A = $70
add #$20    ; A = $90, S = 1, carry = 0
ldb #$80    ; B = $80
add b       ; A = $10, S = 0, carry = 1
sed         ; decimal mode
lda #$45
add #$38    ; A = $83, carry = 0
add #$20    ; A = $03, carry = 1
cld
```

# ADC, ADCZ
"ADd with Carry", "ADd Carry"

## Behavior
Same as [ADD](#add-addz), but also adds the carry flag (0 or 1) to the sum. This allows values of more than 8 bits to be added one byte at a time: add the low bytes with ADD, then the next bytes with ADC, which adds in the carry from the bytes before.

Assemblers should support two different mnemonics for the Zero mode opcode:
```
adcz
adc #0
```
ADCZ adds just the carry flag to A, which is useful to carry into the high byte of a multi-byte value.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Zero        | 88           | 2      |
| A Register  | 89           | 2      |
| B Register  | 8A           | 2      |
| C Register  | 8B           | 2      |
| Immediate   | 8C           | 2      |
| Absolute    | 8D           | 4      |
| BC Indirect | 8E           | 2      |

## Register Effects
A will contain the sum.

## Flag Effects
S is set when the sum is negative (i.e. bit 7 is set)
Z is set when the sum is zero
C is set when the sum is over 255 (or over 99 in decimal mode)
Other flags unaffected

## Stack Effects
None

## Example
The following code adds $12F0 and $0120, storing the 16-bit sum ($1410) at $3000 (low byte) and $3001 (high byte).
```
lda #$F0    ; low byte of $12F0
add #$20    ; A = $10, carry = 1
sta $3000   ; ($3000) = $10
lda #$12    ; high byte of $12F0
adc #$01    ; A = $14, carry = 0
sta $3001   ; ($3001) = $14
```
