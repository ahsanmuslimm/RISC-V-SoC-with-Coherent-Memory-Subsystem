#!/bin/bash

# =====================================================================
# F4PGA Build Script for RISC-V SoC on Arty A7-100T
# =====================================================================
# Purpose: Complete build pipeline for open-source FPGA toolchain
# Target: Arty A7-100T (XC7A100T)
# Toolchain: F4PGA (Yosys, nextpnr-xilinx, f4pga tools)
#
# Usage:
#   bash build.sh              # Full build
#   bash build.sh --synthesis  # Synthesis only
#   bash build.sh --pnr        # Place & Route only
#   bash build.sh --program    # Program FPGA
#   bash build.sh --clean      # Clean artifacts

set -e  # Exit on error

# =====================================================================
# CONFIGURATION
# =====================================================================

PROJECT_NAME="riscv_soc_arty100t"
TARGET_BOARD="arty-a7-100t"
DEVICE="xc7a100t_test"
PART="XC7A100T-CSG324"

RTL_DIR="../../rtl"
CONSTRAINTS_DIR="../../constraints"
BUILD_DIR="build"
REPORTS_DIR="${BUILD_DIR}/reports"

# Tools
YOSYS=${YOSYS:-yosys}
NEXTPNR=${NEXTPNR:-nextpnr-xilinx}
OPENOCD=${OPENOCD:-openocd}

# F4PGA environment
F4PGA_INSTALL_DIR="${F4PGA_INSTALL_DIR:-/opt/f4pga}"
PART_YAML="${F4PGA_INSTALL_DIR}/share/f4pga/xc7a100t_test/utils/xc7a100t_test.yaml"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# =====================================================================
# FUNCTIONS
# =====================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_tools() {
    log_info "Checking required tools..."
    
    for tool in ${YOSYS} ${NEXTPNR}; do
        if ! command -v ${tool} &> /dev/null; then
            log_error "${tool} not found"
            log_info "Install F4PGA: https://github.com/chipsalliance/f4pga-examples"
            exit 1
        fi
    done
    
    log_info "✓ All required tools found"
}

setup_build_dir() {
    log_info "Setting up build directory..."
    mkdir -p ${BUILD_DIR}
    mkdir -p ${REPORTS_DIR}
    log_info "✓ Build directory ready: ${BUILD_DIR}/"
}

