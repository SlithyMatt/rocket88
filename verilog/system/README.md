# Rocket88 Computer
A complete computer built around the ROCKET88 core: 64 KB of RAM, VGA video with text and bitmap modes, four-voice sound, and PS/2 keyboard and mouse ports. The system itself ([r88_system.v](r88_system.v)) doesn't depend on the board; a board's top level connects it to the pins.

The first board is the Cyclone IV EP4CE6 development board ([board documentation](https://github.com/SlithyMatt/Altera-Cyclone-IV-board-V3.0)), with its top level in [c4board.v](../c4board.v), pins in [Rocket88.qsf](../Rocket88.qsf) and timing constraints in [Rocket88.sdc](../Rocket88.sdc).

| File | Contents |
|------|----------|
| [r88_system.v](r88_system.v) | CPU, clocking, memory map, I/O registers, interrupts |
| [r88_sdram.v](r88_sdram.v) | SDRAM controller |
| [r88_video.v](r88_video.v) | VGA controller and video memory |
| [r88_sound.v](r88_sound.v) | Sound generator |
| [r88_ps2.v](r88_ps2.v) | PS/2 port (used twice) |
| [r88_pll.v](r88_pll.v) | Clock generation (Cyclone IV E PLL, or a model for simulation) |
| [boot.asm](boot.asm) | Boot program |
| boot.mem, font.mem | Memory images, built by [tools/build_system_roms.py](../../tools/build_system_roms.py) |
| [examples/smoke_test.asm](examples/smoke_test.asm) | Color bars and a tone on each key press, to test a newly programmed board |

## Building
1. If you changed [boot.asm](boot.asm) or the font, rebuild the memory images from the repository root:
   ```
   python3 tools/build_system_roms.py
   ```
2. Open `verilog/Rocket88.qpf` in Quartus Prime Lite (21.1 or later) and compile.
3. Program the board with `output_files/Rocket88.sof` over JTAG.

## Smoke Test
[examples/smoke_test.asm](examples/smoke_test.asm) is the first program to run on a newly programmed board. It runs entirely inside the FPGA, without using the SDRAM, and polls everything without interrupts.
* The screen shows eight color bars (white, yellow, cyan, green, magenta, red, blue and black), with a title at the bottom.
* LED4 blinks about once a second, showing that the CPU and video are running.
* Each key press on the PS/2 keyboard plays a 440 Hz beep for a quarter of a second and lights LED1 while it plays.
* The display shows the number of keys pressed (left two digits) and the last scan code (right two digits).

To run it, build it into the boot RAM image, then compile and program the board as usual. From the repository root:
```
python3 tools/build_system_roms.py verilog/system/examples/smoke_test.asm
```
Afterwards, run the script with no argument to go back to the normal boot program.

[sim/tb_smoke.v](../sim/tb_smoke.v) checks the smoke test in simulation: the colors of the bars in a captured frame, the title, the tone and its timing, and the display. Its header has the commands to run it.

## Clocking
Everything runs on a 50 MHz system clock from the PLL. The CPU is clocked at 1/16 of that, 3.125 MHz, so each two-step CPU cycle takes 640 ns, and an instruction of 2 cycles takes 1.28 µs. Each CPU clock period is a 16-clock bus slot. The CPU's address, Read, Write and data are latched 5 clocks after its clock edge. Any memory or I/O access then completes within the slot, and read data is ready 5 clocks before the next edge. Memory never makes the CPU wait.

## Memory Map
| Address | Size | Contents |
|---------|------|----------|
| $0000-$7FFF | 32 KB | RAM (SDRAM) |
| $8000-$BFFF | 16 KB | RAM (SDRAM), banked: any 16 KB page of the 8 MB SDRAM, selected by BANK ($FE48) |
| $C000-$DFFF | 8 KB | Bitmap: 320x200, 1 bit per pixel, 40 bytes per row, the leftmost pixel in bit 7. $DF40-$DFFF is spare RAM. |
| $E000-$E3FF | 1 KB | Text: 40x25 character codes, row by row. $E3E8-$E3FF is spare. |
| $E400-$E7FF | 1 KB | Color: one byte for each 8x8 cell. $E7E8-$E7FF is spare. |
| $E800-$EFFF | 2 KB | Font: 256 characters, 8 bytes each, top row first, the leftmost pixel in bit 7 |
| $F000-$FDFF, $FF00-$FFFF | 4 KB | Boot RAM, which holds the boot program and the interrupt vectors when the FPGA is configured |
| $FE00-$FEFF | 256 bytes | I/O registers |

Every address except the I/O page is RAM and can be read and written. With BANK at 0, $0000-$BFFF is one flat 48 KB. The video memory and boot RAM are inside the FPGA; the CPU reads and writes them like any other RAM.

The RESET button restarts the CPU and resets the I/O registers, but RAM keeps its contents. A program that overwrites the boot RAM stays there until the FPGA is configured again.

## Video
The VGA output is 640x480 at 60 Hz. The 320x200 picture is shown with each pixel doubled, as 640x400, with a 40-line border above and below it in the border color.

The board's VGA connector has one bit for each color, so there are 8 colors. Each color number has bit 2 for red, bit 1 for green and bit 0 for blue:

| 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| black | blue | green | cyan | red | magenta | yellow | white |

Each 8x8 cell has a color byte: bits 2-0 are the foreground, bits 6-4 the background, and bit 7 makes the foreground blink (about once a second).

* **Text mode** shows 40x25 characters from the font. The font is in RAM, so programs can redefine any character.
* **Bitmap mode** shows the 320x200 bitmap. A set bit is drawn in its cell's foreground color, and a clear bit in its background color.

The default font has quadrant blocks at $00-$0F (bit 0 top left, bit 1 top right, bit 2 bottom left, bit 3 bottom right, for 80x50 block graphics). It has line drawing at $10-$1A, a checkerboard at $1B, diagonals at $1C-$1D, a ball at $1E and an arrow pointer at $1F. ASCII is at $20-$7E and a solid block at $7F. Characters $80-$FF are $00-$7F in inverse video.

## Sound
There are four voices, each with a 16-bit frequency, a volume and a waveform. A voice plays at frequency × 0.745 Hz, so A440 is 590. The voices are mixed and played on the board's speaker as PWM. Two voices at full volume reach the maximum level, and more than that is clipped.

## PS/2
Each port has an 8-byte receive FIFO. Reading the data register takes the oldest byte. Writing the data register sends a byte to the device, such as $F4 to make a mouse start reporting, or $ED to set the keyboard LEDs. The device answers with $FA, which arrives in the FIFO. Keyboard bytes are raw scan codes (set 2).

The board has one PS/2 port, which is used for the keyboard. The mouse needs a second PS/2 socket wired to the expansion header, as described in [Rocket88.qsf](../Rocket88.qsf).

## Interrupts
IRQ is requested when any enabled interrupt status bit is set. NMI is not used.

| Bit | Source |
|-----|--------|
| 0 | Frame: set at the end of the picture (line 440), 60 times a second. Cleared by writing 1 to it. |
| 1 | Keyboard: the FIFO has data |
| 2 | Mouse: the FIFO has data |

## I/O Registers
| Address | Name | R/W | Contents |
|---------|------|-----|----------|
| $FE00 | VID_MODE | R/W | bit 0: 0 = text, 1 = bitmap |
| $FE01 | VID_BORDER | R/W | bits 2-0: border color |
| $FE02 | VID_LINE_L | R | Line being displayed, low byte (0-524; the picture is lines 40-439) |
| $FE03 | VID_LINE_H | R | Line being displayed, high bits |
| $FE10 | KBD_DATA | R/W | Read: next byte from the keyboard. Write: send a byte to the keyboard. |
| $FE11 | KBD_STATUS | R/W | bit 0: data ready, bit 1: sending, bit 2: error (parity, framing, timeout or FIFO overflow). Any write clears the error. |
| $FE12 | MOUSE_DATA | R/W | The same as KBD_DATA, for the mouse |
| $FE13 | MOUSE_STATUS | R/W | The same as KBD_STATUS, for the mouse |
| $FE20+4n | Vn_FREQ_L | W | Voice n (0-3) frequency, low byte |
| $FE21+4n | Vn_FREQ_H | W | Voice n frequency, high byte |
| $FE22+4n | Vn_VOL | W | Voice n volume, 0-15 |
| $FE23+4n | Vn_WAVE | W | Voice n waveform: 0 square, 1 sawtooth, 2 triangle, 3 noise |
| $FE30 | IRQ_STATUS | R/W | Interrupt status (see above). Write 1 to bit 0 to clear the frame interrupt. |
| $FE31 | IRQ_ENABLE | R/W | Interrupt enables, the same bits as IRQ_STATUS |
| $FE40 | LEDS | R/W | bits 3-0: LED4-LED1, 1 = on |
| $FE41 | KEYS | R | bits 3-0: KEY4-KEY1, 1 = pressed |
| $FE42 | HEX_L | R/W | 7-segment display value, low byte |
| $FE43 | HEX_H | R/W | 7-segment display value, high byte |
| $FE44 | HEX_CTRL | R/W | bit 0: display on (set at reset), bit 1: show the address bus instead |
| $FE48 | BANK | R/W | SDRAM page shown at $8000-$BFFF. Bank n is SDRAM bytes $8000 + n × $4000, so bank 0 makes the first 48 KB flat. |

Unlisted addresses in the I/O page read as 0.

## Boot Program
[boot.asm](boot.asm) tests the RAM at $0000-$BFFF and reports the result. It then shows a screen that:
* echoes typing from the keyboard, with a blinking cursor and a key click;
* moves a pointer with the mouse, where the left button draws and the right button erases;
* draws a pattern in the bitmap.

The board's keys select bitmap mode (KEY1), change the border color (KEY2), clear the screen (KEY3) and change the background color (KEY4). LED1 and LED2 show the mouse buttons, and LED4 blinks from the frame interrupt. The display shows the last key's ASCII code and scan code.

## Simulation
[sim/tb_system.v](../sim/tb_system.v) runs the whole board top level with models of the SDRAM (which check its timing and protocol), a keyboard and a mouse. It boots the boot program and checks:
* the screen, typing, the mouse pointer and drawing;
* the sound, the frame interrupt and the VGA timing;
* bitmap mode, the board's keys and the 7-segment display.

It writes the frames it captures to `sim/frame_text.ppm` and `sim/frame_bitmap.ppm`. From the `verilog` directory:
```
iverilog -g2005 -DSIMULATION -o sim/system.vvp sim/tb_system.v sim/sdram_model.v sim/ps2_device.v \
    c4board.v system/*.v Rocket88.v r88_mc.v r88_regblock.v r88_alu.v r88_decoder.v
vvp -n sim/system.vvp
```
It takes a few minutes. To keep it shorter, the testbench limits the boot RAM test to $0000-$01FF; add `+fullram` to test it all.
