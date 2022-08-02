# LDA, LDAZ
"LoaD A", "LoaD A with Zero"

## Behavior
Loads a value into the A register, based on the operand. Also sets the status flags based on that value.

Assemblers should support two different mnemonics for the Zero mode opcode:
```
ldaz
lda #0
```
Given an immediate operand with the value zero, the assembler should produce the Zero mode opcode, rather than the Immediate opcode followed by an explicit zero byte for an operand.

## Addressing Modes
| Mode        | Opcode (hex) |
|-------------|--------------|
| Zero        | 10           |
| A Register  | 11           |
| B Register  | 12           |
| C Register  | 13           |
| Immediate   | 14           |
| Absolute    | 15           |
| BC Indirect | 16           |
| DD Indirect | 50           |

## Register Effects
A will contain value referenced by operand. No other registers affected.

## Flag Effects
S is set when value is negative (i.e. bit 7 is set)
Z is set when value is zero
Other flags unaffected

## Stack Effects
None

## Example
The following code loads different values into A using different addressing modes. First, it loads in an immediate value of 3, then stores that value in memory at address $0102.
```
lda #3      ; A = 3
sta $0102   ; ($0102) = 3
ldb #1      ; B = 1
ldc #2      ; C = 2
lda b       ; A = 1
lda c       ; A = 2
lda (bc)    ; A = 3
ldaz        ; A = 0
lda $0102   ; A = 3
```

# LDB, LDBZ
"LoaD B", "LoaD B with Zero"

## Behavior
Loads a value into the B register, based on the operand. Works the same as [LDA/LDAZ](#lda-ldaz) for the same addressing modes.

## Addressing Modes
| Mode        | Opcode (hex) |
|-------------|--------------|
| Zero        | 20           |
| A Register  | 21           |
| B Register  | 22           |
| C Register  | 23           |
| Immediate   | 24           |
| Absolute    | 25           |
| BC Indirect | 26           |

# LDC, LDCZ
"LoaD C", "LoaD C with Zero"

## Behavior
Loads a value into the C register, based on the operand. Works the same as [LDA/LDAZ](#lda-ldaz) for the same addressing modes.

## Addressing Modes
| Mode        | Opcode (hex) |
|-------------|--------------|
| Zero        | 30           |
| A Register  | 31           |
| B Register  | 32           |
| C Register  | 33           |
| Immediate   | 34           |
| Absolute    | 35           |
| BC Indirect | 36           |

# LBCS
"Load BC with Stack pointer"

## Behavior
Loads the address in the current SP into BC, with the high byte of the stack pointer going into B and the low byte into C. This is the only way to capture the value of the stack pointer, rather than fetching data from the stack.

## Addressing Modes
| Mode     | Opcode (hex) |
|----------|--------------|
| Implicit | FB           |

## Register Effects
BC will contain the same address value as SP.

## Flag Effects
None

## Stack Effects
None - stack pointer will not change.

## Example
This code sets the stack to a known address, pushes a byte to it, then loads the new stack pointer into BC.
```
lds $1234   ; SP = 1234
pha         ; (1234) = A; SP = 1233
lbcs        ; B = 12; C = 33
```

# LDS
"LoaD Stack pointer"

## Behavior
Loads the stack pointer with a new address. If this is a change from the current stack pointer, anything pushed to the old stack is lost unless the direct address was preserved elsewhere before. This should be one of the first instructions executed after powering on the processor to get the stack into a known and inobtrusive location.

## Addressing Modes
| Mode        | Opcode (hex) |
|-------------|--------------|
| Absolute    | F7           |
| BC Register | F8           |
| BC Indirect | F9           |

## Register Effects
None

## Flag Effects
None

## Stack Effects
Stack will be moved to a new address based on the operand.

## Example
In this code, the stack is initialized to $0FFF. Then a new address ($1234) is pushed onto the stack, moving the stack pointer to $0FFD. This new stack pointer is loaded into BC for preservation. BC is incremented, and then the address that was pushed ($1234) is made into the new stack pointer by fetching it from the address in BC. Then the old stack location is restored by decrementing BC and loading that value back into the stack pointer. Clearing that address from the stack makes it empty again and brings the stack pointer back to $0FFF again.
```
lds $0FFF   ; SP = $0FFF
lda #$12    ; A = $12
pha         ; SP = $0FFE, ($0FFF) = $12
lda #$34    ; A = $34
pha         ; SP = $0FFD, ($0FFE) = $34
lbcs        ; BC = $0FFD
inc bc      ; BC = $0FFE
lds (bc)    ; SP = $1234
dec bc      ; BC = $0FFD
lds bc      ; SP = $0FFD
pla         ; SP = $0FFE
pla         ; SP = $0FFF
```
