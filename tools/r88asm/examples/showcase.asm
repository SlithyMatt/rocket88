; showcase.asm - a tour of the ROCKET88 instruction set
;
; A ROM image that runs a series of small tasks, each using a different group
; of instructions and addressing modes, and stores the results in RAM at
; RESULTS ($0300). It finishes by writing $AA to R_DONE and halting.
; Every documented instruction is used except RST, which would restart it.
;
; Assemble with:   r88asm -l showcase.lst showcase.asm
; The listing shows each macro use (ADD16, FILL) followed by its expansion.
; The test suite (make test) runs it on the Verilog core and checks every result.

; ---------------------------------------------------------------------------
; Memory map
; ---------------------------------------------------------------------------
STACK_TOP   = $0400         ; the stack grows down from $03FF
RESULTS     = $0300         ; results, cleared at startup
RESULTS_LEN = 48
BUFFER      = $0340         ; string copy destination
MCAND       = $0280         ; multiply: 16-bit multiplicand (2 bytes)
ALT_STACK   = $0200         ; a second stack, growing down from $01FF

; Result locations
R_LENGTH    = RESULTS+0     ; length of the copied string
R_SUM       = RESULTS+1     ; 16-bit sum (2 bytes, low first)
R_DIFF      = RESULTS+3     ; 16-bit difference (2 bytes)
R_SCORE     = RESULTS+5     ; BCD score (2 bytes)
R_PRODUCT   = RESULTS+7     ; 8x8 bit product (2 bytes)
R_MAX       = RESULTS+9     ; largest value in the table
R_MIN       = RESULTS+10    ; smallest value in the table
R_BITS      = RESULTS+11    ; logic results (7 bytes)
R_BRKS      = RESULTS+18    ; number of BRKs counted by the IRQ handler
R_DISPATCH  = RESULTS+19    ; written by the jump table handlers (3 bytes)
R_STACK     = RESULTS+22    ; stack checks (5 bytes)
R_SHIFT     = RESULTS+27    ; 16-bit shift results (4 bytes)
R_COUNT     = RESULTS+31    ; sign-controlled loop count
R_DONE      = RESULTS+32    ; $AA when all tasks are done
R_BRK_OK    = RESULTS+33    ; $B0 if the BRK count was checked
R_ZERO      = RESULTS+34    ; Zero mode results (4 bytes)
R_CALLS     = RESULTS+38    ; number of conditional calls taken
R_SUM2      = RESULTS+39    ; 16-bit sum of expressions (2 bytes)

; Inputs
NUM1        = $12F0
NUM2        = $0F25
MULT_A      = $B7
MULT_B      = $5D

; ---------------------------------------------------------------------------
; Macros
; ---------------------------------------------------------------------------

; dest = x + y, for 16-bit values known when assembling.
; Arguments can be expressions: ADD16 R_SUM2, NUM1*2, NUM2-$25
.macro ADD16 dest, x, y
    lda #x.low
    add #y.low              ; carry out of the low byte...
    sta dest
    lda #x.high
    adc #y.high             ; ...into the high byte
    sta dest+1
.endmacro

; Store count bytes (1-256) of value, starting at address start.
; @loop is a local label, so FILL can be used more than once.
.macro FILL start, count, value
    ldb #start.high
    ldc #start.low
    exd                     ; DD = pointer
    ldb #count
    lda #value
@loop:
    sta (dd)
    inc dd
    dec b
    jpnz @loop
.endmacro

; ---------------------------------------------------------------------------
; Startup
; ---------------------------------------------------------------------------
    .org $F000
reset:
    sei                     ; no IRQs until we're ready
    lds STACK_TOP           ; LDS NN
    cld                     ; binary arithmetic

    ; Clear the results area
    ldb #RESULTS.high
    ldc #RESULTS.low        ; assembles to LDCZ, since the low byte is 0
    ldaz
