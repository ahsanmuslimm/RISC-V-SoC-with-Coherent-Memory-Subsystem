# F4PGA FPGA Deployment Guide: RISC-V SoC on Arty A7-100T

**Project:** RISC-V Dual-Core SoC with Coherent Memory Subsystem  
**Target Board:** Arty A7-100T (Xilinx Artix-7, XC7A100T)  
**Toolchain:** F4PGA (Open-source FPGA tools)  
**Date:** September 8, 2026  

---

## Overview

This guide covers FPGA deployment for the RISC-V SoC using the **F4PGA** open-source toolchain instead of proprietary Vivado. F4PGA provides:

✅ **Free and open-source** tools (Yosys, nextpnr-xilinx)  
✅ **Full transparency** in the build process  
✅ **Compatible with Arty A7-100T** (XC7 family support)  
✅ **Linux-friendly** command-line build system  

---

## Quick Start (5 Minutes)

### Prerequisites

1. **F4PGA Toolchain installed** (see Installation below)
2. **RISC-V SoC RTL files** (Days 1–3)
3. **FPGA board:** Arty A7-100T with USB cable

### Full Build

```bash
cd fpga/f4pga
bash build.sh                    # Full build (synthesis + PnR + bitstream)
```

**Output:** `build/riscv_soc_arty100t.bit` (FPGA bitstream)

### Program FPGA

```bash
cd fpga/f4pga
make program                     # Program FPGA via JTAG
```

Or manually:
```bash
openocd -f board/arty_a7.cfg \
       -c "init" \
       -c "pld load 0 build/riscv_soc_arty100t.bit" \
       -c "exit"
```

---

## Installation

### Option 1: Install F4PGA from Pre-built Binaries (Recommended)

```bash
# Clone F4PGA examples repository
git clone https://github.com/chipsalliance/f4pga-examples.git
cd f4pga-examples

# Setup environment (includes all tools)
source environment.sh
conda activate fpga

# Verify tools
yosys --version
nextpnr-xilinx --help
f4pga --help
```

### Option 2: Install via Conda (Easiest for Linux)

```bash
# Install conda (if not already installed)
# https://docs.conda.io/en/latest/miniconda.html

# Create F4PGA environment
conda create -n fpga python=3.9
conda activate fpga

# Install F4PGA tools
conda install -c conda-forge yosys nextpnr-xilinx openocd

# Install additional tools
pip install intervaltree

# Verify installation
yosys --version
```

### Option 3: Build from Source

```bash
# Clone F4PGA projects
git clone https://github.com/chipsalliance/yosys.git
git clone https://github.com/YosysHQ/nextpnr.git

# Build Yosys
cd yosys
make config-clang
make -j$(nproc)
sudo make install
cd ..

# Build nextpnr
cd nextpnr
cmake -DARCH=xilinx -DBUILD_GUI=OFF -DBUILD_PYTHON=ON .
make -j$(nproc)
sudo make install
cd ..
```

### Verify Installation

```bash
# Check all tools
yosys --version
nextpnr-xilinx --help
f4pga --version
openocd --version
```

---

## Project Structure

```
fpga/
├── f4pga/
│   ├── Makefile                 # Build automation (make targets)
│   ├── build.sh                 # Bash build script (portable)
│   └── build/                   # Build artifacts (generated)
│       ├── riscv_soc_arty100t.json      # Synthesis output
│       ├── riscv_soc_arty100t.net.json  # Place & Route output
│       └── riscv_soc_arty100t.bit       # FPGA bitstream
│
└── vivado/
    ├── .gitkeep
    └── (legacy Vivado configs - deprecated)

constraints/
├── arty100t.xdc                 # Pin & timing constraints (XDC format)
└── .gitkeep

rtl/
├── top/riscv_soc_top.sv         # Top-level module
└── ...                          # RTL modules (Days 1–3)
```

---

## Build Process

### Step 1: Synthesis (Yosys)

**Purpose:** Convert RTL to gate-level netlist (JSON format)

```bash
cd fpga/f4pga
bash build.sh --synthesis
```

**What it does:**
1. Reads all Verilog RTL files
2. Checks hierarchy and design rules
3. Performs optimization passes
4. Generates JSON netlist for nextpnr

**Output:** `build/riscv_soc_arty100t.json` (~5–10 MB)

**Typical time:** 30–60 seconds

---

### Step 2: Place & Route (nextpnr-xilinx)

**Purpose:** Assign logic to physical FPGA resources

```bash
cd fpga/f4pga
bash build.sh --pnr
```

**What it does:**
1. Reads JSON netlist and constraints
2. Clusters logic into CLBs (configurable logic blocks)
3. Places clusters on FPGA grid
4. Routes signals between clusters
5. Generates physical netlist

**Inputs:**
- `build/riscv_soc_arty100t.json` (from synthesis)
- `constraints/arty100t.xdc` (pin & timing constraints)

