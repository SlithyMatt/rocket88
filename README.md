# ROCKET88
## A New 8-Bit Architecture

**ROCKET88** -- **R**etro **O**bsolete **C**omputational **K**ernel for **E**lectronic **T**ransacting (Data Bus: **8**-Bit Internal, **8**-Bit External) -- is a virtual 8-bit architecture for modeled microprocessors, to run either in software emulation or programmable logic. As it is entirely unlikely that a custom silicon implementation will ever be created, this architecture will be free to evolve and have multiple community-developed variants, but ultimately there will be a reference design at https://github.com/SlithyMatt/rocket88 which will include this document, implementations of the architecture in Verilog and C++, and a simple computer system built around this architecture targeting specific FPGA development boards and a software emulator. This repo will take pull requests from the community, but it will be a complete free and open source project and the community is free to make any changes they like in their forks and incorporate it into other free and open source projects, as per the [license](LICENSE).

## External Interface
Externally, ROCKET88 will have an 8-bit data bus and a 16-bit address bus. It will operate on a single voltage and clock, and have control pins for reading and writing memory. An I/O connected will need to be mapped to memory, requiring external memory management for any system using a ROCKET88 core. The entire 64k memory space can be used in any fashion, except for the last 6 bytes ($FFFA-$FFFF), which will contain 3 interrupt vectors, but they may be mapped to ROM or RAM. These interrupts will be triggered by NMI, IRQ and RESET pins, and there will also be Read and Write control pins, and that is all.

(Pinout Diagram)

At power on, the RESET vector will be fetched and execution will begin at the address read there.

### Timing
TBD

### Interrupts
TBD

## Internal Components

(Core Block Diagram)

### Registers
ROCKET88 is focused on register manipulation, with most results being stored in the 8-bit Accumulator, or A register. Additionally, there are two 8-bit general purpose registers named B and C, which can form a single 16-bit address register called BC. Then there are two more special-purpose 16-bit address registers: the Program Counter (PC) and the Stack Pointer (SP), allowing code and the stack to occupy any part of the address space. Then the Processor Status register, also known as P, contains all the status bits, and those are mostly accessed individually. Finally, there are two 16-bit shadow registers named DD and EE which can have their values exchanged with BC to have faster access to pointers and counters without having to fetch them from memory.

(Detailed Register Diagram)

For the purposes of this document, we will refer to the high and low bytes of the address registers with the suffixes H and L. For example, the high byte of the Program Counter will be referred to as PCH. In the case of BC, for the sake of simplicty, we will just refer to the individual bytes as B and C, and not BCH and BCL.

### Memory Controller
The Memory Controller (MC) starts each instruction cycle by fetching a byte from memory at the address in PC. This will be the Operation Code, or opcode, for the instruction. The Instruction Decoder then determines what the MC does next based on the opcode. If it requires immediate or direct addressing, then it will fetch the following 1 or 2 bytes (respectively) from memory after incrementing PC each time. Some opcodes will require additional memory accesses after fetching the instruction, to either read or write data in memory. The MC can load its internal address register from the data bus one byte at a time using the lower byte of its internal address wires, filling in either the high byte or the low byte, or filling out the whole address directly from an address register. The Decoder will determine the data source of each byte, and use the MC's write wires accordingly.

* MC_WRITE_LOW - Load address low byte from data bus
* MC_WRITE_HIGH - Load address high byte from data bus
* MC_WRITE_FULL - Load full address from address register demux, selected from BC, PC, SP, or DD

The address register is directly connected to the external address bus, with the Read and Write pins controlling when the address should be interpreted as complete by anything on the bus. The MC does not directly control these pins, but it does use them for timing. When reading from memory, the Decoder will control the Read pin which will pulse for a clock cycle, and the MC will read from the external data bus and load the value into its internal data register, where it can be routed to the internal data bus. The MC_WRITE_DATA wire is used by the Decoder to have the MC route the internal data bus to the external data bus through its internal data register so that the desired output value will be in place for the subsequent pulse of the Write pin, also done by the Decoder.

### Instruction Decoder
The Decoder acts as the main executive of the processor, reading the opcode into its internal register, and then controlling how each half-cycle of the instruction is handled. It provides the selections for all muxes and demuxes connected to the internal buses, as well as the controls for the Arithmetic-Logic Unit (ALU). The Decoder handles the timing of the Read and Write pins, as well as signaling with the MC to read from the internal data bus or load from an address register.

