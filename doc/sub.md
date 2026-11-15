# SUB, SUBZ
"SUBtract", "SUBtract Zero"

## Behavior
Subtracts the value referenced by the operand from the A register, and stores the difference in A. The carry flag is set if a borrow was required (the operand was greater than A), and cleared otherwise. The previous value of the carry flag is not subtracted; use [SBC](#sbc-sbcz) for that.

Note that this is the opposite sense from the compare instructions ([CPA](cpx.md#cpa-cpaz), etc.), which set the carry flag when no borrow is required.

If the Decimal flag is set (see [SED](set.md#sed)), both values are treated as binary-coded decimal (BCD), and the difference is BCD. A negative difference wraps around from 100, with the carry flag set to show the borrow.

Assemblers should support two different mnemonics for the Zero mode opcode:
```
subz
sub #0
```
SUBZ has the same effect as [ADDZ](add.md#add-addz): A is unchanged, S and Z are set from A, and the carry flag is cleared.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Zero        | 90           | 2      |
| A Register  | 91           | 2      |
| B Register  | 92           | 2      |
| C Register  | 93           | 2      |
| Immediate   | 94           | 2      |
| Absolute    | 95           | 4      |
| BC Indirect | 96           | 2      |

## Register Effects
A will contain the difference.

## Flag Effects
S is set when the difference is negative (i.e. bit 7 is set)
Z is set when the difference is zero
C is set when a borrow was required
Other flags unaffected

## Stack Effects
None

## Example
```
lda #$50    ; A = $50
sub #$20    ; A = $30, carry = 0
sub #$40    ; A = $F0, S = 1, carry = 1
sub a       ; A = $00, Z = 1, carry = 0
sed         ; decimal mode
lda #$42
sub #$15    ; A = $27, carry = 0
sub #$30    ; A = $97, carry = 1
cld
```

# SBC, SBCZ
"SuBtract with Carry", "SuBtract Carry"

## Behavior
Same as [SUB](#sub-subz), but also subtracts the carry flag (0 or 1) from the difference, treating it as a borrow from a previous subtraction. This allows values of more than 8 bits to be subtracted one byte at a time: subtract the low bytes with SUB, then the next bytes with SBC.

Assemblers should support two different mnemonics for the Zero mode opcode:
```
sbcz
sbc #0
```
SBCZ subtracts just the carry flag from A. SBC A results in 0 if the carry flag is clear, or $FF if it is set, and leaves the carry flag unchanged.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Zero        | 98           | 2      |
| A Register  | 99           | 2      |
| B Register  | 9A           | 2      |
| C Register  | 9B           | 2      |
| Immediate   | 9C           | 2      |
| Absolute    | 9D           | 4      |
| BC Indirect | 9E           | 2      |

## Register Effects
A will contain the difference.

## Flag Effects
S is set when the difference is negative (i.e. bit 7 is set)
Z is set when the difference is zero
C is set when a borrow was required
Other flags unaffected

## Stack Effects
None

## Example
The following code subtracts $0120 from $1410, storing the 16-bit difference ($12F0) at $3000 (low byte) and $3001 (high byte).
```
lda #$10    ; low byte of $1410
sub #$20    ; A = $F0, carry = 1
sta $3000   ; ($3000) = $F0
lda #$14    ; high byte of $1410
sbc #$01    ; A = $12, carry = 0
sta $3001   ; ($3001) = $12
```