clear:
    sta (bc)                ; STA (BC)
    inc c                   ; INC C
    cpc #RESULTS_LEN        ; CPC #N
    jpnz clear              ; JPNZ: loop until C reaches the end

; ---------------------------------------------------------------------------
; Task 1: copy a zero-terminated string with two pointers, and measure it
; ---------------------------------------------------------------------------
    FILL BUFFER, 24, '*'    ; the copy overwrites the start of this
    FILL BUFFER+32, 4, $E5
    ldb #BUFFER.high
    ldc #BUFFER.low
    exd                     ; DD = destination
    ldb #message.high
    ldc #message.low        ; BC = source
copy:
    lda (bc)                ; LDA (BC), sets Z at the terminator
    sta (dd)                ; STA (DD)
    jmpz copied             ; JMPZ NN
    inc bc                  ; INC BC
    inc dd                  ; INC DD
    jmpr copy               ; JMPR
copied:
    lda c                   ; LDA C: low byte of the pointer to the terminator
    sub #message.low        ; SUB #N
    sta R_LENGTH            ; STA NN

; ---------------------------------------------------------------------------
; Task 2: 16-bit addition and subtraction
; ---------------------------------------------------------------------------
    ADD16 R_SUM, NUM1, NUM2         ; ADD #N and ADC #N, in a macro
    ADD16 R_SUM2, NUM1*2, NUM2-$25  ; expressions as arguments

    lda num_a               ; LDA NN
    sub num_b               ; SUB NN, borrow out of the low byte
    sta R_DIFF
    lda num_a+1
    sbc num_b+1             ; SBC NN, borrow into the high byte
    sta R_DIFF+1

; ---------------------------------------------------------------------------
; Task 3: BCD arithmetic: 0995 + 27 = 1022
; ---------------------------------------------------------------------------
    sed                     ; SED
    lda #$95
    add #$27                ; $95 + $27 = $22, carry
    sta R_SCORE
    lda #$09
    adcz                    ; ADCZ: $09 + carry = $10
    sta R_SCORE+1
    cld                     ; CLD

; ---------------------------------------------------------------------------
; Task 4: 8x8 bit multiply in a subroutine
; ---------------------------------------------------------------------------
    lda #MULT_A
    ldb #MULT_B
    jsr multiply            ; JSR NN

; ---------------------------------------------------------------------------
; Task 5: largest and smallest values in a table
; ---------------------------------------------------------------------------
    ldbz
    ldc #TABLE_LEN-1
    exe                     ; EXE: EE = number of values left to check
    ldb #table.high
    ldc #table.low
    exd                     ; EXD: DD = pointer into the table
    lda (dd)                ; LDA (DD): first value
    ldb a                   ; LDB A: B = largest so far
    ldc a                   ; LDC A: C = smallest so far
scan:
    inc dd
    lda (dd)
    cpa b                   ; CPA B: carry set if A >= B
    jpnc not_max            ; JPNC: skip if A < B
    ldb a
not_max:
    cpa c                   ; CPA C
    jmpc not_min            ; JMPC NN: skip if A >= C
    ldc a
not_min:
    dec ee                  ; DEC EE, Z set when it reaches 0
    jpnz scan
    stb R_MAX               ; STB NN
    stc R_MIN               ; STC NN

; ---------------------------------------------------------------------------
; Task 6: logic
; ---------------------------------------------------------------------------
    lda #%11001010
    and #%11110000          ; AND #N: $C0
    sta R_BITS
    ora #%00000101          ; ORA #N: $C5
    sta R_BITS+1
    xor #$FF                ; XOR #N: $3A
    sta R_BITS+2
    ldb #$0F
    nnd b                   ; NND B: ~($3A & $0F) = $F5
    sta R_BITS+3
    inv b                   ; INV B: B = $F0
    nor b                   ; NOR B: ~($F5 | $F0) = $0A
    sta R_BITS+4
    neg                     ; NEG: -$0A = $F6
    sta R_BITS+5
    ldc #$5A
    inv c                   ; INV C: C = $A5
    xnr c                   ; XNR C: ~($F6 ^ $A5) = $AC
    sta R_BITS+6

