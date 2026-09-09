###############################################################################
# Created by write_sdc
###############################################################################
current_design riscv_soc_top
###############################################################################
# Timing Constraints
###############################################################################
create_clock -name clk -period 50.0000 [get_ports {clk}]
set_clock_transition 0.1500 [get_clocks {clk}]
set_clock_uncertainty -setup 2.5000 clk
set_clock_uncertainty -hold 0.2500 clk
set_propagated_clock [get_clocks {clk}]
set_input_delay 1.0000 -clock [get_clocks {clk}] -min -add_delay [get_ports {uart_rx}]
set_input_delay 10.0000 -clock [get_clocks {clk}] -max -add_delay [get_ports {uart_rx}]
set_output_delay 1.0000 -clock [get_clocks {clk}] -min -add_delay [get_ports {led[0]}]
set_output_delay 10.0000 -clock [get_clocks {clk}] -max -add_delay [get_ports {led[0]}]
set_output_delay 1.0000 -clock [get_clocks {clk}] -min -add_delay [get_ports {led[1]}]
set_output_delay 10.0000 -clock [get_clocks {clk}] -max -add_delay [get_ports {led[1]}]
set_output_delay 1.0000 -clock [get_clocks {clk}] -min -add_delay [get_ports {led[2]}]
set_output_delay 10.0000 -clock [get_clocks {clk}] -max -add_delay [get_ports {led[2]}]
set_output_delay 1.0000 -clock [get_clocks {clk}] -min -add_delay [get_ports {led[3]}]
set_output_delay 10.0000 -clock [get_clocks {clk}] -max -add_delay [get_ports {led[3]}]
set_output_delay 1.0000 -clock [get_clocks {clk}] -min -add_delay [get_ports {led[4]}]
set_output_delay 10.0000 -clock [get_clocks {clk}] -max -add_delay [get_ports {led[4]}]
set_output_delay 1.0000 -clock [get_clocks {clk}] -min -add_delay [get_ports {led[5]}]
set_output_delay 10.0000 -clock [get_clocks {clk}] -max -add_delay [get_ports {led[5]}]
set_output_delay 1.0000 -clock [get_clocks {clk}] -min -add_delay [get_ports {led[6]}]
set_output_delay 10.0000 -clock [get_clocks {clk}] -max -add_delay [get_ports {led[6]}]
set_output_delay 1.0000 -clock [get_clocks {clk}] -min -add_delay [get_ports {led[7]}]
set_output_delay 10.0000 -clock [get_clocks {clk}] -max -add_delay [get_ports {led[7]}]
set_output_delay 1.0000 -clock [get_clocks {clk}] -min -add_delay [get_ports {uart_tx}]
set_output_delay 10.0000 -clock [get_clocks {clk}] -max -add_delay [get_ports {uart_tx}]
set_false_path\
    -from [get_ports {rst_n}]
###############################################################################
# Environment
###############################################################################
set_load -pin_load 0.0500 [get_ports {uart_tx}]
set_load -pin_load 0.0500 [get_ports {led[7]}]
set_load -pin_load 0.0500 [get_ports {led[6]}]
set_load -pin_load 0.0500 [get_ports {led[5]}]
set_load -pin_load 0.0500 [get_ports {led[4]}]
set_load -pin_load 0.0500 [get_ports {led[3]}]
set_load -pin_load 0.0500 [get_ports {led[2]}]
set_load -pin_load 0.0500 [get_ports {led[1]}]
set_load -pin_load 0.0500 [get_ports {led[0]}]
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_4 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {uart_rx}]
###############################################################################
# Design Rules
###############################################################################
set_max_fanout 8.0000 [current_design]
