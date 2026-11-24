# Rocket88 computer: timing constraints for TimeQuest
#
# Clocks:
#   CLOCK_50   50 MHz board clock
#   sys_clk    PLL c0, 50 MHz system clock
#   sdram_clk  PLL c1, 50 MHz, -3 ns, to the SDRAM_CLK pin
#   cpu_clk    sys_clk / 16 (register system|cpu_clk_r), clocks the CPU core
#
# The CPU's bus is sampled and driven at fixed phases of its 16-clock slot
# (see system/r88_system.v), which the multicycle paths below describe.

create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]

create_generated_clock -name sys_clk \
	-source [get_pins {pll|altpll_component|auto_generated|pll1|inclk[0]}] \
	[get_pins {pll|altpll_component|auto_generated|pll1|clk[0]}]
create_generated_clock -name sdram_pll_clk -phase -54.0 \
	-source [get_pins {pll|altpll_component|auto_generated|pll1|inclk[0]}] \
	[get_pins {pll|altpll_component|auto_generated|pll1|clk[1]}]

derive_clock_uncertainty

# ---------------------------------------------------------------------------
# CPU clock
# ---------------------------------------------------------------------------
create_generated_clock -name cpu_clk -divide_by 16 \
	-source [get_pins {pll|altpll_component|auto_generated|pll1|clk[0]}] \
	[get_registers {*|cpu_clk_r}]

# The CPU's address, Read, Write and data are latched 5 system clocks after
# the CPU clock edge (phase 4 -> 5)
set_multicycle_path -from [get_clocks cpu_clk] -to [get_clocks sys_clk] -setup -end 5
set_multicycle_path -from [get_clocks cpu_clk] -to [get_clocks sys_clk] -hold -end 4

# Read data, IRQ and RESET for the CPU change 5 system clocks before the CPU
# clock edge (phase 10 -> 11)
set_multicycle_path -from [get_clocks sys_clk] -to [get_clocks cpu_clk] -setup -start 5
set_multicycle_path -from [get_clocks sys_clk] -to [get_clocks cpu_clk] -hold -start 4

# ---------------------------------------------------------------------------
# SDRAM (HY57V641620, CAS latency 2)
# ---------------------------------------------------------------------------
create_generated_clock -name sdram_clk_pin \
	-source [get_pins {pll|altpll_component|auto_generated|pll1|clk[1]}] \
	[get_ports SDRAM_CLK]

set sdram_outputs [get_ports {SDRAM_CKE SDRAM_CS_N SDRAM_RAS_N SDRAM_CAS_N SDRAM_WE_N SDRAM_BA[*] SDRAM_A[*] SDRAM_LDQM SDRAM_UDQM SDRAM_DQ[*]}]

# Input setup 1.5 ns and hold 0.8 ns, plus 0.5 ns of board trace
set_output_delay -clock sdram_clk_pin -max 2.0 $sdram_outputs
set_output_delay -clock sdram_clk_pin -min -0.8 $sdram_outputs

# Read data: valid from tAC (5.4 ns) after an SDRAM clock edge until tOH
# (2.7 ns) after the next one. The controller captures it on the system
# clock edge after the SDRAM edge that launched it.
set_input_delay -clock sdram_clk_pin -max 6.0 [get_ports {SDRAM_DQ[*]}]
set_input_delay -clock sdram_clk_pin -min 2.7 [get_ports {SDRAM_DQ[*]}]
set_multicycle_path -from [get_clocks sdram_clk_pin] -to [get_clocks sys_clk] -setup -end 2
set_multicycle_path -from [get_clocks sdram_clk_pin] -to [get_clocks sys_clk] -hold -end 1

# ---------------------------------------------------------------------------
# Slow or asynchronous I/O
# ---------------------------------------------------------------------------
# Synchronized inputs
set_false_path -from [get_ports {RESET_N KEY[*] PS2_*}]
# Outputs whose timing doesn't matter at this speed
set_false_path -to [get_ports {LED[*] DIG[*] SEG[*] BEEP PS2_* VGA_*}]
