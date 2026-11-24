// Rocket88 - A New 8-Bit Architecture
// Module: r88_pll
// Description: Clock generation for the Rocket88 system on Cyclone IV E
// See https://github.com/SlithyMatt/rocket88 for current code and documentation
//
// clk is the 50 MHz system clock. sdram_clk is the same frequency, 3 ns
// earlier, which centers the SDRAM command and read data timing on the
// system clock edges (see r88_sdram.v). If the SDRAM is unreliable on a
// particular board, this phase is the setting to adjust.
//
// For simulation, define SIMULATION to use a behavioral model instead of
// the Altera PLL.

module r88_pll (
	input inclk,				// 50 MHz from the board
	output clk,					// 50 MHz system clock
	output sdram_clk,			// 50 MHz, -3 ns, for the SDRAM's clock pin
	output locked
);

`ifdef SIMULATION

reg early = 1'b0;
always @(inclk) early <= #17 inclk;		// 17 ns late = 3 ns early at 20 ns
assign clk = inclk;
assign sdram_clk = early;
reg [3:0] lock_count = 4'd0;
always @(posedge inclk) if (lock_count != 4'd15) lock_count <= lock_count + 4'd1;
assign locked = (lock_count == 4'd15);

`else

wire [4:0] pll_clk;
assign clk = pll_clk[0];
assign sdram_clk = pll_clk[1];

altpll #(
	.bandwidth_type("AUTO"),
	.clk0_divide_by(1),
	.clk0_duty_cycle(50),
	.clk0_multiply_by(1),
	.clk0_phase_shift("0"),
	.clk1_divide_by(1),
	.clk1_duty_cycle(50),
	.clk1_multiply_by(1),
	.clk1_phase_shift("-3000"),
	.compensate_clock("CLK0"),
	.inclk0_input_frequency(20000),
	.intended_device_family("Cyclone IV E"),
	.lpm_hint("CBX_MODULE_PREFIX=r88_pll"),
	.lpm_type("altpll"),
	.operation_mode("NORMAL"),
	.pll_type("AUTO"),
	.port_activeclock("PORT_UNUSED"),
	.port_areset("PORT_UNUSED"),
	.port_clkbad0("PORT_UNUSED"),
	.port_clkbad1("PORT_UNUSED"),
	.port_clkloss("PORT_UNUSED"),
	.port_clkswitch("PORT_UNUSED"),
	.port_configupdate("PORT_UNUSED"),
	.port_fbin("PORT_UNUSED"),
	.port_inclk0("PORT_USED"),
	.port_inclk1("PORT_UNUSED"),
	.port_locked("PORT_USED"),
	.port_pfdena("PORT_UNUSED"),
	.port_phasecounterselect("PORT_UNUSED"),
	.port_phasedone("PORT_UNUSED"),
	.port_phasestep("PORT_UNUSED"),
	.port_phaseupdown("PORT_UNUSED"),
	.port_pllena("PORT_UNUSED"),
	.port_scanaclr("PORT_UNUSED"),
	.port_scanclk("PORT_UNUSED"),
	.port_scanclkena("PORT_UNUSED"),
	.port_scandata("PORT_UNUSED"),
	.port_scandataout("PORT_UNUSED"),
	.port_scandone("PORT_UNUSED"),
	.port_scanread("PORT_UNUSED"),
	.port_scanwrite("PORT_UNUSED"),
	.port_clk0("PORT_USED"),
	.port_clk1("PORT_USED"),
	.port_clk2("PORT_UNUSED"),
	.port_clk3("PORT_UNUSED"),
	.port_clk4("PORT_UNUSED"),
	.port_clk5("PORT_UNUSED"),
	.port_clkena0("PORT_UNUSED"),
	.port_clkena1("PORT_UNUSED"),
	.port_clkena2("PORT_UNUSED"),
	.port_clkena3("PORT_UNUSED"),
	.port_clkena4("PORT_UNUSED"),
	.port_clkena5("PORT_UNUSED"),
	.port_extclk0("PORT_UNUSED"),
	.port_extclk1("PORT_UNUSED"),
	.port_extclk2("PORT_UNUSED"),
	.port_extclk3("PORT_UNUSED"),
	.self_reset_on_loss_lock("OFF"),
	.width_clock(5)
) altpll_component (
	.inclk({1'b0, inclk}),
	.clk(pll_clk),
	.locked(locked),
	.activeclock(),
	.areset(1'b0),
	.clkbad(),
	.clkena({6{1'b1}}),
	.clkloss(),
	.clkswitch(1'b0),
	.configupdate(1'b0),
	.enable0(),
	.enable1(),
	.extclk(),
	.extclkena({4{1'b1}}),
	.fbin(1'b1),
	.fbmimicbidir(),
	.fbout(),
	.fref(),
	.icdrclk(),
	.pfdena(1'b1),
	.phasecounterselect({4{1'b1}}),
	.phasedone(),
	.phasestep(1'b1),
	.phaseupdown(1'b1),
	.pllena(1'b1),
	.scanaclr(1'b0),
	.scanclk(1'b0),
	.scanclkena(1'b1),
	.scandata(1'b0),
	.scandataout(),
	.scandone(),
	.scanread(1'b0),
	.scanwrite(1'b0),
	.sclkout0(),
	.sclkout1(),
	.vcooverrange(),
	.vcounderrange()
);

`endif

endmodule
