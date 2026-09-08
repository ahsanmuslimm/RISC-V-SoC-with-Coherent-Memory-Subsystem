# =====================================================================
# pnr.sdc — riscv_soc_top
# Used by LibreLane during floorplan/placement/CTS/routing
# (config.yaml: PNR_SDC_FILE). Intentionally carries a little extra
# clock-uncertainty margin vs. signoff.sdc so PnR optimizes to a
# slightly harder target than what sign-off actually requires.
#
# Clock: 20 MHz (50 ns period), sky130A start point per
# docs/DECISIONS.md item T4 ("20 MHz start, tighten if it closes").
# =====================================================================

current_design riscv_soc_top

# ---------------------------------------------------------------------
# Primary clock
# ---------------------------------------------------------------------
create_clock -name clk -period 50.0 [get_ports clk]

set_clock_uncertainty -setup 2.5  [get_clocks clk]
set_clock_uncertainty -hold  0.25 [get_clocks clk]
set_clock_transition  0.15        [get_clocks clk]

# ---------------------------------------------------------------------
# Reset: single async active-low rst_n, 2-FF synchronized internally
# (docs/DECISIONS.md D6). The primary input's arrival time relative
# to clk has no meaning — only the internal synchronizer chain matters,
# and that's a normal register path already covered by create_clock.
# ---------------------------------------------------------------------
set_false_path -from [get_ports rst_n]

# ---------------------------------------------------------------------
# I/O timing — UART (external serial link, 115200 8N1) and GPIO LEDs.
# Placeholder board-level budget until real pad/package timing is
# available; treat as external-device-facing I/O, not chip-to-chip.
# ---------------------------------------------------------------------
set_input_delay  -clock clk -max 10.0 [get_ports uart_rx]
set_input_delay  -clock clk -min  1.0 [get_ports uart_rx]

set_output_delay -clock clk -max 10.0 [get_ports uart_tx]
set_output_delay -clock clk -min  1.0 [get_ports uart_tx]

set_output_delay -clock clk -max 10.0 [get_ports {led[*]}]
set_output_delay -clock clk -min  1.0 [get_ports {led[*]}]

# ---------------------------------------------------------------------
# Boundary loads / drive — conservative placeholders for an
# off-chip-facing pad; replace once package/board parasitics are known.
# ---------------------------------------------------------------------
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_4 -pin X [get_ports uart_rx]
set_load 0.05 [all_outputs]

set_max_fanout 8 [current_design]
