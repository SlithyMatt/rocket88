# r88asm - ROCKET88 assembler
#   make        build r88asm
#   make test   run the tests (needs python3 and Icarus Verilog)
#   make clean  remove the build

CC = gcc
CFLAGS ?= -std=c99 -Wall -Wextra -pedantic -O2

r88asm: r88asm.c
	$(CC) $(CFLAGS) -o $@ r88asm.c

test: r88asm
	python3 tests/run_tests.py

clean:
	rm -f r88asm r88asm.exe

.PHONY: test clean
