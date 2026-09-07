# =====================================================================
# OpenLane Configuration for RISC-V SoC Physical Design (Day 4 T4.10–T4.13)
# =====================================================================
# Purpose: Configuration for open-source ASIC flow (OpenLane)
# Technology: sky130_fd_sc_hd (130 nm, foundry process)
# Design: riscv_soc_top (18 modules, 4,465 RTL lines)
#
# Reference: https://github.com/The-OpenROAD-Project/OpenLane
#
# Stages:
#   1. RTL2GDS flow
#   2. Synthesis (Yosys)
#   3. Placement & Routing (OpenROAD)
#   4. Power delivery network (PDN)
#   5. Signal integrity (STA)
#   6. DRC/LVS verification
#
# Output:
#   - GDS (layout file)
#   - DEF (placement file)
#   - Timing report
#   - Power report
#   - Area estimate

# =====================================================================
# DESIGN SPECIFICATIONS
# =====================================================================

set ::env(DESIGN_NAME) "riscv_soc_top"
set ::env(VERILOG_FILES) [glob $::env(DESIGN_DIR)/rtl/**/*.sv]
set ::env(SYNTH_DEFINES) ""

# Design path and macro library
set ::env(DESIGN_DIR) "."
set ::env(MACROS) ""

# =====================================================================
# PLATFORM AND TECHNOLOGY
# =====================================================================

set ::env(PDK) "sky130A"
set ::env(STD_CELL_LIBRARY) "sky130_fd_sc_hd"
set ::env(CLOCK_PERIOD) "20"      # 50 MHz (20 ns period)
set ::env(CLOCK_PORT) "clk"

# =====================================================================
# FLOORPLAN & AREA
# =====================================================================

# Core area: 400K µm² (estimated from gate count)
# Aspect ratio: 1.0 (square)
# Margin: 20% for routing

set ::env(FP_CORE_UTIL) "50"       # 50% utilization (conservative)
set ::env(FP_ASPECT_RATIO) "1.0"   # Square floorplan
set ::env(FP_CORE_MARGIN) "5"      # 5µm margin

# Power distribution network (PDN)
set ::env(FP_PDN_CORE_RING) "1"
set ::env(FP_PDN_RAILS_LAYER) "met1"
set ::env(FP_PDN_CORE_RING_LAYER) "met2"

# =====================================================================
# SYNTHESIS SETTINGS
# =====================================================================

set ::env(SYNTH_STRATEGY) "AREA 0"          # Optimize for area
set ::env(SYNTH_NO_FLAT) "0"                # Flatten hierarchy
set ::env(SYNTH_SPLITNETS) "0"              # No net splitting
set ::env(SYNTH_BUFFERING) "1"              # Add buffers for timing
set ::env(SYNTH_SIZING) "1"                 # Upsize gates for timing
set ::env(SYNTH_MAX_FANOUT) "10"            # Max fanout per gate
set ::env(SYNTH_READ_BLACKBOX_LIB) "1"      # Read blackbox modules

# =====================================================================
# PLACEMENT SETTINGS
# =====================================================================

set ::env(PLACE_DENSITY) "0.6"              # Placement density
set ::env(PLACE_SITE) "unithd"              # sky130 unit height
set ::env(PLACE_PINS_LAYER) "met2"          # Pin layer

# =====================================================================
# ROUTING SETTINGS
# =====================================================================

set ::env(ROUTING_LAYER_ADJUSTMENT) "0.5"   # Reduce layer congestion
set ::env(GRT_OVERFLOW_ITERS) "50"          # Global routing iterations
set ::env(DETAILED_ROUTER) "tritonRoute"    # Detailed router

# =====================================================================
# TIMING & OPTIMIZATION
# =====================================================================

set ::env(CLOCK_NETS) "$::env(CLOCK_PORT)"
set ::env(PL_TIME_DRIVEN) "1"               # Timing-driven placement
set ::env(PL_RESIZER_DESIGN_OPTIMIZATIONS) "1"  # Resizing for timing
set ::env(GLB_RESIZER_TIMING_OPTIMIZATIONS) "1"

# =====================================================================
# DRC/LVS & VERIFICATION
# =====================================================================

set ::env(RUN_MAGIC_DRC) "1"                # Run Magic DRC
set ::env(RUN_NETGEN_LVS) "1"               # Run Netgen LVS
set ::env(MAGIC_DRC_USE_GDS) "1"            # Use GDS for DRC
set ::env(RUN_CVC) "1"                      # Run CVC for connectivity

# =====================================================================
# STA & POWER ANALYSIS
# =====================================================================

set ::env(RUN_OPENSTA) "1"                  # Run OpenSTA for timing
set ::env(RUN_POWER_REPORT) "1"             # Generate power report
set ::env(POWER_POINT) "1.80"               # Nominal 1.8V supply

# =====================================================================
# OUTPUT & REPORTING
# =====================================================================

set ::env(REPORT_RUNTIME) "1"               # Report runtime
set ::env(REPORT_DESIGN_METRICS) "1"        # Design metrics
set ::env(GDS_PATH) ""                      # Output GDS path
set ::env(DEF_PATH) ""                      # Output DEF path

# =====================================================================
# OPTIONAL CUSTOMIZATIONS
# =====================================================================

# Macro placement (if any SRAM macros added)
# set ::env(MACROS) [list sram_1kx32]

# Custom timing constraints
# set ::env(STA_REPORT_THRESHOLD) "0.5"

# Power gating (future enhancement)
# set ::env(POWER_GATING) "1"

