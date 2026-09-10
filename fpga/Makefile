# =====================================================================
# F4PGA/OpenFPGA Build System for RISC-V SoC on Arty A7-100T
# =====================================================================
# Purpose: Build bitstream using F4PGA toolchain (open-source)
# Target: Arty A7-100T (Xilinx Artix-7, XC7A100T)
# Toolchain: F4PGA (F4PGA Project - nextpnr, yosys, etc.)
#
# Usage:
#   make build        # Synthesis + place & route
#   make program      # Program FPGA over JTAG
#   make clean        # Remove build artifacts
#   make help         # Show this help

.PHONY: help build synthesis pnr generate_bitstream program clean

# =====================================================================
# CONFIGURATION
# =====================================================================

# Project settings
PROJECT_NAME = riscv_soc_arty100t
TARGET_BOARD = arty-a7-100t
DEVICE = xc7a100t_test
PART = XC7A100T-CSG324

# Directories
RTL_DIR = ../../rtl
CONSTRAINTS_DIR = ../../constraints
BUILD_DIR = build
REPORTS_DIR = $(BUILD_DIR)/reports

# Tools
YOSYS = yosys
NEXTPNR = nextpnr-xilinx
OPENOCD = openocd

# F4PGA environment (set these or source F4PGA setup)
F4PGA_INSTALL_DIR ?= /opt/f4pga
CONDA_ENV_DIR ?= /opt/conda/envs/xc7
CHIPDB ?= $(CONDA_ENV_DIR)/share/nextpnr-xilinx/xc7a100tcsg324-1.bba
PART_YAML = $(F4PGA_INSTALL_DIR)/share/f4pga/xc7a100t_test/utils/xc7a100t_test.yaml

# Synthesis options
SYNTH_STRATEGY = -json
SYNTH_OPTIONS = -top riscv_soc_top -json $(BUILD_DIR)/$(PROJECT_NAME).json

# PnR options
PNR_OPTIONS = --seed 42 --timing-allow-fail

# =====================================================================
# TARGETS
# =====================================================================

help:
	@echo "F4PGA Build System for RISC-V SoC (Arty A7-100T)"
	@echo ""
	@echo "Targets:"
	@echo "  make build              - Full build (synthesis + PnR)"
	@echo "  make synthesis          - Synthesis only (Yosys)"
	@echo "  make pnr                - Place & Route only (nextpnr)"
	@echo "  make generate_bitstream - Generate FPGA bitstream"
	@echo "  make program            - Program FPGA over JTAG"
	@echo "  make clean              - Remove build artifacts"
	@echo "  make help               - Show this help"
	@echo ""
	@echo "Configuration:"
	@echo "  TARGET_BOARD: $(TARGET_BOARD)"
	@echo "  DEVICE: $(DEVICE)"
	@echo "  PART: $(PART)"
	@echo "  BUILD_DIR: $(BUILD_DIR)"

# Create build directory
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(REPORTS_DIR)

# =====================================================================
# SYNTHESIS (Yosys)
# =====================================================================

synthesis: $(BUILD_DIR) check_tools
	@echo "=========================================="
	@echo "Running synthesis with Yosys..."
	@echo "=========================================="
	@mkdir -p $(BUILD_DIR)
	$(YOSYS) -p "read_verilog -sv $(RTL_DIR)/core/*.sv; \
	        read_verilog -sv $(RTL_DIR)/memory/*.sv; \
	        read_verilog -sv $(RTL_DIR)/cache/*.sv; \
	        read_verilog -sv $(RTL_DIR)/coherence/*.sv; \
	        read_verilog -sv $(RTL_DIR)/bus/*.sv; \
	        read_verilog -sv $(RTL_DIR)/peripheral/*.sv; \
	        read_verilog -sv $(RTL_DIR)/top/*.sv; \
	        hierarchy -check -top riscv_soc_top; \
	        proc; opt_clean -purge; \
	        flatten; \
	        synth_xilinx; \
	        write_json $(BUILD_DIR)/$(PROJECT_NAME).json"
	@echo "✓ Synthesis complete: $(BUILD_DIR)/$(PROJECT_NAME).json"
	@ls -lh $(BUILD_DIR)/$(PROJECT_NAME).json

# =====================================================================
# PLACE & ROUTE (nextpnr)
# =====================================================================

