; smoke_test.asm - first test of a newly programmed board
;
; Shows color bars on the VGA output, and plays a 440 Hz tone each time a key
; is pressed on the PS/2 keyboard. It runs entirely on the FPGA (the stack
; and variables are in the boot RAM), so it works even if the SDRAM doesn't.
;
; What you should see and hear:
;   - Eight vertical bars: white, yellow, cyan, green, magenta, red, blue,
;     black, with a title in white on black at the bottom
;   - LED4 blinks about once a second (the CPU and video are running)
;   - Each key press plays a short beep and lights LED1 while it plays
;   - The 4-digit display reads 0000 at first, then shows the last key's
;     scan code in decimal (for example 0028 for A, whose scan code is $1C)
;
; To run it, build it into the boot RAM image and recompile in Quartus:
;   python3 tools/build_system_roms.py verilog/system/examples/smoke_test.asm
; and run the script with no argument to go back to the normal boot program.

; ---------------------------------------------------------------------------
; Hardware
; ---------------------------------------------------------------------------
TEXT        = $E000
COLOR       = $E400
VID_MODE    = $FE00
VID_BORDER  = $FE01
KBD_DATA    = $FE10
KBD_STATUS  = $FE11         ; bit 0: data ready
V0_FREQ     = $FE20
V0_VOL      = $FE22
V0_WAVE     = $FE23
IRQ_STATUS  = $FE30         ; bit 0: frame
IRQ_ENABLE  = $FE31
LEDS        = $FE40
HEX_L       = $FE42
HEX_H       = $FE43

; ---------------------------------------------------------------------------
; Settings
; ---------------------------------------------------------------------------
TONE        = 590           ; 440 Hz (each unit is 0.745 Hz)
TONE_FRAMES = 15            ; a quarter of a second
BAR_ROWS    = 23            ; the title takes the last 2 of the 25 rows
TITLE_ROW   = TEXT + BAR_ROWS*40
TITLE_COLOR = $07           ; white on black

; ---------------------------------------------------------------------------
; Variables, in the boot RAM above the stack
; ---------------------------------------------------------------------------
STACK_TOP   = $FD00         ; the stack grows down from $FCFF
RELEASE     = $FD00         ; the last keyboard byte was $F0 (key up)
TIMER       = $FD01         ; frames left in the tone
FRAMES      = $FD02         ; frame counter
ROWS        = $FD04         ; rows left to fill

; ---------------------------------------------------------------------------
; Start
; ---------------------------------------------------------------------------
    .org $F000
reset:
    sei                     ; no interrupts: everything is polled
    cld
    lds STACK_TOP
    ldaz
    sta VID_MODE            ; text mode
    sta VID_BORDER          ; black border
    sta IRQ_ENABLE
    sta V0_VOL              ; silent
    sta V0_WAVE             ; square wave
    sta LEDS
    sta HEX_L
    sta HEX_H
    sta RELEASE
    sta TIMER
    sta FRAMES
    lda #TONE.low
    sta V0_FREQ
    lda #TONE.high
    sta V0_FREQ+1

    ; Fill the screen with spaces
    ldb #1000.high
    ldc #1000.low
    exe                     ; EE = count
    ldb #TEXT.high
    ldc #TEXT.low
    exd                     ; DD = text
    lda #' '
clear:
    sta (dd)
    inc dd
    dec ee
    jpnz clear

    ; Color bars: each row is the 8 colors in the table, 5 cells each
    ldb #COLOR.high
    ldc #COLOR.low
    exd                     ; DD = color memory
    lda #BAR_ROWS
    sta ROWS
bar_row:
    ldb #bars.high
    ldc #bars.low           ; BC = color table
bar_next:
    lda (bc)
    cpa #$FF
    jmpz bar_row_done
    sta (dd)
    inc dd
    sta (dd)
    inc dd
    sta (dd)
    inc dd
    sta (dd)
    inc dd
    sta (dd)
    inc dd
    inc bc
    jmpr bar_next
bar_row_done:
    lda ROWS
    dec a
    sta ROWS
    jpnz bar_row

    ; The last two rows: white on black (DD is there now)
    ldb #80
    lda #TITLE_COLOR
title_color:
    sta (dd)
    inc dd
    dec b
    jpnz title_color

    ; Title
    ldb #TITLE_ROW.high
    ldc #TITLE_ROW.low
    exd
    ldb #title1.high
    ldc #title1.low
    jsr print
    ldb #(TITLE_ROW+40).high
    ldc #(TITLE_ROW+40).low
    exd
    ldb #title2.high
    ldc #title2.low
    jsr print

    lda #1
    sta IRQ_STATUS          ; clear the frame flag

; ---------------------------------------------------------------------------
; Main loop
; ---------------------------------------------------------------------------
main:
    ; Once a frame: time the tone, and blink LED4
    lda IRQ_STATUS
    and #1
    jmpz check_key
    sta IRQ_STATUS          ; clear the frame flag (A = 1)
    lda TIMER
    jmpz tone_off
    dec a
    sta TIMER
    jpnz show_leds
tone_off:
    ldaz
    sta V0_VOL
show_leds:
    lda FRAMES
    inc a
    sta FRAMES
    and #$20                ; LED4: on for 32 frames, off for 32
    lsr a
    lsr a
    ldc a
    lda TIMER
    jmpz leds_set
    lda c
    ora #1                  ; LED1: the tone is playing
    ldc a
leds_set:
    stc LEDS

check_key:
    lda KBD_STATUS
    and #1
    jmpz main
    lda KBD_DATA
    cpa #$F0                ; the next byte is a key being released
    jmpz key_up
    cpa #$E0                ; prefix of an extended key: wait for its code
    jmpz main
    ldc a                   ; C = scan code
    lda RELEASE
    jpnz key_released

    ; A key was pressed: show it and play the tone
    lda c
    jsr show_decimal
    lda #TONE_FRAMES
    sta TIMER
    lda #15
    sta V0_VOL
    jmp main

key_up:
    lda #1
    sta RELEASE
    jmp main
key_released:
    ldaz
    sta RELEASE
    jmp main

; Show A (0-255) on the display in decimal, as 0000-0255. The display shows
; the hex digits of HEX_H and HEX_L, so each gets a BCD digit.
show_decimal:
    ldbz                    ; B = hundreds
hundreds:
    sub #100
    jmpc hundreds_done      ; borrowed: A was under 100
    inc b
    jmpr hundreds
hundreds_done:
    add #100                ; undo the last subtraction
    stb HEX_H               ; left digits: 0 and the hundreds
    ldbz                    ; B = tens
tens:
    sub #10
    jmpc tens_done
    inc b
    jmpr tens
tens_done:
    add #10                 ; A = ones
    ldc a
    lda b
    asl a
    asl a
    asl a
    asl a
    ora c                   ; tens in the high digit, ones in the low
    sta HEX_L
    rts

; Copy the zero-terminated string at BC to the screen at DD
print:
    lda (bc)
    jmpz print_done
    sta (dd)
    inc bc
    inc dd
    jmpr print
print_done:
    rts

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------

; Bar colors (background in bits 6-4, the same foreground), then $FF
bars:
    .byte $77, $66, $33, $22, $55, $44, $11, $00, $FF

title1:
    .byte " ROCKET88 SMOKE TEST", 0
title2:
    .byte " Press a key to hear a 440 Hz tone", 0

; ---------------------------------------------------------------------------
; Vectors
; ---------------------------------------------------------------------------
    .org $FFFA
    .addr reset             ; IRQ (not used)
    .addr reset             ; NMI (not used)
    .addr reset             ; RESET
