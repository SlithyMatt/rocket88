; boot.asm - boot program for the Rocket88 computer (verilog/system)
;
; Loaded into the boot RAM at $F000-$FFFF when the FPGA is configured.
; Build it into system/boot.mem with:  python3 tools/build_system_roms.py
;
; Tests the SDRAM at $0000-$BFFF, then shows a screen that echoes the
; keyboard, moves a pointer with the mouse (left button draws, right button
; erases), clicks with each key, and uses the board's keys:
;   KEY1  switch between text and bitmap mode
;   KEY2  change the border color
;   KEY3  clear the screen
;   KEY4  change the background color
; The frame interrupt drives the sound envelope and blinks LED4. LED1 and
; LED2 show the mouse buttons, and the display shows the last key's ASCII
; code and scan code.

; ---------------------------------------------------------------------------
; Hardware
; ---------------------------------------------------------------------------
BITMAP      = $C000
TEXT        = $E000
COLOR       = $E400
FONT        = $E800

VID_MODE    = $FE00         ; bit 0: 1 = bitmap
VID_BORDER  = $FE01
KBD_DATA    = $FE10
KBD_STATUS  = $FE11         ; bit 0: data ready
MOUSE_DATA  = $FE12
MOUSE_STATUS = $FE13
V0_FREQ     = $FE20
V0_VOL      = $FE22
V0_WAVE     = $FE23
V1_FREQ     = $FE24
V1_VOL      = $FE26
V1_WAVE     = $FE27
IRQ_STATUS  = $FE30         ; bit 0: frame
IRQ_ENABLE  = $FE31
LEDS        = $FE40
KEYS        = $FE41
HEX_L       = $FE42
HEX_H       = $FE43

; ---------------------------------------------------------------------------
; Variables
; ---------------------------------------------------------------------------
STACK_TOP   = $C000         ; the stack grows down from $BFFF
VARS        = $0000
CUR_PTR     = VARS+0        ; text cursor address (2 bytes)
CUR_COL     = VARS+2        ; text cursor column
SHIFT       = VARS+3        ; a shift key is down
RELEASE     = VARS+4        ; the last keyboard byte was $F0 (key up)
EXTENDED    = VARS+5        ; the last keyboard byte was $E0
MX          = VARS+6        ; mouse position, 0-159
MY          = VARS+7        ; mouse position, 0-99
MPKT_N      = VARS+8        ; bytes of the mouse packet received
MPKT0       = VARS+9
MPKT1       = VARS+10
MPKT2       = VARS+11
MBTN        = VARS+12       ; mouse buttons
PTR_ADDR    = VARS+13       ; address of the pointer on the screen (2 bytes)
PTR_SAVE    = VARS+15       ; character under the pointer
FRAMES      = VARS+16       ; frame counter
SND_VOL     = VARS+17       ; sound volume, decays to 0
KEYS_PREV   = VARS+18
SCREEN_COLOR = VARS+19
BORDER      = VARS+20
TMP         = VARS+21
VARS_LEN    = 24

DEFAULT_COLOR = $17         ; white on blue
DEFAULT_BORDER = 3          ; cyan
CURSOR      = $7F           ; solid block
POINTER     = $1F           ; arrow

; ---------------------------------------------------------------------------
; Reset
; ---------------------------------------------------------------------------
    .org $F000
reset:
    sei
    cld

    ; Test $0000-$BFFF before anything uses RAM: write a pattern made from
    ; each address, then read it all back.
    ldbz
    ldcz
ram_write:
    lda b
    xor c
    xor #$5A
    sta (bc)
    inc bc
    lda b
    cpa #$C0
    jpnz ram_write
    ldbz
    ldcz
ram_read:
    lda b
    xor c
    xor #$5A
    xor (bc)
    jpnz ram_done           ; BC = the address that failed
    inc bc
    lda b
    cpa #$C0
    jpnz ram_read
ram_done:
    lds STACK_TOP
    phb                     ; keep the result: $C000 if the test passed
    phc

    ; Clear the variables
    ldb #VARS.high
    ldc #VARS.low
    ldaz
