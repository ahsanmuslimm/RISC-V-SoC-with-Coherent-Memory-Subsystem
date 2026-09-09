# FPGA Bitstream Generation Guide for Arty A7-100T

## Overview
This guide walks you through generating and programming the RISC-V Dual-Core SoC bitstream for the Arty A7-100T FPGA board using the F4PGA open-source toolchain.

## Prerequisites

### 1. System Requirements
- Linux-based system (Ubuntu 18.04, 20.04, or later recommended)
- Python 3.7+
- ~10GB free disk space for F4PGA installation and builds

### 2. Required Tools
- F4PGA toolchain
- Yosys (logic synthesis)
- nextpnr-xilinx (place & route)
- OpenOCD (JTAG programming)

### 3. Hardware
- Arty A7-100T FPGA board
- USB cable (micro-USB for JTAG/UART)
- Power supply or USB power

---

## Step 1: Setup F4PGA Environment

### Option A: One-Time Setup (First Run)

```bash
# Navigate to F4PGA examples
cd ~/f4pga-examples

# Set environment variables
export F4PGA_INSTALL_DIR=~/opt/f4pga
export FPGA_FAM="xc7"

# Initialize conda environment
source "$F4PGA_INSTALL_DIR/$FPGA_FAM/conda/etc/profile.d/conda.sh"

# Create xc7 conda environment (ONLY FIRST TIME)
conda env create -f xc7/environment.yml

# Activate environment
conda activate xc7
```

### Option B: Every New Terminal Session

```bash
cd ~/f4pga-examples

# Set environment
export F4PGA_INSTALL_DIR=~/opt/f4pga
export FPGA_FAM="xc7"

# Source conda
source "$F4PGA_INSTALL_DIR/$FPGA_FAM/conda/etc/profile.d/conda.sh"

# Activate xc7 environment
conda activate xc7

# Verify tools are available
which yosys
which nextpnr-xilinx
which openocd
```

---

## Step 2: Navigate to Build Directory

```bash
# From project root
cd fpga/f4pga

# Verify files present
ls -la
# Expected files:
# - Makefile
# - arty100t.xdc
# - build.sh
# - flow.json (newly created)
```

---

## Step 3: Generate Bitstream

### Method 1: Using Shell Script (Recommended)

```bash
# Make build script executable
chmod +x build.sh

# Full build (synthesis + place & route + bitstream)
bash build.sh

# Or individual steps:
bash build.sh --synthesis
bash build.sh --pnr
bash build.sh --bitstream
bash build.sh --clean
```

### Method 2: Using Makefile

```bash
# Full build
make build

# Or step-by-step:
make synthesis
make pnr
make generate_bitstream

# Clean build artifacts
make clean

# View available targets
make help
```

### Method 3: Manual Command Execution

#### Step 3a: Synthesis (Yosys)

```bash
yosys -m ghdl << 'EOF'
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

stat -json build/reports/synth_stat.json
EOF
```

#### Step 3b: Place & Route (nextpnr)

```bash
nextpnr-xilinx \
  --json build/riscv_soc_arty100t.json \
  --xdc arty100t.xdc \
  --xact_map /opt/f4pga/share/f4pga/xc7a100t_test/utils/xc7a100t_test.yaml \
  --device xc7a100t_test \
  --write build/riscv_soc_arty100t.net.json \
  --seed 42 \
  --timing-allow-fail
```

#### Step 3c: Bitstream Generation (F4PGA)

```bash
# Pack
f4pga pack \
  -e /opt/f4pga/share/f4pga/xc7a100t_test/utils/xc7a100t_test.yaml \
  -d xc7a100t_test \
  -s build/riscv_soc_arty100t.eblif \
  build/riscv_soc_arty100t.net.json

# Place
f4pga place \
  -e /opt/f4pga/share/f4pga/xc7a100t_test/utils/xc7a100t_test.yaml \
  -d xc7a100t_test \
  -n build/riscv_soc_arty100t.net.json \
  -p build/riscv_soc_arty100t.place

# Route
f4pga route \
  -e /opt/f4pga/share/f4pga/xc7a100t_test/utils/xc7a100t_test.yaml \
  -d xc7a100t_test \
  -s build/riscv_soc_arty100t.route

# Write bitstream
f4pga write_bitstream \
  -e /opt/f4pga/share/f4pga/xc7a100t_test/utils/xc7a100t_test.yaml \
  -d xc7a100t_test \
  -b build/riscv_soc_arty100t.bit
```

---

## Step 4: Verify Bitstream Generation

```bash
# Check if bitstream was generated
ls -lh build/riscv_soc_arty100t.bit

# Expected output:
# -rw-r--r-- 1 user user 542K riscv_soc_arty100t.bit

# List all build artifacts
ls -lh build/
```

---

## Step 5: Program FPGA Board

### Prerequisites for Programming
1. Connect Arty A7-100T via USB cable
2. Verify USB device is recognized:
   ```bash
   lsusb | grep Digilent
   # Should show: Digilent Arty FPGA or similar
   ```

### Method 1: Using OpenOCD (Recommended)

```bash
# Program FPGA
openocd -f board/arty_a7.cfg \
  -c "init" \
  -c "pld load 0 build/riscv_soc_arty100t.bit" \
  -c "exit"

# Expected output:
# Info : FTDI MPSSE device found...
# Info : ... loaded
```

### Method 2: Using Vivado (If Available)

```bash
vivado_lab -source program.tcl
```

