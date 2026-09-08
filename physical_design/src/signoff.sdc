# =====================================================================
# signoff.sdc — riscv_soc_top
# Used by LibreLane for final post-route STA (config.yaml:
# SIGNOFF_SDC_FILE). Real numbers, no extra PnR optimization margin —
# this is what actually has to pass at 20 MHz / 50 ns for tapeout,
# per docs/DECISIONS.md item T4.
# =====================================================================

current_design riscv_soc_top

# ---------------------------------------------------------------------
# Primary clock
# ---------------------------------------------------------------------
create_clock -name clk -period 50.0 [get_ports clk]

set_clock_uncertainty -setup 1.5  [get_clocks clk]
set_clock_uncertainty -hold  0.15 [get_clocks clk]
set_clock_transition  0.15        [get_clocks clk]

# On-chip variation derating (typical sky130A signoff practice: apply
# +/-5% on cell delay for setup/hold pessimism).
set_timing_derate -early 0.95
set_timing_derate -late  1.05

# ---------------------------------------------------------------------
# Reset — see pnr.sdc; same rationale applies at sign-off.
# ---------------------------------------------------------------------
set_false_path -from [get_ports rst_n]

# ---------------------------------------------------------------------
# I/O timing — same external-facing budget as pnr.sdc, kept identical
# on purpose so a PnR result that met timing under pnr.sdc doesn't
# silently regress under signoff.sdc.
# ---------------------------------------------------------------------
set_input_delay  -clock clk -max 10.0 [get_ports uart_rx]
set_input_delay  -clock clk -min  1.0 [get_ports uart_rx]

set_output_delay -clock clk -max 10.0 [get_ports uart_tx]
set_output_delay -clock clk -min  1.0 [get_ports uart_tx]

set_output_delay -clock clk -max 10.0 [get_ports {led[*]}]
set_output_delay -clock clk -min  1.0 [get_ports {led[*]}]

set_driving_cell -lib_cell sky130_fd_sc_hd__buf_4 -pin X [get_ports uart_rx]
set_load 0.05 [all_outputs]

set_max_fanout 8 [current_design]