clear_vars:
    sta (bc)
    inc c
    cpc #VARS_LEN
    jpnz clear_vars

    lda #DEFAULT_COLOR
    sta SCREEN_COLOR
    lda #DEFAULT_BORDER
    sta BORDER
    sta VID_BORDER
    lda #80
    sta MX
    lda #50
    sta MY

    jsr draw_bitmap
    jsr fill_colors
    jsr clear_screen

    ; Banner and RAM test result
    ldb #banner.high
    ldc #banner.low
    jsr print
    plc                     ; BC = RAM test result
    plb
    lda b
    cpa #$C0
    jpnz ram_failed
    ldb #ram_ok.high
    ldc #ram_ok.low
    jsr print
    jmpr ram_reported
ram_failed:
    phc
    phb
    ldb #ram_bad.high
    ldc #ram_bad.low
    jsr print
    pla
    jsr print_hex
    pla
    jsr print_hex
    lda #13
    jsr putc
ram_reported:
    ldb #help.high
    ldc #help.low
    jsr print

    ; Ask the mouse to start reporting
    lda #$F4
    sta MOUSE_DATA

    ; Sound: two triangle voices, and a chime
    lda #2
    sta V0_WAVE
    sta V1_WAVE
    lda #702.low            ; C5
    sta V0_FREQ
    lda #702.high
    sta V0_FREQ+1
    lda #1052.low           ; G5
    sta V1_FREQ
    lda #1052.high
    sta V1_FREQ+1
    lda #15
    sta SND_VOL
    sta V0_VOL
    sta V1_VOL

    jsr show_ptr

    ; Frame interrupt on
    lda #1
    sta IRQ_STATUS
    sta IRQ_ENABLE
    cli

; ---------------------------------------------------------------------------
; Main loop: poll the keyboard, mouse and board keys
; ---------------------------------------------------------------------------
main:
    lda KBD_STATUS
    and #1
    jmpz no_key
    jsr hide_ptr
    lda KBD_DATA
    jsr key_byte
    jsr show_ptr
no_key:
    lda MOUSE_STATUS
    and #1
    jmpz no_mouse
    lda MOUSE_DATA
    jsr mouse_byte
no_mouse:
    jsr check_keys
    jmp main

; ---------------------------------------------------------------------------
; Frame interrupt: sound envelope and heartbeat LED
; ---------------------------------------------------------------------------
irq:
    lda #1
    sta IRQ_STATUS          ; acknowledge
    lda FRAMES
    inc a
    sta FRAMES
    and #$20                ; LED4 blinks about once a second
    lsr a
    lsr a
    ora MBTN
    sta LEDS
    lda FRAMES
    and #1
    jmpz irq_done           ; decay every other frame
    lda SND_VOL
    jmpz irq_done
    dec a
    sta SND_VOL
    sta V0_VOL
    sta V1_VOL
irq_done:
nmi:
    rti

; ---------------------------------------------------------------------------
; Keyboard: A = a byte from the keyboard (scan code set 2)
; ---------------------------------------------------------------------------
key_byte:
    sta HEX_L
    cpa #$F0
    jmpz key_release
    cpa #$E0
    jmpz key_extended
    ldc a                   ; C = scan code
    lda RELEASE
    ldb a                   ; B = this is a key up
    ldaz
    sta RELEASE
    lda EXTENDED
    jpnz key_ignore         ; skip extended keys (arrows and so on)
    lda c
    cpa #$12                ; left shift
    jmpz key_shift
    cpa #$59                ; right shift
    jmpz key_shift
    lda b
    jpnz key_done           ; ignore other key ups
    lda c
    and #$80
    jpnz key_done           ; no characters above $7F
    ; Look up the character
    stc TMP
    lda SHIFT
    jmpz key_unshifted
    ldb #keymap_shift.high
    lda #keymap_shift.low
    jmpr key_lookup
key_unshifted:
    ldb #keymap.high
    lda #keymap.low
key_lookup:
    add TMP
    ldc a
    jpnc key_nc
    inc b
key_nc:
    lda (bc)
    jmpz key_done
    sta HEX_H
    pha
    jsr click
    pla
    jmp putc