**Output:** `build/riscv_soc_arty100t.net.json` (~20–50 MB)

**Typical time:** 2–5 minutes (depending on design complexity)

**Options:**
- `--seed 42`: Fixed seed for reproducible results
- `--timing-allow-fail`: Allow timing violations (for large designs)
- `--freq 50`: Target frequency constraint (MHz)

---

### Step 3: Bitstream Generation (F4PGA Tools)

**Purpose:** Generate FPGA configuration bitstream

```bash
cd fpga/f4pga
bash build.sh --bitstream
```

**What it does:**
1. Pack logic into FPGA primitives
2. Place CLBs on physical grid
3. Route signal connections
4. Generate bitstream for configuration

**Output:** `build/riscv_soc_arty100t.bit` (~1–5 MB)

**Typical time:** 1–3 minutes

---

### Step 4: Program FPGA (OpenOCD + JTAG)

**Purpose:** Load bitstream onto FPGA board

```bash
cd fpga/f4pga
make program
```

Or use OpenOCD directly:
```bash
openocd -f board/arty_a7.cfg \
       -c "init" \
       -c "pld load 0 build/riscv_soc_arty100t.bit" \
       -c "exit"
```

**What it does:**
1. Connects to FPGA via JTAG (USB interface)
2. Loads bitstream into FPGA configuration memory
3. FPGA boots with loaded design

**Prerequisites:**
- USB cable connected (board powered via USB)
- OpenOCD installed and configured
- FPGA board detected by system

**Typical time:** 5–10 seconds

---

## Build Commands

### Full Build (Synthesis → PnR → Bitstream)

```bash
cd fpga/f4pga
bash build.sh                    # No argument = full build
# or
make build
```

**Output:** `build/riscv_soc_arty100t.bit`

---

### Synthesis Only

```bash
bash build.sh --synthesis
# or
make synthesis
```

**Use case:** Check RTL for errors before running slow PnR

---

### Place & Route Only

```bash
bash build.sh --pnr
# or
make pnr
```

**Use case:** Iterate on constraints without re-synthesizing

---

### Bitstream Generation Only

```bash
bash build.sh --bitstream
# or
make generate_bitstream
```

**Use case:** Regenerate bitstream after final tweaks

---

### Program FPGA

```bash
make program
```

**Use case:** Load bitstream onto FPGA board

---

### Clean Build Artifacts

```bash
bash build.sh --clean
# or
make clean
```

**Use case:** Remove build directory and restart clean

---

## Constraints (arty100t.xdc)

### Clock Constraint

```tcl
# 100 MHz system clock
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 [get_ports clk]
```

**Arty A7-100T:** On-board 100 MHz oscillator on pin E3

---

### Reset Constraint

```tcl
# Active-low reset button
set_property -dict { PACKAGE_PIN C2 IOSTANDARD LVCMOS33 } [get_ports rst_n]
set_property PULLUP true [get_ports rst_n]
```

**Arty A7-100T:** Reset button (BTNC) on pin C2

---

### UART Pins

```tcl
# UART TX (output)
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports uart_tx]

# UART RX (input)
set_property -dict { PACKAGE_PIN A9  IOSTANDARD LVCMOS33 } [get_ports uart_rx]
```

**Arty A7-100T:** USB-UART bridge via CH340 chip

**Baud rate:** 115200 (set in SoC design)

**Connection:** USB cable to computer (appears as /dev/ttyUSB* on Linux)

---

### LED Pins

```tcl
# 8 LEDs available
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports led[0]]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports led[1]]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports led[2]]
set_property -dict { PACKAGE_PIN G13 IOSTANDARD LVCMOS33 } [get_ports led[3]]
set_property -dict { PACKAGE_PIN D13 IOSTANDARD LVCMOS33 } [get_ports led[4]]
set_property -dict { PACKAGE_PIN B14 IOSTANDARD LVCMOS33 } [get_ports led[5]]
set_property -dict { PACKAGE_PIN F14 IOSTANDARD LVCMOS33 } [get_ports led[6]]
set_property -dict { PACKAGE_PIN C14 IOSTANDARD LVCMOS33 } [get_ports led[7]]
```

**Arty A7-100T:** 4 user LEDs (LD4–LD7) + 4 optional pins

---

## Troubleshooting

### Issue: "yosys: command not found"

**Fix:** Activate F4PGA conda environment
```bash
conda activate fpga
yosys --version
```

Or add F4PGA to PATH:
```bash
export PATH="/opt/f4pga/bin:$PATH"
```

---

### Issue: "nextpnr-xilinx: command not found"

**Fix:** Install via conda
```bash
conda install -c conda-forge nextpnr-xilinx
nextpnr-xilinx --help
```

---

### Issue: "No JSON file after synthesis"

**Cause:** Yosys synthesis failed

