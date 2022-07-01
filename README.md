# ROCKET88
## A New 8-Bit Architecture

**ROCKET88** -- **R**etro **O**bsolete **C**omputational **K**ernel for **E**lectronic **T**ransacting (Data Bus: **8**-Bit Internal, **8**-Bit External) -- is an virtual 8-bit architecture for modeled microprocessors, to run either in software emulation or programmable logic. As it is entirely unlikely that a custom silicon implementation will ever be created, this architecture will be free to evolve and have multiple community-developed variants, but ultimately there will be a reference design at https://github.com/SlithyMatt/rocket88 which will include this document, implementations of the architecture in Verilog and C++, and a simple computer system built around this architecture targeting specific FPGA development boards and a software emulator. This repo will take pull requests from the community, but it will be a complete free and open source project and the community is free to make any changes they like in their forks and incorporate it into other free and open source projects, as per the [license](LICENSE).

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
The Arithmetic-Logic Unit (ALU) handles all unary and binary operations performed by the processor. It has a primary and secondary inputs that can be take values from registers or the internal data bus, and then outputs to the internal data bus, where the result can be routed to a register, including the MC data register for writing to memory. The Decoder will handle the demuxing of the inputs, and the muxing of the output once the ALU completes its operation. The ALU will handle the following operations.

Unary (secondary input ignored):
* Pass through