key_shift:
    lda b
    xor #1                  ; down = 1, up = 0
    sta SHIFT
    rts
key_release:
    lda #1
    sta RELEASE
    rts
key_extended:
    lda #1
    sta EXTENDED
    rts
key_ignore:
    ldaz                    ; the code after $E0 (and $F0, for a key up)
    sta EXTENDED
key_done:
    rts

; Click: A = character, sets the pitch
click:
    ldc a
    ldbz
    asl c
    rol b
    asl c
    rol b
    asl c
    rol b
    stc V0_FREQ
    stb V0_FREQ+1
    asl c                   ; an octave up
    rol b
    stc V1_FREQ
    stb V1_FREQ+1
    lda #15
    sta SND_VOL
    sta V0_VOL
    sta V1_VOL
    rts

; ---------------------------------------------------------------------------
; Mouse: A = a byte from the mouse. Packets are 3 bytes: buttons and signs,
; X movement, Y movement (up is positive).
; ---------------------------------------------------------------------------
mouse_byte:
    ldc a
    lda MPKT_N
    jpnz mouse_more
    lda c
    cpa #$FA                ; acknowledge
    jmpz mouse_ret
    cpa #$AA                ; self-test passed
    jmpz mouse_ret
    and #$08                ; always set in the first byte of a packet
    jmpz mouse_ret
    stc MPKT0
    lda #1
    sta MPKT_N
mouse_ret:
    rts
mouse_more:
    cpa #1
    jpnz mouse_third
    stc MPKT1
    lda #2
    sta MPKT_N
    rts
mouse_third:
    stc MPKT2
    ldaz
    sta MPKT_N

    ; Left button leaves a block where the pointer was, right erases
    lda MPKT0
    and #3
    sta MBTN
    and #1
    jmpz mouse_no_left
    lda #CURSOR
    sta PTR_SAVE
mouse_no_left:
    lda MBTN
    and #2
    jmpz mouse_no_right
    lda #' '
    sta PTR_SAVE
mouse_no_right:
    jsr hide_ptr

    ; X: 0-159
    lda MPKT1
    jmpn mouse_left
    add MX
    jmpc mouse_x_max
    cpa #160
    jpnc mouse_x_set
mouse_x_max:
    lda #159
    jmpr mouse_x_set
mouse_left:
    add MX
    jmpc mouse_x_set        ; no borrow, so still on screen
    ldaz
mouse_x_set:
    sta MX

    ; Y: 0-99, down the screen
    lda MPKT2
    neg
    jmpn mouse_up
    add MY
    jmpc mouse_y_max
    cpa #100
    jpnc mouse_y_set
mouse_y_max:
    lda #99
    jmpr mouse_y_set
mouse_up:
    add MY
    jmpc mouse_y_set
    ldaz
mouse_y_set:
    sta MY
    jmp show_ptr

; Put the pointer back to what it covered
hide_ptr:
    ldb PTR_ADDR+1
    ldc PTR_ADDR
    lda PTR_SAVE
    sta (bc)
    rts

; Show the pointer at cell (MX/4, MY/4)
show_ptr:
    lda MY
    lsr a
    lsr a                   ; row
    ldc a
    asl a
    asl a
    add c                   ; row * 5
    ldc a
    ldbz
    asl c
    rol b
    asl c
    rol b
    asl c
    rol b                   ; BC = row * 40
    lda MX
    lsr a
    lsr a                   ; column
    add c
    ldc a
    jpnc show_nc
    inc b
show_nc:
    lda b
    add #TEXT.high
    ldb a
    stb PTR_ADDR+1
    stc PTR_ADDR
    lda (bc)
    sta PTR_SAVE
    lda #POINTER
    sta (bc)
    rts

; ---------------------------------------------------------------------------
; Board keys, acted on when pressed
; ---------------------------------------------------------------------------
check_keys:
    lda KEYS
    ldc a
    lda KEYS_PREV
    xor #$FF
    and c                   ; keys that went down
    stc KEYS_PREV
    jpnz keys_down
    rts