**Fix:**
1. Check RTL for syntax errors
2. Run with verbose output:
   ```bash
   yosys -v 4 -m ghdl -p "read_verilog ..."
   ```
3. Check Yosys warnings/errors

---

### Issue: "FPGA not detected by OpenOCD"

**Cause:** JTAG connection issue

**Fix:**
1. Verify USB cable connected
2. Check board powered
3. List JTAG devices:
   ```bash
   lsusb | grep -i xilinx
   ```
4. Try different USB port
5. Check FTDI driver:
   ```bash
   lsmod | grep ftdi
   ```

---

### Issue: "Timing violations in PnR"

**Cause:** Design too large or timing too tight

**Fix:**
1. Use `--timing-allow-fail` option (generated bitstream may not meet timing)
2. Reduce clock frequency (increase period constraint)
3. Optimize critical paths in RTL
4. Try different seed: `--seed 123`

---

## Performance Metrics (Expected)

### Resource Utilization (Arty A7-100T: XC7A100T)

| Resource | Available | Used | Utilization |
|----------|-----------|------|-------------|
| **LUTs** | 63,400 | ~4,000 | ~6% |
| **FFs** | 63,400 | ~2,000 | ~3% |
| **BRAMs** | 270 | 5 | ~2% |
| **DSPs** | 240 | 0 | 0% |

---

### Build Times

| Stage | Time | Notes |
|-------|------|-------|
| **Synthesis** | 30–60 s | Depends on RTL size |
| **PnR** | 2–5 min | Dominant time |
| **Bitstream** | 1–3 min | F4PGA packing/routing |
| **Total** | ~5–10 min | Full build end-to-end |

---

### Power Consumption (Estimated)

| State | Power | Notes |
|-------|-------|-------|
| **Idle** | ~50 mW | Leakage only |
| **Running @ 50 MHz** | ~200 mW | Dynamic + leakage |
| **Full load** | ~500 mW | Peak (both cores active) |

**Note:** Arty A7-100T board total power draw (including peripherals): ~1–2 W

---

## Advanced Usage

### Custom Frequency Targeting

Edit `fpga/f4pga/Makefile` or `build.sh`:

```bash
# Set different target frequency (MHz)
TARGET_FREQ=100   # For faster design
# or
TARGET_FREQ=25    # For slower/lower-power
```

---

### Custom Build Script Integration

Use from other build systems:

```bash
#!/bin/bash
# In your CI/CD pipeline
cd fpga/f4pga
bash build.sh --synthesis
if [ $? -eq 0 ]; then
    bash build.sh --pnr
    bash build.sh --bitstream
    echo "Bitstream ready: build/riscv_soc_arty100t.bit"
else
    echo "Synthesis failed"
    exit 1
fi
```

---

### Generating Reports

```bash
# Create build reports
make reports

# Reports generated in:
# build/reports/synth_stat.json
# build/reports/pnr.rpt
# build/reports/synth.rpt
```

---

## F4PGA vs Vivado Comparison

| Feature | F4PGA | Vivado |
|---------|-------|--------|
| **Cost** | Free | Proprietary ($$ or free WebPACK) |
| **Source** | Open-source | Proprietary/closed |
| **Platform** | Linux, macOS | Windows, Linux |
| **Speed** | Fast | Slower (more optimized) |
| **Quality** | Good | Excellent |
| **Learning curve** | Moderate | Steep |
| **Documentation** | Growing | Extensive |

**For this project:** F4PGA sufficient for prototyping, Vivado better for production optimization

---

## Next Steps (Day 5)

### Run Full FPGA Build

```bash
cd fpga/f4pga
bash build.sh
```

### Program Board

```bash
make program
```

### Verify Design

- Connect via UART (115200 baud)
- Send test commands
- Observe LED output
- Monitor performance

---

## References

### F4PGA Documentation
- [F4PGA Project](https://f4pga.org/)
- [F4PGA Examples](https://github.com/chipsalliance/f4pga-examples)
- [nextpnr Documentation](https://nextpnr.readthedocs.io/)

### Arty A7-100T Documentation
- [Board Reference](https://reference.digilentinc.com/reference/programmable-logic/arty-a7/reference)
- [Pinout Diagram](https://reference.digilentinc.com/reference/programmable-logic/arty-a7/reference#pinout_table)
- [Datasheet](https://www.xilinx.com/products/silicon-devices/fpga/artix-7.html)

### FPGA Tools
- [Yosys Documentation](https://yosyshq.net/yosys/)
- [OpenOCD User's Guide](http://openocd.org/doc/html/index.html)

---

## Status

✅ **F4PGA Configuration Complete**

- ✅ Makefile build system ready
- ✅ build.sh script ready
- ✅ Constraints (arty100t.xdc) ready
- ✅ Full build pipeline documented

**Ready for Day 5:** Run full build and program FPGA

