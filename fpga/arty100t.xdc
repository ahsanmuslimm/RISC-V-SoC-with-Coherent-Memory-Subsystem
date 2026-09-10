# =====================================================================
# XDC Constraints for Arty A7-100T FPGA Board
# =====================================================================
# Board: Digilent Arty A7-100T (XC7A100T-CSG324-1)
# Reference: Digilent Official Master XDC
#
# Pin Assignments:
#   - CLK: 100 MHz system clock (E3)
#   - RST: Reset button (C2)
#   - UART: Serial communication via USB-UART
#   - LED[3:0]: 4 User LEDs (LD4-LD7)
#   - BTN[3:0]: 4 Buttons (Center, Left, Right, Down)

# =====================================================================
# CLOCK CONSTRAINTS
# =====================================================================

# System clock: 100 MHz oscillator on Arty A7-100T
# Pin: E3 (CLK100MHZ)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

# =====================================================================
# RESET CONSTRAINTS
# =====================================================================

# Reset signal (active-low) - mapped to Arduino header pin C2
# Note: This is the ChipKit reset pin, can also be used as system reset
set_property -dict { PACKAGE_PIN C2    IOSTANDARD LVCMOS33 } [get_ports rst_n]
set_property PULLUP true [get_ports rst_n]

# =====================================================================
# UART INTERFACE (USB-UART)
# =====================================================================

# UART TX (FPGA → USB): Connected to RX on CH340
# Pin: D10
set_property -dict { PACKAGE_PIN D10   IOSTANDARD LVCMOS33 } [get_ports uart_tx]

# UART RX (USB → FPGA): Connected to TX on CH340
# Pin: A9
set_property -dict { PACKAGE_PIN A9    IOSTANDARD LVCMOS33 } [get_ports uart_rx]

# =====================================================================
# LED OUTPUTS (4 User LEDs on Arty A7-100T)
# =====================================================================

# LED[0]: LD4 (Green) - Pin H5
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports led[0]]

# LED[1]: LD5 (Green) - Pin J5
set_property -dict { PACKAGE_PIN J5    IOSTANDARD LVCMOS33 } [get_ports led[1]]

# LED[2]: LD6 (Green) - Pin T9
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports led[2]]

# LED[3]: LD7 (Green) - Pin T10
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports led[3]]

# =====================================================================
# BUTTON INPUTS (4 Push Buttons)
# =====================================================================

# BTN[0]: Center button - Pin D9 (separate from rst_n which is on C2)
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports btn[0]]
set_property PULLUP true [get_ports btn[0]]

# BTN[1]: Left button - Pin C9
set_property -dict { PACKAGE_PIN C9    IOSTANDARD LVCMOS33 } [get_ports btn[1]]
set_property PULLUP true [get_ports btn[1]]

# BTN[2]: Right button - Pin B9
set_property -dict { PACKAGE_PIN B9    IOSTANDARD LVCMOS33 } [get_ports btn[2]]
set_property PULLUP true [get_ports btn[2]]

# BTN[3]: Down button - Pin B8
set_property -dict { PACKAGE_PIN B8    IOSTANDARD LVCMOS33 } [get_ports btn[3]]
set_property PULLUP true [get_ports btn[3]]

# =====================================================================
# SWITCH INPUTS (4 Slide Switches - Optional)
# =====================================================================

# SW[0]: Pin A8
set_property -dict { PACKAGE_PIN A8    IOSTANDARD LVCMOS33 } [get_ports sw[0]]

# SW[1]: Pin C11
set_property -dict { PACKAGE_PIN C11   IOSTANDARD LVCMOS33 } [get_ports sw[1]]

# SW[2]: Pin C10
set_property -dict { PACKAGE_PIN C10   IOSTANDARD LVCMOS33 } [get_ports sw[2]]

# SW[3]: Pin A10
set_property -dict { PACKAGE_PIN A10   IOSTANDARD LVCMOS33 } [get_ports sw[3]]

# =====================================================================
# TIMING CONSTRAINTS
# =====================================================================

# Input delay on asynchronous inputs (rst_n on C2)
set_input_delay -clock sys_clk_pin 5 [get_ports rst_n]
set_input_delay -clock sys_clk_pin 0 [get_ports btn]
set_input_delay -clock sys_clk_pin 0 [get_ports sw]
set_input_delay -clock sys_clk_pin 0 [get_ports uart_rx]

# Output delay on outputs
set_output_delay -clock sys_clk_pin 0 [get_ports uart_tx]
set_output_delay -clock sys_clk_pin 0 [get_ports led]

# =====================================================================
# BITSTREAM GENERATION SETTINGS
# =====================================================================

# SPI configuration for programming
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]

# =====================================================================
# POWER & DRIVE STRENGTH
# =====================================================================

# LED outputs: Fast slew, higher drive
set_property SLEW FAST [get_ports led*]
set_property DRIVE 12 [get_ports led*]

# UART: Slower slew for signal integrity
set_property SLEW SLOW [get_ports uart_tx]
set_property DRIVE 8 [get_ports uart_tx]

# =====================================================================
# CONFIGURATION
# =====================================================================

# Set voltage standards
set_property INTERNAL_VREF 0.750 [get_iobanks 34]