; ---------------------------------------------------------------------------
; Task 7: the stack
; ---------------------------------------------------------------------------
    lda #$C3
    ldb #$3C
    ldc #$5A
    pha                     ; PHA
    phb                     ; PHB
    phc                     ; PHC
    sec                     ; SEC
    php                     ; PHP: save carry = 1
    clc                     ; CLC
    ldaz
    ldbz
    ldcz
    plp                     ; PLP: carry = 1 again
    plc                     ; PLC
    plb                     ; PLB
    pla                     ; PLA: A = $C3
    sta R_STACK
    adcz                    ; A = $C3 + carry = $C4
    sta R_STACK+1

    lbcs                    ; LBCS: BC = SP, back at STACK_TOP
    stb R_STACK+2
    stc R_STACK+3

    ; Switch to a second stack and back again
    exd                     ; DD = saved stack pointer
    lds ALT_STACK           ; LDS NN
    ldb #alt_stack_ptr.high
    ldc #alt_stack_ptr.low
    lds (bc)                ; LDS (BC): the same address again, read from memory
    lda #$EE
    pha                     ; pushed on the second stack
    exd                     ; BC = saved stack pointer
    lds bc                  ; LDS BC: back to the main stack

; ---------------------------------------------------------------------------
; Task 8: BRK, counted by the IRQ handler
; ---------------------------------------------------------------------------
    lda #$77
    brk                     ; BRK: the handler counts it
    brk
    sta R_STACK+4           ; A survives the handler ($77)
    lda R_BRKS
    cpa #2
    jsrz brk_ok             ; JSRZ NN: called because both BRKs were counted

; ---------------------------------------------------------------------------
; Task 9: a jump table, used with JSR (BC) and JMP (BC)
; ---------------------------------------------------------------------------
    ldb #handlers.high
    ldc #handlers.low
    jsr (bc)                ; JSR (BC): handler_0
    inc bc
    inc bc
    jsr (bc)                ; handler_1
    inc bc
    inc bc
    jmp (bc)                ; JMP (BC): handler_2, which jumps back
dispatched:

; ---------------------------------------------------------------------------
; Task 10: 16-bit shifts of BC in local subroutines
; ---------------------------------------------------------------------------
    ldb #$01
    ldc #$81                ; BC = $0181
    jsrr shift_left_bc      ; JSRR: BC = $0302
    stb R_SHIFT
    stc R_SHIFT+1
    jsrr shift_right_bc     ; BC = $0181
    stb R_SHIFT+2
    stc R_SHIFT+3
    jmpr shifted

shift_left_bc:
    asl c                   ; ASL C: high bit into carry
    rol b                   ; ROL B: carry into the low bit
    rts                     ; RTS

shift_right_bc:
    lsr b                   ; LSR B: low bit into carry
    ror c                   ; ROR C: carry into the high bit
    rts
shifted:

; ---------------------------------------------------------------------------
; Task 11: a loop controlled by the sign flag
; ---------------------------------------------------------------------------
    lda #3
    ldbz
down:
    inc b                   ; INC B
    dec a                   ; DEC A
    jmpp down               ; JMPP: repeat while A is not negative (3, 2, 1, 0)
    stb R_COUNT             ; 4
    jmpn counted            ; JMPN NN: A is $FF, so this is taken
    stb R_DONE              ; skipped
counted:

; ---------------------------------------------------------------------------
; Task 12: Zero mode forms, and conditional subroutine calls
; ---------------------------------------------------------------------------
    lda #$5A
    orz                     ; ORZ: A unchanged, sets S and Z
    xorz                    ; XORZ: A unchanged
    addz                    ; ADDZ: A unchanged, clears carry
    subz                    ; SUBZ: A unchanged
    sta R_ZERO              ; $5A
    xnrz                    ; XNRZ: inverts A, $A5
    sta R_ZERO+1
    norz                    ; NORZ: inverts A, $5A
    nndz                    ; NNDZ: always $FF
    sta R_ZERO+2
    sec
    sbcz                    ; SBCZ: $FF - carry = $FE
    sta R_ZERO+3
    andz                    ; ANDZ: always 0

    ; EE counts the calls to tally
    ldbz
    ldcz
    exe                     ; EE = 0
    cpaz                    ; CPAZ: A is 0, so Z = 1
    jsnz tally              ; JSNZ: not called, Z is set
    ldb #1
    cpbz                    ; CPBZ: Z = 0
    jsnz tally              ; called (1)
    cpb #2                  ; CPB #N: carry = 0, since B < 2
    jsnc tally              ; JSNC: called (2)
    cpb a                   ; CPB A: carry = 1, since B >= A (0)
    jsrc tally              ; JSRC NN: called (3)
    lda #$80                ; S = 1
    jsrp tally              ; JSRP: not called, S is set
    jsrn tally              ; JSRN NN: called (4)
    nop                     ; NOP
    exe                     ; BC = call count
    stc R_CALLS             ; 4
    jmpr calls_done

tally:
    inc ee                  ; INC EE
    rts
calls_done:

; ---------------------------------------------------------------------------
; Done: mark it and wait for interrupts
; ---------------------------------------------------------------------------
finish:
    lda #$AA
    sta R_DONE
    cli                     ; CLI
done:
    hlt                     ; HLT
    jmpr done

; ---------------------------------------------------------------------------
; Subroutines
; ---------------------------------------------------------------------------

; Multiply A by B, by shifting and adding; the product goes to R_PRODUCT.
multiply:
    sta MCAND               ; multiplicand, extended to 16 bits
    ldaz
    sta MCAND+1
    sta R_PRODUCT
    sta R_PRODUCT+1
    ldc b                   ; LDC B: C = multiplier
mloop:
    cpcz                    ; CPCZ: done when no multiplier bits are left
    jmpz mdone
    lsr c                   ; next multiplier bit into carry
    jpnc mskip              ; bit was 0: don't add
    lda R_PRODUCT
    add MCAND               ; ADD NN
    sta R_PRODUCT
    lda R_PRODUCT+1
    adc MCAND+1             ; ADC NN
    sta R_PRODUCT+1
mskip:
    asl MCAND               ; ASL NN: double the multiplicand
    rol MCAND+1             ; ROL NN
    jmpr mloop
mdone:
    rts

brk_ok:
    lda #$B0
    sta R_BRK_OK
    rts

handler_0:
    lda #$11
    sta R_DISPATCH
    rts

handler_1:
    lda #$22
    sta R_DISPATCH+1
    rts

handler_2:
    lda #$33
    sta R_DISPATCH+2
    jmp dispatched          ; JMP NN

; ---------------------------------------------------------------------------
; Interrupt handlers
; ---------------------------------------------------------------------------

; IRQ / BRK: count BRKs, identified by the K bit in the P pushed on the stack
irq:
    lbcs                    ; BC = SP
    inc bc
    inc bc
    inc bc                  ; P is 3 bytes above SP (above C, B and A)
    lda (bc)
    and #%00000100          ; K bit
    jmpz irq_done           ; not a BRK
    ldb #R_BRKS.high
    ldc #R_BRKS.low
    inc (bc)                ; INC (BC)
irq_done:
    rti                     ; RTI: restores A, B, C, P and PC

nmi:
    rti

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
message:
    .byte "HELLO, ROCKET88!", 0

num_a:
    .word $1234
num_b:
    .word $0567

table:
    .byte 23, 200, 7, 99, 150, 64
table_end:
TABLE_LEN = table_end - table

handlers:
    .addr handler_0, handler_1, handler_2

alt_stack_ptr:
    .addr ALT_STACK

; ---------------------------------------------------------------------------
; Vectors
; ---------------------------------------------------------------------------
    .org $FFFA
    .addr irq
    .addr nmi
    .addr reset
