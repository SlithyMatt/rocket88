# EXD
"EXchange with DD"

## Behavior
Exchanges the 16-bit values in the BC and DD registers. This gives fast access to a second pointer or counter without having to save BC to memory. Also sets the Zero flag based on the new value in BC.

## Addressing Modes
| Mode     | Opcode (hex) | Cycles |
|----------|--------------|--------|
| Implicit | 40           | 2      |

## Register Effects
BC will contain the previous value of DD, and DD will contain the previous value of BC.

## Flag Effects
Z is set when the new value of BC is zero
Other flags unaffected

## Stack Effects
None

## Example
```
ldb #$12
ldc #$34    ; BC = $1234
exd         ; DD = $1234
ldb #$56
ldc #$78    ; BC = $5678
exd         ; BC = $1234, DD = $5678, Z = 0
```

# EXE
"EXchange with EE"

## Behavior
Same as [EXD](#exd), but exchanges the values in the BC and EE registers.

## Addressing Modes
| Mode     | Opcode (hex) | Cycles |
|----------|--------------|--------|
| Implicit | 48           | 2      |

## Register Effects
BC will contain the previous value of EE, and EE will contain the previous value of BC.

## Flag Effects
Z is set when the new value of BC is zero
Other flags unaffected

## Example
The following code keeps both a pointer and a loop counter in BC, swapping between them with EE. It stores $AA in 3 bytes, starting at $3000.
```
ldb #$30
ldcz        ; BC = $3000
exe         ; EE = $3000 (pointer)
ldbz
ldc #3      ; BC = 3 (counter)
lda #$AA
loop:
exe         ; BC = pointer, EE = counter
sta (bc)    ; store $AA at the pointer
inc bc      ; move the pointer
exe         ; BC = counter, EE = pointer
dec bc      ; count down, Z = 1 when the counter reaches 0
jpnz loop
exe         ; BC = $3003, ($3002) = $AA, ($3003) = $00
```
