#!/bin/bash

# =====================================================================
# RISC-V SoC Bitstream Generation - Quick Start Script
# =====================================================================
# Purpose: One-command setup and build for Arty A7-100T FPGA board
# Usage: bash quickstart-bitstream.sh [--program]
#
# What it does:
#   1. Verifies F4PGA environment
#   2. Sets up build directory
#   3. Runs full synthesis + P&R + bitstream generation
#   4. (Optional) Programs FPGA via JTAG
#
# Examples:
#   bash quickstart-bitstream.sh              # Build only
#   bash quickstart-bitstream.sh --program    # Build + program FPGA
#   bash quickstart-bitstream.sh --clean      # Clean build artifacts

set -e

# =====================================================================
# CONFIGURATION
# =====================================================================

PROJECT_ROOT="../../.."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
REPORTS_DIR="${BUILD_DIR}/reports"

PROJECT_NAME="riscv_soc_arty100t"
DEVICE="xc7a100t_test"
PART="XC7A100T-CSG324"
BOARD="arty-a7-100t"
TARGET="arty_100"

# F4PGA environment
F4PGA_INSTALL_DIR="${F4PGA_INSTALL_DIR:-${HOME}/opt/f4pga}"
FPGA_FAM="${FPGA_FAM:-xc7}"
PART_YAML="${F4PGA_INSTALL_DIR}/share/f4pga/${DEVICE}/utils/${DEVICE}.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =====================================================================
# UTILITY FUNCTIONS
# =====================================================================

