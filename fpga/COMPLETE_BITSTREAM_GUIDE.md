# Complete F4PGA Bitstream Generation Guide
## RISC-V Dual-Core SoC with Coherent Memory Subsystem

---

## 🎯 WHAT YOU HAVE NOW

✅ **Complete**: RTL synthesis (11 MB JSON netlist)  
✅ **Complete**: F4PGA infrastructure & configuration  
✅ **Complete**: Build environment setup  
⏳ **Pending**: Place & Route (needs nextpnr-xilinx)  
⏳ **Pending**: Bitstream generation  

---

## 📋 CURRENT STATUS

### Synthesis Output
```
File: fpga/f4pga/build/riscv_soc_arty100t.json
Size: 11 MB
Status: ✅ Ready for P&R
Errors: 0
Warnings: 64 (normal)
Utilization: 0.3% (284 LCs)
```

### Missing Tool
```
Tool: nextpnr-xilinx (Place & Route)
Status: ✗ Not installed
Reason: Network error downloading dependencies
```

---

## 🔧 HOW TO COMPLETE THE BITSTREAM

### Step 1: Fix Network Connectivity
Check your internet connection:
```bash
ping -c 1 google.com
ping -c 1 anaconda.com
```

### Step 2: Install nextpnr-xilinx
```bash
# Navigate to F4PGA examples
cd ~/f4pga-examples

# Set environment variables
export F4PGA_INSTALL_DIR=~/opt/f4pga
export FPGA_FAM="xc7"

# Source conda setup
source "$F4PGA_INSTALL_DIR/$FPGA_FAM/conda/etc/profile.d/conda.sh"

# Activate environment
conda activate xc7

# Install nextpnr-xilinx (with retries)
conda install -c litex-hub nextpnr-xilinx -y --retries 5

# Verify installation
which nextpnr-xilinx
nextpnr-xilinx --version
```

**Expected output**:
```
/home/cl4/opt/f4pga/xc7/conda/envs/xc7/bin/nextpnr-xilinx
nextpnr-xilinx v0.0_2841_gcd8b15db
```

### Step 3: Generate Bitstream
```bash
# Navigate to project
cd ~/f4pga-examples/xc7/RISC-V-SoC-with-Coherent-Memory-Subsystem/fpga/f4pga

# Clean previous builds (optional)
make clean

# Start bitstream generation
# ⚠️  WARNING: This will take 20-45 minutes!
make build
```

**What happens during build**:
- Pack: Maps logic to CLBs
- Place: Positions on FPGA grid
- Route: Connects with wires
- Bitstream: Generates final .bit file

**Expected console output**:
```
[pack] Running pack...
[place] Running place...
[route] Running route...
[write_bitstream] Generating bitstream...
Build complete!
```

### Step 4: Verify Bitstream Generated
```bash
# Check for bitstream file
ls -lh fpga/f4pga/build/riscv_soc_arty100t.bit

# Expected output:
# -rw-rw-r-- 1 cl4 cl4 600K Sep  9 12:30 fpga/f4pga/build/riscv_soc_arty100t.bit
```

---

## 🎯 ALTERNATIVE: USE VIVADO

If nextpnr-xilinx won't install, use Vivado:

```bash
# Check if Vivado is installed
which vivado

# If found, create new project in Vivado GUI:
# 1. File → New Project
# 2. Select "Arty A7-100T" as board
# 3. Add RTL files from rtl/ directory
# 4. Add constraints from fpga/f4pga/arty100t.xdc
# 5. Run Synthesis → Place & Route → Generate Bitstream
```

---

## 📦 PROGRAMMING YOUR FPGA

After bitstream is generated:

### Option 1: Using OpenFPGALoader
```bash
# Load bitstream to FPGA via USB
openFPGALoader -f -m fpga/f4pga/build/riscv_soc_arty100t.bit
```

### Option 2: Using OpenOCD
```bash
# Start OpenOCD server
openocd -f board/arty_a7.cfg

# In another terminal
telnet localhost 4444

# Load bitstream
> program_flash /path/to/riscv_soc_arty100t.bit
```

### Option 3: Using Vivado Hardware Manager
```bash
vivado -mode batch -source <script.tcl>
```

---

## ✅ TROUBLESHOOTING

### Issue 1: nextpnr-xilinx Still Won't Install
**Solution**:
```bash
# Try conda-forge channel
conda install -c conda-forge nextpnr-xilinx -y

# Or use mamba (faster)
conda install -n base -c conda-forge mamba
mamba install -c litex-hub nextpnr-xilinx
```

