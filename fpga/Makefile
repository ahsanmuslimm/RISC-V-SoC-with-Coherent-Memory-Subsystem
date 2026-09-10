current_dir := ${CURDIR}
TOP := riscv_soc_top
TARGET ?= arty_100

# Source files (relative to project root)
SOURCES := $(current_dir)/../rtl/core/*.sv \
           $(current_dir)/../rtl/memory/*.sv \
           $(current_dir)/../rtl/cache/*.sv \
           $(current_dir)/../rtl/coherence/*.sv \
           $(current_dir)/../rtl/bus/*.sv \
           $(current_dir)/../rtl/peripheral/*.sv \
           $(current_dir)/../rtl/top/*.sv

# XDC constraint file based on target
ifeq ($(TARGET),arty_35)
    XDC := $(current_dir)/arty35t.xdc
else ifeq ($(TARGET),arty_100)
    XDC := $(current_dir)/arty100t.xdc
else
    XDC := $(current_dir)/arty100t.xdc
endif

# Build directories
BUILD_DIR := build/$(TARGET)
REPORTS_DIR := $(BUILD_DIR)/reports

# Tools
YOSYS := yosys
NEXTPNR := nextpnr-xilinx
F4PGA := f4pga
OPENOCD := openocd

# =====================================================================
# BUILD TARGETS
# =====================================================================

.PHONY: build synth pnr bitstream program clean help

# Default target
build: synth pnr bitstream
	@echo ""
	@echo "=========================================="
	@echo "Build complete!"
	@echo "Bitstream: $(BUILD_DIR)/riscv_soc_top.bit"
	@echo "=========================================="

# Synthesis using Yosys
synth: $(BUILD_DIR)
	@echo "Running synthesis..."
	@$(YOSYS) -p "read_verilog -sv $(current_dir)/../rtl/core/*.sv; \
	        read_verilog -sv $(current_dir)/../rtl/memory/*.sv; \
	        read_verilog -sv $(current_dir)/../rtl/cache/*.sv; \
	        read_verilog -sv $(current_dir)/../rtl/coherence/*.sv; \
	        read_verilog -sv $(current_dir)/../rtl/bus/*.sv; \
	        read_verilog -sv $(current_dir)/../rtl/peripheral/*.sv; \
	        read_verilog -sv $(current_dir)/../rtl/top/*.sv; \
	        hierarchy -check -top $(TOP); \
	        proc; opt; synth_xilinx; \
	        write_json $(BUILD_DIR)/$(TOP).json" 2>&1 | tee $(BUILD_DIR)/synth.log
	@echo "Synthesis complete: $(BUILD_DIR)/$(TOP).json"

# Place & Route using nextpnr
pnr: synth
	@echo "Running place and route..."
	@mkdir -p $(REPORTS_DIR)
	@$(NEXTPNR) --json $(BUILD_DIR)/$(TOP).json \
	            --xdc $(XDC) \
	            --top $(TOP) \
	            --seed 42 \
	            --timing-allow-fail \
	            --write $(BUILD_DIR)/$(TOP).net.json 2>&1 | tee $(REPORTS_DIR)/pnr.log
	@echo "PnR complete: $(BUILD_DIR)/$(TOP).net.json"

# Generate bitstream
bitstream: pnr
	@echo "Generating bitstream..."
	@$(F4PGA) -vv build --flow $(current_dir)/flow.json 2>&1 | tee $(REPORTS_DIR)/bitstream.log
	@echo "Bitstream: $(BUILD_DIR)/$(TOP).bit"

# Program FPGA
program: bitstream
	@echo "Programming FPGA..."
	@if command -v $(OPENOCD) &> /dev/null; then \
		$(OPENOCD) -f board/digilent-hs2.cfg \
		           -c "init" \
		           -c "pld load 0 $(BUILD_DIR)/$(TOP).bit" \
		           -c "exit"; \
	else \
		echo "OpenOCD not found. Install or use Vivado:"; \
		echo "  vivado -source program.tcl"; \
	fi

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf build/
	@echo "Done."

# Help target
help:
	@echo "RISC-V Dual-Core SoC FPGA Build System"
	@echo ""
	@echo "Targets:"
	@echo "  make build          - Full build (synth + pnr + bitstream)"
	@echo "  make synth          - Synthesis only (Yosys)"
	@echo "  make pnr            - Place & Route (nextpnr)"
	@echo "  make bitstream      - Generate bitstream"
	@echo "  make program        - Program FPGA via JTAG"
	@echo "  make clean          - Remove build artifacts"
	@echo ""
	@echo "Variables:"
	@echo "  TARGET=arty_100     - Target board (default: arty_100)"
	@echo ""

# =====================================================================
# DIRECTORY CREATION
# =====================================================================

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(REPORTS_DIR)