run_synthesis() {
    log_info "Running synthesis with Yosys..."
    
    ${YOSYS} -m ghdl << EOF
        read_verilog ${RTL_DIR}/core/*.sv
        read_verilog ${RTL_DIR}/memory/*.sv
        read_verilog ${RTL_DIR}/cache/*.sv
        read_verilog ${RTL_DIR}/coherence/*.sv
        read_verilog ${RTL_DIR}/bus/*.sv
        read_verilog ${RTL_DIR}/peripheral/*.sv
        read_verilog ${RTL_DIR}/top/*.sv
        
        hierarchy -check -top riscv_soc_top
        proc
        opt_clean -purge
        
        synth_xilinx -flatten -json ${BUILD_DIR}/${PROJECT_NAME}.json
        
        stat -json ${REPORTS_DIR}/synth_stat.json
EOF
    
    if [ -f "${BUILD_DIR}/${PROJECT_NAME}.json" ]; then
        log_info "✓ Synthesis complete"
        ls -lh ${BUILD_DIR}/${PROJECT_NAME}.json
    else
        log_error "Synthesis failed: JSON not generated"
        exit 1
    fi
}

run_pnr() {
    log_info "Running place & route with nextpnr..."
    
    if [ ! -f "${BUILD_DIR}/${PROJECT_NAME}.json" ]; then
        log_error "JSON file not found, run synthesis first"
        exit 1
    fi
    
    # Check for constraints
    if [ -f "${CONSTRAINTS_DIR}/arty100t.xdc" ]; then
        log_info "Using constraints: ${CONSTRAINTS_DIR}/arty100t.xdc"
        CONSTRAINT_OPT="--xdc ${CONSTRAINTS_DIR}/arty100t.xdc"
    else
        log_warn "No constraints file found at ${CONSTRAINTS_DIR}/arty100t.xdc"
        CONSTRAINT_OPT=""
    fi
    
    ${NEXTPNR} --json ${BUILD_DIR}/${PROJECT_NAME}.json \
              ${CONSTRAINT_OPT} \
              --xact_map ${PART_YAML} \
              --device ${DEVICE} \
              --write ${BUILD_DIR}/${PROJECT_NAME}.net.json \
              --seed 42 \
              --timing-allow-fail
    
    if [ -f "${BUILD_DIR}/${PROJECT_NAME}.net.json" ]; then
        log_info "✓ Place & Route complete"
        ls -lh ${BUILD_DIR}/${PROJECT_NAME}.net.json
    else
        log_error "Place & Route failed: netlist not generated"
        exit 1
    fi
}

generate_bitstream() {
    log_info "Generating FPGA bitstream..."
    
    if [ ! -f "${BUILD_DIR}/${PROJECT_NAME}.net.json" ]; then
        log_error "Netlist file not found, run PnR first"
        exit 1
    fi
    
    # Try F4PGA tools if available
    if command -v f4pga &> /dev/null; then
        log_info "Using F4PGA for bitstream generation"
        
        f4pga pack -e ${PART_YAML} \
                 -d ${DEVICE} \
                 -s ${BUILD_DIR}/${PROJECT_NAME}.eblif \
                 ${BUILD_DIR}/${PROJECT_NAME}.net.json
        
        f4pga place -e ${PART_YAML} \
                  -d ${DEVICE} \
                  -n ${BUILD_DIR}/${PROJECT_NAME}.net.json \
                  -p ${BUILD_DIR}/${PROJECT_NAME}.place
        
        f4pga route -e ${PART_YAML} \
                  -d ${DEVICE} \
                  -s ${BUILD_DIR}/${PROJECT_NAME}.route
        
        f4pga write_bitstream -e ${PART_YAML} \
                           -d ${DEVICE} \
                           -b ${BUILD_DIR}/${PROJECT_NAME}.bit
    else
        log_warn "F4PGA not found, skipping bitstream generation"
        log_info "Bitstream generation requires F4PGA tools"
        return 1
    fi
    
    if [ -f "${BUILD_DIR}/${PROJECT_NAME}.bit" ]; then
        log_info "✓ Bitstream generated"
        ls -lh ${BUILD_DIR}/${PROJECT_NAME}.bit
    else
        log_error "Bitstream generation failed"
        return 1
    fi
}

program_fpga() {
    log_info "Programming FPGA via JTAG..."
    
    BITSTREAM="${BUILD_DIR}/${PROJECT_NAME}.bit"
    
    if [ ! -f "${BITSTREAM}" ]; then
        log_error "Bitstream file not found: ${BITSTREAM}"
        exit 1
    fi
    
    if command -v openocd &> /dev/null; then
        log_info "Using OpenOCD for JTAG programming"
        
        openocd -f board/arty_a7.cfg \
               -c "init" \
               -c "pld load 0 ${BITSTREAM}" \
               -c "exit"
        
        log_info "✓ FPGA programming complete"
    else
        log_warn "OpenOCD not found, cannot program FPGA"
        log_info "Install OpenOCD or use: vivado_lab -source program.tcl"
        exit 1
    fi
}

full_build() {
    log_info "Starting full build (synthesis + PnR + bitstream)..."
    check_tools
    setup_build_dir
    run_synthesis
    run_pnr
    generate_bitstream || log_warn "Bitstream generation skipped (F4PGA not available)"
    log_info "✓ Full build complete!"
}

clean_build() {
    log_info "Cleaning build artifacts..."
    rm -rf ${BUILD_DIR}
    log_info "✓ Clean complete"
}

show_help() {
    cat << EOF
F4PGA Build Script for RISC-V SoC on Arty A7-100T

Usage:
  bash build.sh [OPTION]

Options:
  (none)           Full build (synthesis + PnR + bitstream)
  --synthesis      Run synthesis only (Yosys)
  --pnr            Run place & route only (nextpnr)
  --bitstream      Generate bitstream (F4PGA tools)
  --program        Program FPGA over JTAG (OpenOCD)
  --clean          Remove build artifacts
  --check          Check tools availability
  --help           Show this help

Configuration:
  TARGET_BOARD:  ${TARGET_BOARD}
  DEVICE:        ${DEVICE}
  PART:          ${PART}
  BUILD_DIR:     ${BUILD_DIR}
  F4PGA_DIR:     ${F4PGA_INSTALL_DIR}

Examples:
  bash build.sh                 # Full build
  bash build.sh --synthesis     # Synthesis only
  bash build.sh --pnr           # Place & route only
  bash build.sh --program       # Program FPGA

For more info: https://github.com/chipsalliance/f4pga
EOF
}

# =====================================================================
# MAIN
# =====================================================================

case "${1:-}" in
    --synthesis)
        check_tools
        setup_build_dir
        run_synthesis
        ;;
    --pnr)
        setup_build_dir
        run_pnr
        ;;
    --bitstream)
        generate_bitstream
        ;;
    --program)
        program_fpga
        ;;
    --clean)
        clean_build
        ;;
    --check)
        check_tools
        ;;
    --help)
        show_help
        ;;
    *)
        full_build
        ;;
esac

log_info "Done!"