keys_down:
    sta TMP
    jsr hide_ptr
    lda TMP
    and #1
    jmpz keys_2
    lda VID_MODE            ; KEY1: text / bitmap
    xor #1
    sta VID_MODE
keys_2:
    lda TMP
    and #2
    jmpz keys_3
    lda BORDER              ; KEY2: border color
    inc a
    and #7
    sta BORDER
    sta VID_BORDER
keys_3:
    lda TMP
    and #4
    jmpz keys_4
    jsr clear_screen        ; KEY3: clear
keys_4:
    lda TMP
    and #8
    jmpz keys_done
    lda SCREEN_COLOR        ; KEY4: next background (skipping white on white)
    add #$10
    and #$7F
    cpa #$77
    jpnz keys_color
    lda #$07
keys_color:
    sta SCREEN_COLOR
    jsr fill_colors
    jsr draw_cursor
keys_done:
    jmp show_ptr

; ---------------------------------------------------------------------------
; Text output
; ---------------------------------------------------------------------------

; Print the zero-terminated string at BC
print:
    exe                     ; EE = string
print_loop:
    exe
    lda (bc)
    jmpz print_done
    inc bc
    exe
    jsr putc                ; keeps EE
    jmpr print_loop
print_done:
    exe
    rts

; Print A as two hex digits
print_hex:
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr hex_digit
    pla
hex_digit:
    and #$0F
    cpa #10
    jmpc hex_letter
    add #'0'
    jmp putc
hex_letter:
    add #'A'-10
    jmp putc

; Print character A at the cursor. 13 = new line, 8 = backspace.
; Uses A, B, C and DD.
putc:
    pha
    jsr erase_cursor
    pla
    cpa #13
    jmpz putc_newline
    cpa #8
    jmpz putc_backspace
    ldb CUR_PTR+1
    ldc CUR_PTR
    sta (bc)
    inc bc
    stb CUR_PTR+1
    stc CUR_PTR
    lda CUR_COL
    inc a
    sta CUR_COL
    cpa #40
    jpnz draw_cursor
    ldaz
    sta CUR_COL
    jmpr check_scroll
putc_newline:
    lda #40
    sub CUR_COL             ; move to the start of the next line
    add CUR_PTR
    sta CUR_PTR
    lda CUR_PTR+1
    adcz
    sta CUR_PTR+1
    ldaz
    sta CUR_COL
check_scroll:
    lda CUR_PTR+1
    cpa #(TEXT+1000).high
    jpnz draw_cursor
    lda CUR_PTR
    cpa #(TEXT+1000).low
    jpnc draw_cursor        ; still on the screen
    jsr scroll
    lda CUR_PTR
    sub #40
    sta CUR_PTR
    lda CUR_PTR+1
    sbcz
    sta CUR_PTR+1
    jmpr draw_cursor
putc_backspace:
    lda CUR_COL
    jmpz draw_cursor
    dec a
    sta CUR_COL
    lda CUR_PTR
    sub #1
    sta CUR_PTR
    lda CUR_PTR+1
    sbcz
    sta CUR_PTR+1
    ; fall through

; Show the cursor: a blinking block
draw_cursor:
    ldb CUR_PTR+1
    ldc CUR_PTR
    lda #CURSOR
    sta (bc)
    lda b
    add #(COLOR-TEXT).high
    ldb a
    lda (bc)
    ora #$80
    sta (bc)
    rts

erase_cursor:
    ldb CUR_PTR+1
    ldc CUR_PTR
    lda #' '
    sta (bc)
    lda b
    add #(COLOR-TEXT).high
    ldb a
    lda (bc)
    and #$7F
    sta (bc)
    rts

; Scroll the text up one line. Keeps EE, for print.
scroll:
    exe
    phb
    phc
    ldb #960.high
    ldc #960.low
    exe                     ; EE = count
    ldb #TEXT.high
    ldc #TEXT.low
    exd                     ; DD = destination
    ldb #(TEXT+40).high
    ldc #(TEXT+40).low      ; BC = source
scroll_loop:
    lda (bc)
    sta (dd)
    inc bc
    inc dd
    dec ee
    jpnz scroll_loop
    ldb #40                 ; clear the last line (DD is there now)
    lda #' '
