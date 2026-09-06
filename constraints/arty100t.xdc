# =====================================================================
# XDC Constraints for Arty A7-100T FPGA Board
# =====================================================================
# Purpose: Pin and timing constraints for RISC-V SoC on Arty A7-100T
# Board: Digilent Arty A7-100T (XC7A100T-CSG324)
# Toolchain: F4PGA/nextpnr-xilinx
#
# Pins:
#   - CLK: 100 MHz system clock (on-board oscillator)
#   - RST: Reset button
#   - UART TX/RX: Serial communication
#   - LED[7:0]: 8 LEDs for output
#   - BTN[3:0]: 4 buttons (optional input)

# =====================================================================
# CLOCK CONSTRAINTS
# =====================================================================

# System clock: 100 MHz oscillator on Arty A7-100T
# Pin: E3 (labeled CLK100MHZ on board)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

# =====================================================================
# RESET CONSTRAINTS
# =====================================================================

# Reset button (active-low): C2 on Arty A7-100T
set_property -dict { PACKAGE_PIN C2    IOSTANDARD LVCMOS33 } [get_ports rst_n]
set_property PULLUP true [get_ports rst_n]

# =====================================================================
# UART INTERFACE (Serial Communication)
# =====================================================================

# UART TX (output from FPGA to CH340 USB-UART)
# Pin: D10 on Arty A7-100T
set_property -dict { PACKAGE_PIN D10   IOSTANDARD LVCMOS33 } [get_ports uart_tx]

# UART RX (input to FPGA from CH340 USB-UART)
# Pin: A9 on Arty A7-100T
set_property -dict { PACKAGE_PIN A9    IOSTANDARD LVCMOS33 } [get_ports uart_rx]

# =====================================================================
# LED OUTPUTS
# =====================================================================

# LED[0]: LD4 (Red)
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports led[0]]

# LED[1]: LD5 (Green)
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports led[1]]

# LED[2]: LD6 (Blue)
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports led[2]]

# LED[3]: LD7 (Red)
set_property -dict { PACKAGE_PIN G13   IOSTANDARD LVCMOS33 } [get_ports led[3]]

# LED[4–7]: Reserved for future use (can be extended)
# Currently mapped to unused pins on Arty A7-100T

set_property -dict { PACKAGE_PIN D13   IOSTANDARD LVCMOS33 } [get_ports led[4]]
set_property -dict { PACKAGE_PIN B14   IOSTANDARD LVCMOS33 } [get_ports led[5]]
set_property -dict { PACKAGE_PIN F14   IOSTANDARD LVCMOS33 } [get_ports led[6]]
set_property -dict { PACKAGE_PIN C14   IOSTANDARD LVCMOS33 } [get_ports led[7]]

# =====================================================================
# BUTTON INPUTS (Optional)
# =====================================================================

# BTN[0]: D9 (Center button)
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports btn[0]]
set_property PULLUP true [get_ports btn[0]]

# BTN[1]: C9 (Left button)
set_property -dict { PACKAGE_PIN C9    IOSTANDARD LVCMOS33 } [get_ports btn[1]]
set_property PULLUP true [get_ports btn[1]]

# BTN[2]: B9 (Right button)
set_property -dict { PACKAGE_PIN B9    IOSTANDARD LVCMOS33 } [get_ports btn[2]]
set_property PULLUP true [get_ports btn[2]]

# BTN[3]: B10 (Down button)
set_property -dict { PACKAGE_PIN B10   IOSTANDARD LVCMOS33 } [get_ports btn[3]]
set_property PULLUP true [get_ports btn[3]]

# =====================================================================
# PMOD HEADERS (Optional for future expansion)
# =====================================================================

# Note: Arty A7-100T has 4 PMOD connectors (PMOD A, B, C, D)
# Each PMOD has 8 pins (4 I/O + 4 GND)
#
# Example: PMOD A1 (J1 connector)
# set_property -dict { PACKAGE_PIN C17   IOSTANDARD LVCMOS33 } [get_ports pmod_a[0]]
# set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports pmod_a[1]]
# etc.

# =====================================================================
# TIMING CONSTRAINTS
# =====================================================================

# Input delay on asynchronous inputs (reset, buttons)
set_input_delay -clock sys_clk_pin 0 [get_ports rst_n]
set_input_delay -clock sys_clk_pin 0 [get_ports btn]

# Output delay on outputs
set_output_delay -clock sys_clk_pin 0 [get_ports uart_tx]
set_output_delay -clock sys_clk_pin 0 [get_ports led]

# =====================================================================
# BITSTREAM GENERATION SETTINGS
# =====================================================================

# Bitstream configuration
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]

# =====================================================================
# POWER & SLEW CONSTRAINTS
# =====================================================================

# All I/O: LVCMOS33 (3.3V logic)
# Slew rate: fast (for LED outputs)
set_property SLEW FAST [get_ports led*]
set_property DRIVE 12 [get_ports led*]

# Slew rate: slow (for low EMI)
set_property SLEW SLOW [get_ports uart_tx]
set_property DRIVE 8 [get_ports uart_tx]

# =====================================================================
# NOTES FOR NEXT PNR TOOL
# =====================================================================

# This XDC file is compatible with:
#   - Xilinx Vivado (proprietary)
#   - nextpnr-xilinx (open-source F4PGA)
#
# Pin numbering reference (Arty A7-100T CSG324 package):
#   - Row 0–7 (A–H)
#   - Column 1–24
#
# For full pinout: https://reference.digilentinc.com/reference/programmable-logic/arty-a7/reference

