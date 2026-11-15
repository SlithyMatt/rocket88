# PLA
"PulL A"

## Behavior
Pulls a value from the stack into the A register. The value is read from memory at the stack pointer, and then the stack pointer is incremented. Also sets the status flags based on that value.

## Addressing Modes
| Mode    | Opcode (hex) | Cycles |
|---------|--------------|--------|
| Stack   | 17           | 3      |

## Register Effects
A will contain the value pulled from the stack. SP is incremented.

## Flag Effects
S is set when value is negative (i.e. bit 7 is set)
Z is set when value is zero
Other flags unaffected

## Stack Effects
One byte is pulled from the stack.

## Example
```
lds $1000   ; SP = $1000
lda #$5A    ; A = $5A
pha         ; SP = $0FFF
ldaz        ; A = $00
pla         ; A = $5A, SP = $1000
```

# PLB
"PulL B"

## Behavior
Same as [PLA](#pla), but pulls the value into the B register.

## Addressing Modes
| Mode    | Opcode (hex) | Cycles |
|---------|--------------|--------|
| Stack   | 27           | 3      |

## Example
The following code copies A to B through the stack.
```
lds $1000   ; SP = $1000
lda #$80    ; A = $80
pha
plb         ; B = $80, S = 1, SP = $1000
```

# PLC
"PulL C"

## Behavior
Same as [PLA](#pla), but pulls the value into the C register.

## Addressing Modes
| Mode    | Opcode (hex) | Cycles |
|---------|--------------|--------|
| Stack   | 37           | 3      |

## Example
```
lds $1000   ; SP = $1000
ldaz        ; A = $00
pha
ldc #$FF    ; C = $FF
plc         ; C = $00, Z = 1
```

# PLP
"PulL P"

## Behavior
Pulls a value from the stack into the processor status register (P), in the same way as [PLA](#pla). Every flag is replaced by the matching bit of the value pulled (see [PHP](phx.md#php) for the layout), including the Break (K) flag. As with any other instruction, K is cleared again when the next instruction is fetched.

## Addressing Modes
| Mode    | Opcode (hex) | Cycles |
|---------|--------------|--------|
| Stack   | EF           | 3      |

## Register Effects
SP is incremented.

## Flag Effects
All flags are loaded from the value pulled from the stack.

## Stack Effects
One byte is pulled from the stack.

## Example
```
lds $1000   ; SP = $1000
lda #$28    ; C and D bits of P
pha
plp         ; carry = 1, D = 1, SP = $1000
cld
```