log_info() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_section() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_success() {
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Verify environment
verify_environment() {
    log_section "Verifying F4PGA Environment"
    
    # Check if in correct directory
    if [ ! -f "Makefile" ] || [ ! -f "arty100t.xdc" ]; then
        log_error "Must run from fpga/f4pga directory"
        log_info "Run: cd fpga/f4pga && bash quickstart-bitstream.sh"
        exit 1
    fi
    log_info "Located in correct directory: $(pwd)"
    
    # Check F4PGA installation
    if [ ! -d "${F4PGA_INSTALL_DIR}" ]; then
        log_error "F4PGA not found at ${F4PGA_INSTALL_DIR}"
        log_warn "Install F4PGA first:"
        echo "  https://github.com/chipsalliance/f4pga/tree/main/docs"
        exit 1
    fi
    log_info "F4PGA found at: ${F4PGA_INSTALL_DIR}"
    
    # Check conda environment
    if ! command_exists conda; then
        log_error "Conda not found. Install Miniconda or Anaconda"
        exit 1
    fi
    log_info "Conda found: $(which conda)"
    
    # Check if xc7 environment exists
    if ! conda env list | grep -q "xc7"; then
        log_warn "xc7 environment not found"
        log_info "Creating xc7 environment..."
        log_info "Note: This will take several minutes on first run"
        cd "${F4PGA_INSTALL_DIR}/.."
        conda env create -f "${F4PGA_INSTALL_DIR}/../xc7/environment.yml" || {
            log_error "Failed to create xc7 environment"
            exit 1
        }
        cd "${SCRIPT_DIR}"
    fi
    log_info "xc7 environment ready"
    
    # Check required tools
    log_info "Checking required tools..."
    for tool in yosys nextpnr-xilinx; do
        if ! command_exists "$tool"; then
            log_error "Tool not found: $tool"
            log_info "Try: conda activate xc7"
            exit 1
        fi
        log_info "  ✓ $(which $tool)"
    done
    
    # Check YAML file
    if [ ! -f "${PART_YAML}" ]; then
        log_error "Device YAML not found: ${PART_YAML}"
        exit 1
    fi
    log_info "Device YAML found: ${PART_YAML}"
}

# Setup build directory
setup_build_dir() {
    log_section "Setting Up Build Directory"
    
    mkdir -p "${BUILD_DIR}"
    mkdir -p "${REPORTS_DIR}"
    
    log_info "Build directory: ${BUILD_DIR}/"
    log_info "Reports directory: ${REPORTS_DIR}/"
}

# Run synthesis
run_synthesis() {
    log_section "Running Synthesis (Yosys)"
    
    if [ ! -f "Makefile" ]; then
        log_error "Makefile not found"
        exit 1
    fi
    
    log_info "Reading RTL files..."
    log_info "Top module: riscv_soc_top"
    
    yosys -m ghdl << 'YOSYS_EOF'
read_verilog ../../rtl/core/*.sv
read_verilog ../../rtl/memory/*.sv
read_verilog ../../rtl/cache/*.sv
read_verilog ../../rtl/coherence/*.sv
read_verilog ../../rtl/bus/*.sv
read_verilog ../../rtl/peripheral/*.sv
read_verilog ../../rtl/top/*.sv

hierarchy -check -top riscv_soc_top
proc
opt_clean -purge

synth_xilinx -flatten -json build/riscv_soc_arty100t.json

stat
YOSYS_EOF
    
    if [ ! -f "${BUILD_DIR}/${PROJECT_NAME}.json" ]; then
        log_error "Synthesis failed: JSON not generated"
        exit 1
    fi
    
    SIZE=$(du -h "${BUILD_DIR}/${PROJECT_NAME}.json" | cut -f1)
    log_success "✓ Synthesis complete: ${SIZE}"
}

# Run place & route
run_pnr() {
    log_section "Running Place & Route (nextpnr)"
    
    if [ ! -f "${BUILD_DIR}/${PROJECT_NAME}.json" ]; then
        log_error "Synthesis output not found"
        exit 1
    fi
    
    if [ ! -f "arty100t.xdc" ]; then
        log_error "Constraints file not found: arty100t.xdc"
        exit 1
    fi
    
    log_info "Using constraints: arty100t.xdc"
    log_info "Device YAML: ${PART_YAML}"
    
    nextpnr-xilinx \
        --json "${BUILD_DIR}/${PROJECT_NAME}.json" \
        --xdc "arty100t.xdc" \
        --xact_map "${PART_YAML}" \
        --device "${DEVICE}" \
        --write "${BUILD_DIR}/${PROJECT_NAME}.net.json" \
        --seed 42 \
        --timing-allow-fail
    
    if [ ! -f "${BUILD_DIR}/${PROJECT_NAME}.net.json" ]; then
        log_error "Place & Route failed: netlist not generated"
        exit 1
    fi
    
    SIZE=$(du -h "${BUILD_DIR}/${PROJECT_NAME}.net.json" | cut -f1)
    log_success "✓ Place & Route complete: ${SIZE}"
}

# Generate bitstream
generate_bitstream() {
    log_section "Generating Bitstream (F4PGA)"
    
    if [ ! -f "${BUILD_DIR}/${PROJECT_NAME}.net.json" ]; then
        log_error "P&R netlist not found"
        exit 1
    fi
    
    # Check if f4pga tools are available
    if ! command_exists f4pga; then
        log_error "F4PGA tools not found in PATH"
        log_warn "Try: conda activate xc7"
        exit 1
    fi
    
    log_info "Step 1/4: Packing..."
    f4pga pack \
        -e "${PART_YAML}" \
        -d "${DEVICE}" \
        -s "${BUILD_DIR}/${PROJECT_NAME}.eblif" \
        "${BUILD_DIR}/${PROJECT_NAME}.net.json" || {
        log_error "Packing failed"
        exit 1
    }
    log_info "  ✓ Packing complete"
    
    log_info "Step 2/4: Placement..."
    f4pga place \
        -e "${PART_YAML}" \
        -d "${DEVICE}" \
        -n "${BUILD_DIR}/${PROJECT_NAME}.net.json" \
        -p "${BUILD_DIR}/${PROJECT_NAME}.place" || {
        log_error "Placement failed"
        exit 1
    }
    log_info "  ✓ Placement complete"
    
    log_info "Step 3/4: Routing..."
    f4pga route \
        -e "${PART_YAML}" \
        -d "${DEVICE}" \
        -s "${BUILD_DIR}/${PROJECT_NAME}.route" || {
        log_error "Routing failed"
        exit 1
    }
    log_info "  ✓ Routing complete"
    
    log_info "Step 4/4: Writing bitstream..."
    f4pga write_bitstream \
        -e "${PART_YAML}" \
        -d "${DEVICE}" \
        -b "${BUILD_DIR}/${PROJECT_NAME}.bit" || {
        log_error "Bitstream generation failed"
        exit 1
    }
    log_info "  ✓ Bitstream writing complete"
    
    if [ ! -f "${BUILD_DIR}/${PROJECT_NAME}.bit" ]; then
        log_error "Bitstream file not generated"
        exit 1
    fi
    
    SIZE=$(du -h "${BUILD_DIR}/${PROJECT_NAME}.bit" | cut -f1)
    log_success "✓ Bitstream generated: ${SIZE}"
}

# Program FPGA
program_fpga() {
    log_section "Programming FPGA"
    
    BITSTREAM="${BUILD_DIR}/${PROJECT_NAME}.bit"
    
    if [ ! -f "${BITSTREAM}" ]; then
        log_error "Bitstream file not found: ${BITSTREAM}"
        exit 1
    fi
    
    # Check for USB device
    if ! lsusb | grep -qi digilent; then
        log_warn "Digilent device not detected via lsusb"
        log_info "Verify Arty A7-100T is connected via USB"
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Programming cancelled"
            return 1
        fi
    else
        log_info "Digilent device detected"
    fi
    
    # Try OpenOCD
    if command_exists openocd; then
        log_info "Using OpenOCD for JTAG programming..."
        
        if [ -f "board/arty_a7.cfg" ]; then
            openocd -f "board/arty_a7.cfg" \
                -c "init" \
                -c "pld load 0 ${BITSTREAM}" \
                -c "exit" || {
                log_error "OpenOCD programming failed"
                return 1
            }
        else
            log_warn "OpenOCD config not found: board/arty_a7.cfg"
            return 1
        fi
    else
        log_error "OpenOCD not found"
        log_info "Install: sudo apt-get install openocd"
        return 1
    fi
    
    log_success "✓ FPGA Programming Complete!"
    log_info "Device should now be running the loaded design"
}

# Clean build artifacts
clean_build() {
    log_section "Cleaning Build Artifacts"
    
    if [ -d "${BUILD_DIR}" ]; then
        rm -rf "${BUILD_DIR}"
        log_info "Removed: ${BUILD_DIR}/"
    else
        log_info "Build directory already clean"
    fi
    
    log_success "✓ Clean Complete"
}

# Display help
show_help() {
    cat << 'EOF'

╔════════════════════════════════════════════════════════════════════════════╗
║                      RISC-V SoC Bitstream Generator                        ║
║                    Quick Start for Arty A7-100T FPGA                       ║
╚════════════════════════════════════════════════════════════════════════════╝

USAGE:
  bash quickstart-bitstream.sh [OPTION]

OPTIONS:
  (none)           Build bitstream (synthesis + P&R + bitstream)
  --program        Build and program FPGA immediately
  --synthesis-only Synthesis step only
  --pnr-only       Place & route step only
  --bitstream-only Bitstream generation step only
  --clean          Remove all build artifacts
  --help           Show this help message

EXAMPLES:
  bash quickstart-bitstream.sh              # Full build
  bash quickstart-bitstream.sh --program    # Build + load to FPGA
  bash quickstart-bitstream.sh --clean      # Remove build files

REQUIREMENTS:
  ✓ F4PGA installed at ~/opt/f4pga
  ✓ conda environment with xc7 created
  ✓ Tools: yosys, nextpnr-xilinx, f4pga, openocd (for programming)
  ✓ Arty A7-100T connected via USB (for --program option)

SETUP (First Time):
  1. Install F4PGA: https://github.com/chipsalliance/f4pga
  2. Source environment: source ~/.bashrc
  3. Activate conda: conda activate xc7
  4. Navigate to: cd fpga/f4pga
  5. Run this script: bash quickstart-bitstream.sh --program

OUTPUT FILES:
  build/riscv_soc_arty100t.bit    → FPGA bitstream (ready to program)
  build/riscv_soc_arty100t.json   → Synthesis netlist
  build/reports/                  → Build reports and statistics

DOCUMENTATION:
  See BITSTREAM_GENERATION_GUIDE.md for detailed instructions

EOF
}

# =====================================================================
# MAIN EXECUTION
# =====================================================================

main() {
    # Parse command line arguments
    PROGRAM_FPGA=false
    SYNTH_ONLY=false
    PNR_ONLY=false
    BIT_ONLY=false
    CLEAN_ONLY=false
    
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --clean)
            CLEAN_ONLY=true
            ;;
        --synthesis-only)
            SYNTH_ONLY=true
            ;;
        --pnr-only)
            PNR_ONLY=true
            ;;
        --bitstream-only)
            BIT_ONLY=true
            ;;
        --program)
            PROGRAM_FPGA=true
            ;;
        *)
            # Default: full build
            ;;
    esac
    
    # Execute based on options
    if [ "$CLEAN_ONLY" = true ]; then
        clean_build
        exit 0
    fi
    
    # Verify environment
    verify_environment
    
    # Setup directories
    setup_build_dir
    
    # Execute build steps
    if [ "$SYNTH_ONLY" = true ]; then
        run_synthesis
    elif [ "$PNR_ONLY" = true ]; then
        run_pnr
    elif [ "$BIT_ONLY" = true ]; then
        generate_bitstream
    else
        # Full build
        run_synthesis
        run_pnr
        generate_bitstream
    fi
    
    # Program FPGA if requested
    if [ "$PROGRAM_FPGA" = true ]; then
        if program_fpga; then
            log_success "✓ All Tasks Complete!"
            log_info "Bitstream: ${BUILD_DIR}/${PROJECT_NAME}.bit"
            log_info "Status: Loaded to Arty A7-100T"
        else
            log_error "Programming failed"
            exit 1
        fi
    else
        log_success "✓ Build Complete!"
        log_info "Bitstream: ${BUILD_DIR}/${PROJECT_NAME}.bit"
        log_info "To program FPGA: bash quickstart-bitstream.sh --program"
    fi
}

# Run main function
main "$@"