### Arithmetic-Logic Unit
The Arithmetic-Logic Unit (ALU) handles all unary and binary operations performed by the processor. It has primary and secondary inputs that can be values taken from registers or the internal data bus, and then outputs to the internal data bus, where the result can be routed to a register, including the MC data register for writing to memory. The Decoder will handle the demuxing of the inputs, and the muxing of the output once the ALU completes its operation. The ALU will handle the following operations.

Unary (secondary input ignored):
* Pass through
* Shift left
* Shift right

Binary:
* Compare
* Add
* Subtract
* Or
* And
* Exclusive Or

The output of the ALU can also be inverted as an extra selection beyond the operation selection. The ALU not only outputs a result to the data bus, it also sets the status bits based on that result.

## Instruction Set Architecture
The opcodes for ROCKET88 follow a consistent pattern based on their addressing mode and behavior. To see the Instruction Set Architecture (ISA) organized in a tabular form, see the [spreadsheet](Rocket88.ods) in this repo. While some instructions in the ISA have unique behavior and arbitrary placement in the opcode table, the majority are have opcodes that are encoded according to their behavior. The basic structure of most opcodes are as follows.

| Bit:   | 7   | 6 | 5 | 4 |    3   |      2    |     1    |    0   |
|--------|-----|---|---|---|--------|-----------|----------|--------|
| Field: | Operation | | | | Option | Source/Destination Addressing |

The lower 3 bits determine the addressing mode for the opcode, and that will not only determine how data is routed through the processor, but also how many operand bytes will follow the opcode in the program. Most opcodes stand alone and have no operands, but those using the immediate or direct addressing modes will have one or two bytes of operands following the opcode that will need to be fetched to execute the full instruction.

### Addressing Modes
ROCKET88 supports 8 addressing modes, not including fully intrinsic opcodes that have no relevant addressing. This section lists them in the order based on the the 3-bit encoding for them that usually make up the lower 3 bits of the opcode. This section also discusses the assembly language mnemonics for these modes, but that will be also be covered in the reference entries for all instructions.

#### Zero (0)
The Zero mode is not only named after its value in the addressing bits, but also for the immediate value that it represents, namely zero. Rather than requiring the use of the immediate mode to specify zero as an operand, it can just be encoded in the opcode, and the extra byte of operand data will not need to be fetched. It also means that a register doesn't have to be used to contain the value of zero just for the sake of a binary operation, like a comparison.

The mnemonics of Zero mode are flexible. Instructions may use either a dedicated instruction mnemonic or use the immediate mnemonic with a **#0** operand, and the assembler will automatically choose the Zero mode opcode instead of the Immediate opcode followed by a zero byte.

#### A Register (1)
The A Register mode will use the value in the A register as an operand source or the destination of the operation result. This will always be an implicit opcode and require no operands.

The mnemonic will be to simply have A as the assembly operand to specify this mode.

#### B Register (2), C Register (3)
The B and C registers can also be addressed in the same manner as the A register.

#### Immediate (4)
Immediate addressing will have a single byte as the operand value inline with the code, rather than fetching it from a register or elsewhere in memory. This will require an additional single byte in the code after the opcode, so all instructions using this mode will need to advance the PC by two bytes instead of just one.

The mnemonic for this mode is to precede the immediate value with a hash symbol (#) to indicate that it is a number to be taken at face value and not an address or offset.

#### Relative (4)
For jump instructions, there is no purpose for Immediate addressing, so instead jump opcodes that are have immediate encoding actually use relative addressing, which requires a single byte operand, just like immediate mode. However, this value will be a signed offset that will be added to the PC if the jump condition is met.

The mnemonic for this is to use a label, and the assembler will calculate the offset to use for machine code. If the address that label resolves to is too far away from the current PC (more than 128 bytes before, or 127 bytes after), then this will be an assembly error.

#### Absolute (5)
Absolute addressing will have a 16-bit (two bytes, little endian) address as an operand, and may require a read from or write to that address to execute the instruction. At any rate, three bytes need to be fetched to get the opcode and address operand, advancing the PC by three.

The mnemonic for this mode is to simply have the address value with no extra punctuation, like a hash or parentheses.

#### Indirect (6)
Indirect addressing lets you use BC as an address register, and reference data at the address in BC. This means that there is no need to have an operand after the opcode, making it implicit like direct register addressing.

The mnemonic for this mode is to have BC in parentheses instead of a fixed address.

#### Stack (7)
Stack addressing uses the stack pointer to reference the current top of the stack. As the stack pointer is a dedicated register, opcodes using this mode are implicit.

The mnemonic for this mode is to have SP in parenteses, but some instructions (like PHA) that only support this mode will not require any assembly operand.

### Status Flags

