# SEC
"SEt Carry"

## Behavior
Sets the carry flag. This is used before [ROR](ror.md) or [ROL](rol.md) to shift in a one, before [SBC](sub.md#sbc-sbcz) to subtract an extra one, or before [ADC](add.md#adc-adcz) to add an extra one.

## Addressing Modes
| Mode     | Opcode (hex) | Cycles |
|----------|--------------|--------|
| Implicit | FC           | 2      |

## Register Effects
None

## Flag Effects
C is set
Other flags unaffected

## Stack Effects
None

## Example
```
sec         ; carry = 1
lda #$10
adc #$01    ; A = $12, carry = 0
```

# SED
"SEt Decimal"

## Behavior
Sets the Decimal flag, so that [ADD](add.md#add-addz), [ADC](add.md#adc-adcz), [SUB](sub.md#sub-subz) and [SBC](sub.md#sbc-sbcz) treat their values as binary-coded decimal (BCD). Other instructions, including increments, decrements and compares, are always binary. Use [CLD](clx.md#cld) to return to binary arithmetic.

## Addressing Modes
| Mode     | Opcode (hex) | Cycles |
|----------|--------------|--------|
| Implicit | D7           | 2      |

## Register Effects
None

## Flag Effects
D is set
Other flags unaffected

## Stack Effects
None

## Example
```
sed         ; D = 1
lda #$19
add #$01    ; A = $20
cld         ; D = 0
```

# SEI
"SEt Interrupt disable"

## Behavior
Sets the Interrupt Disable (I) flag, so that maskable interrupt requests (IRQ) are ignored. This does not affect NMI or RESET. Use [CLI](clx.md#cli) to allow IRQs again.

The I flag is also set automatically when an IRQ, NMI or [BRK](brk.md) is serviced, and [RTI](ret.md#rti) restores its previous value.

## Addressing Modes
| Mode     | Opcode (hex) | Cycles |
|----------|--------------|--------|
| Implicit | F0           | 2      |

## Register Effects
None

## Flag Effects
I is set
Other flags unaffected

## Stack Effects
None

## Example
```
sei         ; I = 1
cli         ; I = 0
```
