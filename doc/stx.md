# STA
"STore A"

## Behavior
Stores the value in the A register in memory, at the address specified in the operand.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Absolute    | 1D           | 4      |
| BC Indirect | 1E           | 2      |
| DD Indirect | 58           | 2      |

## Register Effects
None

## Flag Effects
None

## Stack Effects
None

## Example
The following code stores the value in A to two different addresses: $1234 and $ABCD. Both addressing modes are used.

```
lda #42     ; A = 42
sta $1234   ; ($1234) = 42
ldb #$AB
ldc #$CD
sta (bc)    ; ($ABCD) = 42
```

# STB
"STore B"

## Behavior
Same as STA, but stores the value in the B register. The BC Indirect addressing mode means that the value in B will also be the memory page written to. Because of this limitation, the Absolute mode is the only widely practical mode.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Absolute    | 2D           | 4      |
| BC Indirect | 2E           | 2      |

## Example
The following code stores the value in B to two different addresses: $1234 and $ABCD. Both addressing modes are used.

```
ldb #$12    ; B = $12
ldc #$34
stb (bc)    ; ($1234) = $12
stb $ABCD   ; ($ABCD) = $12
```

# STC
"STore C"

## Behavior
Same as STA, but stores the value in the C register. The BC Indirect addressing mode means that the value in C will also be the low byte of the memory address written to. Because of this limitation, the Absolute mode is the only widely practical mode.

## Addressing Modes
| Mode        | Opcode (hex) | Cycles |
|-------------|--------------|--------|
| Absolute    | 3D           | 4      |
| BC Indirect | 3E           | 2      |

## Example
The following code stores the value in C to two different addresses: $1234 and $ABCD. Both addressing modes are used.

```
ldb #$12
ldc #$34    ; C = $34
stc (bc)    ; ($1234) = $34
stc $ABCD   ; ($ABCD) = $34
```