### Issue 2: "HTTP 000 CONNECTION FAILED"
**Solution**:
```bash
# Check connectivity
ping anaconda.com

# Retry with extended timeout
conda install -c litex-hub nextpnr-xilinx -y --retries 10 --timeout 600

# Or clear conda cache and retry
conda clean --all
conda install -c litex-hub nextpnr-xilinx -y
```

### Issue 3: "Environment not activated"
**Solution**:
```bash
# Verify environment exists
conda env list

# If missing, recreate it
cd ~/f4pga-examples
conda env create -f xc7/environment.yml -y

# Activate
conda activate xc7
```

### Issue 4: "make: command not found"
**Solution**:
```bash
# Install make
sudo apt-get install build-essential

# Or if using conda
conda install make
```

---

## 📊 FILES REFERENCE

### Project Structure
```
RISC-V-SoC-with-Coherent-Memory-Subsystem/
├── rtl/                          # RTL source code (17 modules)
│   ├── core/                     # CPU cores
│   ├── memory/                   # Memory controllers
│   ├── cache/                    # L1 caches
│   ├── coherence/                # Coherence protocol
│   ├── bus/                      # AXI bus
│   ├── peripheral/               # Peripherals
│   └── top/                      # Top module
├── fpga/
│   ├── f4pga/                    # F4PGA build directory
│   │   ├── Makefile              # Build rules
│   │   ├── flow.json             # F4PGA configuration
│   │   ├── arty100t.xdc          # Constraints
│   │   └── build/
│   │       ├── riscv_soc_arty100t.json  # Synthesis (11 MB)
│   │       └── riscv_soc_arty100t.bit   # Bitstream (pending)
│   └── vivado/                   # Vivado project (alternative)
├── BITSTREAM_STATUS_FINAL.md     # Detailed status report
└── COMPLETE_BITSTREAM_GUIDE.md   # This file
```

### Key Files
- **fpga/f4pga/Makefile**: Build automation
- **fpga/f4pga/flow.json**: F4PGA pipeline configuration
- **fpga/f4pga/arty100t.xdc**: FPGA pin constraints
- **fpga/f4pga/build/riscv_soc_arty100t.json**: Synthesis netlist
- **fpga/f4pga/build/riscv_soc_arty100t.bit**: Final bitstream (to be generated)

---

## 🚀 QUICK START COMMANDS

### One-Command Build (after nextpnr-xilinx installed)
```bash
cd ~/f4pga-examples && \
export F4PGA_INSTALL_DIR=~/opt/f4pga && \
export FPGA_FAM="xc7" && \
source "$F4PGA_INSTALL_DIR/$FPGA_FAM/conda/etc/profile.d/conda.sh" && \
conda activate xc7 && \
cd xc7/RISC-V-SoC-with-Coherent-Memory-Subsystem/fpga/f4pga && \
make clean && \
make build && \
ls -lh build/*.bit
```

---

## 📝 EXPECTED TIMELINE

| Phase | Duration | Status |
|-------|----------|--------|
| RTL Synthesis | 10-15 min | ✅ Done |
| Environment Setup | 5-10 min | ✅ Done |
| nextpnr-xilinx Install | 10-20 min | ⏳ Pending (network) |
| Place & Route | 20-45 min | ⏳ Pending |
| Bitstream Generation | 2-5 min | ⏳ Pending |
| **Total Time** | **~55-95 min** | **⏳ In Progress** |

---

## 🎓 LEARNING RESOURCES

### F4PGA Documentation
- Official: https://f4pga.readthedocs.io/
- GitHub: https://github.com/chipsalliance/f4pga

### nextpnr Documentation
- GitHub: https://github.com/YosysHQ/nextpnr
- Xilinx support: https://github.com/litex-hub/litex-hub

### Arty A7-100T Resources
- User Guide: https://digilent.com/reference/programmable-logic/arty-a7/reference-manual
- Vivado Board File: Available in Vivado
- Constraints: fpga/f4pga/arty100t.xdc

---

## 📞 SUPPORT CHECKLIST

Before asking for help, verify:
- [ ] Internet connection working
- [ ] `conda` command available
- [ ] xc7 environment exists: `conda env list | grep xc7`
- [ ] Synthesis output exists: `ls -lh fpga/f4pga/build/riscv_soc_arty100t.json`
- [ ] Flow.json exists: `ls -lh fpga/f4pga/flow.json`
- [ ] Constraints exist: `ls -lh fpga/f4pga/arty100t.xdc`

---

**Last Updated**: September 9, 2026  
**Status**: Synthesis Complete, Awaiting Tool Installation

