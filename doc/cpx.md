# CPA, CPAZ
"ComPare A", "ComPare A with Zero"

## Behavior
Compares the value in the A register with the value referenced by the operand, by subtracting the operand from A without storing the difference. Only the status flags are changed, to be tested by a following jump instruction.

* Z is set when the values are equal.
* C is set when A is greater than or equal to the operand, as unsigned values (that is, when no borrow is required). Note that this is the opposite sense from [SUB](sub.md#sub-subz), which sets carry when a borrow is required.
* S is set to bit 7 of the difference. This is the same as "A is less than the operand" only when the values are no more than 127 apart, so use C for unsigned comparisons.

Assemblers should support two different mnemonics for the Zero mode opcode:
```
cpaz
cpa #0
```
CPAZ sets S and Z from the value in A, and always sets the carry flag.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Zero        | 18           | 2      |
| A Register  | 19           | 2      |
| B Register  | 1A           | 2      |
| C Register  | 1B           | 2      |
| Immediate   | 1C           | 2      |

## Register Effects
None

## Flag Effects
S is set when bit 7 of A minus the operand is set
Z is set when A is equal to the operand
C is set when A is greater than or equal to the operand
Other flags unaffected

## Stack Effects
None

## Example
```
lda #$42    ; A = $42
cpa #$42    ; Z = 1, carry = 1
cpa #$50    ; Z = 0, carry = 0, S = 1
ldb #$10    ; B = $10
cpa b       ; Z = 0, carry = 1, S = 0
```

# CPB, CPBZ
"ComPare B", "ComPare B with Zero"

## Behavior
Same as [CPA](#cpa-cpaz), but compares the value in the B register.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Zero        | 28           | 2      |
| A Register  | 29           | 2      |
| B Register  | 2A           | 2      |
| C Register  | 2B           | 2      |
| Immediate   | 2C           | 2      |

## Example
The following code counts B up from 0 until it reaches 10.
```
ldbz        ; B = 0
loop:
inc b
cpb #10
jpnz loop   ; repeat until B == 10
stb $3000   ; ($3000) = 10
```

# CPC, CPCZ
"ComPare C", "ComPare C with Zero"

## Behavior
Same as [CPA](#cpa-cpaz), but compares the value in the C register.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Zero        | 38           | 2      |
| A Register  | 39           | 2      |
| B Register  | 3A           | 2      |
| C Register  | 3B           | 2      |
| Immediate   | 3C           | 2      |

## Example
```
ldc #$80    ; C = $80
cpc #$7F    ; carry = 1, S = 0
cpcz        ; Z = 0, S = 1, carry = 1
```
