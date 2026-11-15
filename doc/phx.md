# PHA
"PusH A"

## Behavior
Pushes the value in the A register onto the stack. The stack pointer is first decremented, and then the value is written to memory at the new stack pointer, so SP always points to the last byte pushed.

## Addressing Modes
| Mode    | Opcode (hex) | Cycles |
|---------|--------------|--------|
| Stack   | 1F           | 3      |

## Register Effects
SP is decremented. No other registers affected.

## Flag Effects
None

## Stack Effects
The value in A is pushed onto the stack.

## Example
```
lds $1000   ; SP = $1000
lda #$12    ; A = $12
pha         ; SP = $0FFF, ($0FFF) = $12
```

# PHB
"PusH B"

## Behavior
Same as [PHA](#pha), but pushes the value in the B register.

## Addressing Modes
| Mode    | Opcode (hex) | Cycles |
|---------|--------------|--------|
| Stack   | 2F           | 3      |

## Example
```
lds $1000   ; SP = $1000
ldb #$34    ; B = $34
phb         ; SP = $0FFF, ($0FFF) = $34
```

# PHC
"PusH C"

## Behavior
Same as [PHA](#pha), but pushes the value in the C register.

## Addressing Modes
| Mode    | Opcode (hex) | Cycles |
|---------|--------------|--------|
| Stack   | 3F           | 3      |

## Example
The following code saves BC on the stack while it is used for something else, then restores it.
```
lds $1000   ; SP = $1000
ldb #$12
ldc #$34    ; BC = $1234
phb         ; SP = $0FFF
phc         ; SP = $0FFE
ldbz
ldcz        ; BC = $0000
plc         ; C = $34
plb         ; BC = $1234, SP = $1000
```

# PHP
"PusH P"

## Behavior
Pushes the processor status register (P) onto the stack, in the same way as [PHA](#pha). The flags are arranged in the byte as follows, with bits 1 and 0 always pushed as zero.

| Bit:   | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|--------|---|---|---|---|---|---|---|---|
| Flag:  | S | Z | C | I | D | K | 0 | 0 |

## Addressing Modes
| Mode    | Opcode (hex) | Cycles |
|---------|--------------|--------|
| Stack   | E7           | 3      |

## Register Effects
SP is decremented. No other registers affected.

## Flag Effects
None

## Stack Effects
P is pushed onto the stack.

## Example
```
lds $1000   ; SP = $1000
lda #$80    ; S = 1, Z = 0
sec         ; carry = 1
php         ; SP = $0FFF, ($0FFF) = $A0
```
