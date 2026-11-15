# NEG
"NEGate"

## Behavior
Negates the value in the A register, replacing it with its two's complement (zero minus A). Negation is always binary, even when the Decimal flag is set.

Since the result is zero minus A, the carry flag is set when a borrow is required, which is whenever A was not zero. Negating $80 (-128) results in $80 again, as +128 can't be represented in a signed byte.

## Addressing Modes
| Mode       | Opcode (hex) | Cycles |
|------------|--------------|--------|
| A Register | B7           | 2      |

## Register Effects
A will contain the negated value.

## Flag Effects
S is set when the new value is negative (i.e. bit 7 is set)
Z is set when the new value is zero
C is set when A was not zero
Other flags unaffected

## Stack Effects
None

## Example
```
lda #$01    ; A = $01
neg         ; A = $FF, S = 1, carry = 1
neg         ; A = $01, S = 0
ldaz
neg         ; A = $00, Z = 1, carry = 0
```