pnr: synthesis
	@echo "=========================================="
	@echo "Running place & route with nextpnr..."
	@echo "=========================================="
	@if [ -f "$(CONSTRAINTS_DIR)/arty100t.xdc" ]; then \
		echo "Using constraints: $(CONSTRAINTS_DIR)/arty100t.xdc"; \
		$(NEXTPNR) --json $(BUILD_DIR)/$(PROJECT_NAME).json \
		          --xdc $(CONSTRAINTS_DIR)/arty100t.xdc \
		          --chipdb $(CHIPDB) \
		          --write $(BUILD_DIR)/$(PROJECT_NAME).net.json \
		          $(PNR_OPTIONS); \
	else \
		echo "WARNING: No constraints file found, running without constraints"; \
		$(NEXTPNR) --json $(BUILD_DIR)/$(PROJECT_NAME).json \
		          --chipdb $(CHIPDB) \
		          --write $(BUILD_DIR)/$(PROJECT_NAME).net.json \
		          $(PNR_OPTIONS); \
	fi
	@echo "✓ Place & Route complete: $(BUILD_DIR)/$(PROJECT_NAME).net.json"

# =====================================================================
# BITSTREAM GENERATION (F4PGA)
# =====================================================================

generate_bitstream: pnr
	@echo "=========================================="
	@echo "Generating FPGA bitstream..."
	@echo "=========================================="
	@if command -v f4pga &> /dev/null; then \
		echo "Using F4PGA for bitstream generation"; \
		f4pga pack -e $(PART_YAML) \
		         -d $(DEVICE) \
		         -s $(BUILD_DIR)/$(PROJECT_NAME).eblif \
		         $(BUILD_DIR)/$(PROJECT_NAME).net.json; \
		f4pga place -e $(PART_YAML) \
		          -d $(DEVICE) \
		          -n $(BUILD_DIR)/$(PROJECT_NAME).net.json \
		          -p $(BUILD_DIR)/$(PROJECT_NAME).place; \
		f4pga route -e $(PART_YAML) \
		          -d $(DEVICE) \
		          -s $(BUILD_DIR)/$(PROJECT_NAME).route; \
		f4pga write_bitstream -e $(PART_YAML) \
		                   -d $(DEVICE) \
		                   -b $(BUILD_DIR)/$(PROJECT_NAME).bit; \
	else \
		echo "ERROR: F4PGA not found. Install F4PGA first"; \
		exit 1; \
	fi
	@echo "✓ Bitstream generated: $(BUILD_DIR)/$(PROJECT_NAME).bit"

# =====================================================================
# BITSTREAM PROGRAMMING (OpenOCD/JTAG)
# =====================================================================

program: $(BUILD_DIR)/$(PROJECT_NAME).bit
	@echo "=========================================="
	@echo "Programming FPGA via JTAG..."
	@echo "=========================================="
	@if command -v openocd &> /dev/null; then \
		openocd -f board/digilentzynq.cfg \
		       -c "init" \
		       -c "pld load 0 $(BUILD_DIR)/$(PROJECT_NAME).bit" \
		       -c "exit"; \
	else \
		echo "OpenOCD not found. Try: vivado_lab -source program.tcl"; \
	fi
	@echo "✓ FPGA programming complete"

# =====================================================================
# UTILITY TARGETS
# =====================================================================

check_tools:
	@echo "Checking required tools..."
	@command -v yosys >/dev/null 2>&1 || (echo "ERROR: yosys not found"; exit 1)
	@command -v nextpnr-xilinx >/dev/null 2>&1 || (echo "ERROR: nextpnr-xilinx not found"; exit 1)
	@echo "✓ All required tools found"

# Full build target
build: clean synthesis pnr generate_bitstream
	@echo "=========================================="
	@echo "✓ Full build complete!"
	@echo "=========================================="
	@echo "Bitstream: $(BUILD_DIR)/$(PROJECT_NAME).bit"
	@echo "To program: make program"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@echo "✓ Clean complete"

# Generate reports
reports: build
	@echo "Generating reports..."
	@mkdir -p $(REPORTS_DIR)
	@echo "Place & Route Report:" > $(REPORTS_DIR)/pnr.rpt
	@echo "  Status: TBD" >> $(REPORTS_DIR)/pnr.rpt
	@echo "Synthesis Report:" > $(REPORTS_DIR)/synth.rpt
	@echo "  Status: TBD" >> $(REPORTS_DIR)/synth.rpt
	@echo "✓ Reports generated in $(REPORTS_DIR)/"

# Show targets
.PHONY: list
list:
	@grep "^[a-zA-Z_-]*:" Makefile | sed 's/:.*//' | sort