scroll_clear:
    sta (dd)
    inc dd
    dec b
    jpnz scroll_clear
    plc
    plb
    exe
    rts

; Clear the text and put the cursor at the top left
clear_screen:
    ldb #1000.high
    ldc #1000.low
    exe
    ldb #TEXT.high
    ldc #TEXT.low
    exd
    lda #' '
clear_loop:
    sta (dd)
    inc dd
    dec ee
    jpnz clear_loop
    lda #TEXT.low
    sta CUR_PTR
    lda #TEXT.high
    sta CUR_PTR+1
    ldaz
    sta CUR_COL
    jmp draw_cursor

; Set every cell's color to SCREEN_COLOR
fill_colors:
    ldb #1000.high
    ldc #1000.low
    exe
    ldb #COLOR.high
    ldc #COLOR.low
    exd
    lda SCREEN_COLOR
fill_loop:
    sta (dd)
    inc dd
    dec ee
    jpnz fill_loop
    rts

; Draw a pattern in the bitmap: each byte is (row XOR column*8)
draw_bitmap:
    ldb #BITMAP.high
    ldc #BITMAP.low
    exd
    ldbz                    ; B = row
bitmap_row:
    ldcz                    ; C = column
bitmap_col:
    lda c
    asl a
    asl a
    asl a
    xor b
    sta (dd)
    inc dd
    inc c
    lda c
    cpa #40
    jpnz bitmap_col
    inc b
    lda b
    cpa #200
    jpnz bitmap_row
    rts

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
banner:
    .byte "ROCKET88 COMPUTER", 13
    .byte "64K RAM, 8 colors, 4 voices", 13, 13, 0
ram_ok:
    .byte "RAM $0000-$BFFF OK", 13, 13, 0
ram_bad:
    .byte "RAM ERROR AT $", 0
help:
    .byte "Type on the keyboard. Move the mouse:", 13
    .byte "left button draws, right button erases.", 13, 13
    .byte "KEY1 bitmap   KEY2 border", 13
    .byte "KEY3 clear    KEY4 colors", 13, 13, 0

; PS/2 scan code set 2 to ASCII, for codes $00-$7F
keymap:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $20, $60, $00   ; $00
    .byte $00, $00, $00, $00, $00, $71, $31, $00, $00, $00, $7A, $73, $61, $77, $32, $00   ; $10
    .byte $00, $63, $78, $64, $65, $34, $33, $00, $00, $20, $76, $66, $74, $72, $35, $00   ; $20
    .byte $00, $6E, $62, $68, $67, $79, $36, $00, $00, $00, $6D, $6A, $75, $37, $38, $00   ; $30
    .byte $00, $2C, $6B, $69, $6F, $30, $39, $00, $00, $2E, $2F, $6C, $3B, $70, $2D, $00   ; $40
    .byte $00, $00, $27, $00, $5B, $3D, $00, $00, $00, $00, $0D, $5D, $00, $5C, $00, $00   ; $50
    .byte $00, $00, $00, $00, $00, $00, $08, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; $60
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; $70
keymap_shift:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $20, $7E, $00   ; $00
    .byte $00, $00, $00, $00, $00, $51, $21, $00, $00, $00, $5A, $53, $41, $57, $40, $00   ; $10
    .byte $00, $43, $58, $44, $45, $24, $23, $00, $00, $20, $56, $46, $54, $52, $25, $00   ; $20
    .byte $00, $4E, $42, $48, $47, $59, $5E, $00, $00, $00, $4D, $4A, $55, $26, $2A, $00   ; $30
    .byte $00, $3C, $4B, $49, $4F, $29, $28, $00, $00, $3E, $3F, $4C, $3A, $50, $5F, $00   ; $40
    .byte $00, $00, $22, $00, $7B, $2B, $00, $00, $00, $00, $0D, $7D, $00, $7C, $00, $00   ; $50
    .byte $00, $00, $00, $00, $00, $00, $08, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; $60
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; $70

; ---------------------------------------------------------------------------
; Vectors
; ---------------------------------------------------------------------------
    .org $FFFA
    .addr irq
    .addr nmi
    .addr reset