### Method 3: Manual Script

```bash
# Make a simple TCL script for programming
cat > program.tcl << 'EOF'
open_hw_manager
connect_hw_server -url 127.0.0.1:3121
get_hw_targets
open_hw_target [get_hw_targets *]
get_hw_devices
create_hw_bitstream -hw_device [get_hw_devices xc7a100t_0] -file {build/riscv_soc_arty100t.bit}
program_hw_devices [get_hw_devices xc7a100t_0]
EOF

vivado -nolog -nojournal -mode batch -source program.tcl
```

---

## Step 6: Verify FPGA Programming

### Via UART Terminal

```bash
# Install serial terminal (if not present)
sudo apt-get install picocom

# Connect to UART (replace ttyUSB0 if different)
picocom -b 115200 /dev/ttyUSB0

# In terminal, observe:
# - LED indicators lighting up
# - Status messages if firmware loaded
# - Press Ctrl+A then Ctrl+X to exit picocom
```

### Via GPIO/LED Status

- **LED[0-3]**: Status indicators (watch for blinking patterns)
- **LED[4-7]**: Event counters or cache activity indicators

---

## Troubleshooting

### Issue 1: Tools Not Found

```
ERROR: yosys not found
ERROR: nextpnr-xilinx not found
```

**Solution:**
```bash
# Verify F4PGA environment is activated
conda activate xc7

# Check tool paths
which yosys
which nextpnr-xilinx

# If missing, reinstall F4PGA or check installation path
```

### Issue 2: Device or YAML File Not Found

```
ERROR: Cannot find xc7a100t_test.yaml
```

**Solution:**
```bash
# Verify F4PGA installation
ls -la /opt/f4pga/share/f4pga/xc7a100t_test/

# If missing, check F4PGA_INSTALL_DIR environment variable
echo $F4PGA_INSTALL_DIR
```

### Issue 3: JTAG Device Not Found

```
Error: Could not find JTAG device
```

**Solution:**
```bash
# Check USB connection
lsusb | grep Digilent

# Check device permissions
ls -la /dev/ttyUSB*

# Add user to dialout group (one-time)
sudo usermod -a -G dialout $USER
# Then logout and login

# Check OpenOCD configuration
cat board/arty_a7.cfg
```

### Issue 4: Timing Violations

```
WARNING: Timing violations detected
```

**Solution:**
- This is expected with `--timing-allow-fail` flag
- Design will still work but may have timing margin issues
- To fix: increase clock period or optimize RTL

---

## Output Files

| File | Description | Size |
|------|-------------|------|
| `build/riscv_soc_arty100t.json` | Synthesis output (JSON netlist) | ~2-5 MB |
| `build/riscv_soc_arty100t.net.json` | Place & Route netlist | ~2-5 MB |
| `build/riscv_soc_arty100t.bit` | **FPGA Bitstream** | ~500-700 KB |
| `build/reports/synth_stat.json` | Synthesis statistics | ~50 KB |

---

## Design Specifications

### Clock & Reset
- **Clock**: 100 MHz (10 ns period) from Arty onboard oscillator
- **Reset**: Active-low asynchronous reset with 2-FF synchronizer

### Interfaces
- **UART**: 115200 8N1 via CH340 USB-to-Serial
  - TX: D10 (FPGA → Host)
  - RX: A9 (Host → FPGA)

- **GPIO/LEDs**: 8-bit output
  - LED[0-3]: On-board red/green/blue LEDs
  - LED[4-7]: Available for expansion

- **Buttons**: 4 pushbuttons (optional input)
  - BTN[0-3]: Mapped to pins D9, C9, B9, B10

### Memory Map
| Address Range | Module | Size |
|---|---|---|
| 0x00000000 - 0x000003FF | Instruction SRAM (core 0) | 1 KB |
| 0x00000400 - 0x000007FF | Instruction SRAM (core 1) | 1 KB |
| 0x10000000 - 0x10000FFF | Shared Data SRAM | 4 KB |
| 0x20000000 - 0x200000FF | MMIO Registers | 256 B |
| 0x30000000 - 0x300000FF | UART Core | 256 B |
| 0x40000000 - 0x400000FF | GPIO/LED | 256 B |

### Core Architecture
- **Cores**: 2 × RV32I RISC-V cores
- **L1 Cache**: 4-line direct-mapped per core
- **Coherence**: I/S/M protocol (Invalid/Shared/Modified)
- **Bus**: AXI4-Lite with 2-master round-robin arbiter

---

## Next Steps

1. **Monitor Execution**: Watch LEDs and UART output
2. **Verify Functionality**: Run test programs on cores
3. **Collect Results**: Check performance counters in MMIO
4. **Iterate**: Modify RTL, rebuild, reprogram as needed

---

## References

- F4PGA Project: https://github.com/chipsalliance/f4pga
- Arty A7-100T Documentation: https://reference.digilentinc.com/reference/programmable-logic/arty-a7/reference
- Xilinx XC7A100T Datasheet: https://www.xilinx.com/products/silicon-devices/fpga/artix-7.html

---

## Support

For issues or questions:
1. Check F4PGA documentation
2. Review generated reports in `build/reports/`
3. Enable verbose logging in tools (add `-v` flags)
4. Consult Arty A7-100T reference manual

---

**Last Updated**: 2026-09-09
**Flow Configuration**: flow.json
**Target Device**: XC7A100T-CSG324 (Arty A7-100T)
