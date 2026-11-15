# CLC
"CLear Carry"

## Behavior
Clears the carry flag. This is used before [ROR](ror.md) or [ROL](rol.md) to shift in a zero, or before the first [ADC](add.md#adc-adcz) or [SBC](sub.md#sbc-sbcz) of a multi-byte calculation.

## Addressing Modes
| Mode     | Opcode (hex) | Cycles |
|----------|--------------|--------|
| Implicit | FB           | 2      |

## Register Effects
None

## Flag Effects
C is cleared
Other flags unaffected

## Stack Effects
None

## Example
```
sec         ; carry = 1
clc         ; carry = 0
lda #$80
rol a       ; A = $00, Z = 1, carry = 1
```

# CLD
"CLear Decimal"

## Behavior
Clears the Decimal flag, so that all arithmetic is binary. See [SED](set.md#sed).

## Addressing Modes
| Mode     | Opcode (hex) | Cycles |
|----------|--------------|--------|
| Implicit | DF           | 2      |

## Register Effects
None

## Flag Effects
D is cleared
Other flags unaffected

## Stack Effects
None

## Example
```
sed         ; D = 1
cld         ; D = 0
lda #$19
add #$01    ; A = $1A
```

# CLI
"CLear Interrupt disable"

## Behavior
Clears the Interrupt Disable (I) flag, so that maskable interrupt requests (IRQ) are serviced. See [SEI](set.md#sei).

## Addressing Modes
| Mode     | Opcode (hex) | Cycles |
|----------|--------------|--------|
| Implicit | F1           | 2      |

## Register Effects
None

## Flag Effects
I is cleared
Other flags unaffected

## Stack Effects
None

## Example
```
sei         ; I = 1
cli         ; I = 0
```
