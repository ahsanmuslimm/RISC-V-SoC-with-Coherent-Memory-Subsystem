# FPGA Bitstream Generation - Quick Reference

## What You Now Have

This directory contains everything needed to generate and program an FPGA bitstream for the Arty A7-100T board:

### New Files Created

1. **`flow.json`** - F4PGA design flow configuration
   - Defines synthesis, P&R, and bitstream generation steps
   - Specifies device: XC7A100T-CSG324 (Arty A7-100T)
   - Maps RTL files and constraints
   - **This was the missing piece you needed!**

2. **`BITSTREAM_GENERATION_GUIDE.md`** - Comprehensive step-by-step guide
   - Detailed setup instructions
   - All build methods (script, Makefile, manual)
   - Troubleshooting section
   - Memory map and design specifications

3. **`quickstart-bitstream.sh`** - Automated build script
   - One command to build everything
   - Verifies F4PGA environment automatically
   - Creates build directory, runs synthesis, P&R, and bitstream generation
   - **Recommended starting point**

4. **`README_BITSTREAM.md`** - This file

### Existing Files

- **`Makefile`** - Build automation using make commands
- **`arty100t.xdc`** - FPGA pin and timing constraints for Arty A7-100T
- **`build.sh`** - Original bash build script with detailed logging

---

## 🚀 Quick Start (5 Minutes)

### Step 1: Setup F4PGA Environment (One Time)

```bash
# From f4pga-examples directory
cd ~/f4pga-examples

# Set environment variables
export F4PGA_INSTALL_DIR=~/opt/f4pga
export FPGA_FAM="xc7"

# Initialize conda
source "$F4PGA_INSTALL_DIR/$FPGA_FAM/conda/etc/profile.d/conda.sh"

# Create xc7 environment (FIRST TIME ONLY - takes a few minutes)
conda env create -f xc7/environment.yml
```

### Step 2: Navigate and Build

```bash
# Navigate to build directory
cd xc7/RISC-V-SoC-with-Coherent-Memory-Subsystem/fpga/f4pga

# Make build script executable
chmod +x quickstart-bitstream.sh

# Run full build
bash quickstart-bitstream.sh

# Or: Build and program FPGA immediately
bash quickstart-bitstream.sh --program
```

### Step 3: Check Output

```bash
# Verify bitstream was generated
ls -lh build/riscv_soc_arty100t.bit

# Expected output:
# -rw-r--r-- 1 user user ~600K riscv_soc_arty100t.bit ✓
```

---

## 📋 Build Method Comparison

| Method | Command | Time | Best For |
|--------|---------|------|----------|
| **quickstart.sh** | `bash quickstart-bitstream.sh` | 5-15 min | First-time users, full automation |
| **Makefile** | `make build` | 5-15 min | Integrating into build systems |
| **build.sh** | `bash build.sh` | 5-15 min | Manual control, debugging |
| **Manual** | `yosys`, `nextpnr`, `f4pga` | Varies | Advanced users, specific steps |

---

## 📁 Project Structure

```
fpga/f4pga/
├── flow.json                           # F4PGA design flow (NEW!)
├── README_BITSTREAM.md                 # This file (NEW!)
├── BITSTREAM_GENERATION_GUIDE.md       # Detailed guide (NEW!)
├── quickstart-bitstream.sh             # Automation script (NEW!)
├── Makefile                            # Make-based build
├── build.sh                            # Detailed bash script
├── arty100t.xdc                        # Pin constraints
└── build/                              # Build outputs (created on first build)
    ├── riscv_soc_arty100t.bit          # ← FPGA Bitstream
    ├── riscv_soc_arty100t.json         # Synthesis output
    ├── riscv_soc_arty100t.net.json     # P&R output
    └── reports/                        # Build reports
```

---

## 🔧 Design Configuration

### Device & Board
- **FPGA**: Xilinx Artix-7 (XC7A100T-CSG324)
- **Board**: Digilent Arty A7-100T
- **Memory**: 100 BRAM36K blocks, ~101,440 LUT6s
- **Package**: 324-pin CSG (ceramic BGA)

### Clock
- **Frequency**: 100 MHz (configurable)
- **Source**: On-board LFCLK oscillator (pin E3)
- **Period**: 10 ns

### Interfaces
| Interface | Pins | Function |
|-----------|------|----------|
| UART TX | D10 | Serial output to host |
| UART RX | A9 | Serial input from host |
| LEDs | H17, K15, J13, G13, D13, B14, F14, C14 | 8-bit status output |
| Buttons | D9, C9, B9, B10 | 4-bit input (optional) |
| Reset | C2 | Active-low async reset |

### Coherence Protocol
- **Type**: I/S/M (Invalid/Shared/Modified)
- **Write-Through**: With broadcast invalidation
- **Cache Size**: 4 lines per core (direct-mapped)

---

## ⚙️ F4PGA Build Flow

The `flow.json` file orchestrates this pipeline:

```
RTL Files
   ↓
[Synthesis - Yosys]
   ↓ riscv_soc_arty100t.json
[Pack - F4PGA]
   ↓ riscv_soc_arty100t.eblif
[Place - F4PGA]
   ↓ riscv_soc_arty100t.place
[Route - F4PGA]
   ↓ riscv_soc_arty100t.route
[Write Bitstream - F4PGA]
   ↓
riscv_soc_arty100t.bit ← READY TO PROGRAM!
```

---

## 🐛 Troubleshooting

### Common Issues

**Q: "Command not found: yosys"**
- A: Activate conda environment: `conda activate xc7`

**Q: "F4PGA not found"**
- A: Check F4PGA_INSTALL_DIR: `echo $F4PGA_INSTALL_DIR`
- Ensure it points to installation location (default: ~/opt/f4pga)

**Q: "Device not found during programming"**
- A: Connect Arty A7-100T via USB
- Check: `lsusb | grep Digilent`
- May need: `sudo usermod -a -G dialout $USER` (then logout/login)

**Q: "Timing violations"**
- A: Expected with `--timing-allow-fail` flag
- Design will still work but may have reduced timing margin
- Safe to proceed with programming

**Q: Build takes too long / freezes**
- A: Large designs may take 10-30 minutes
- Check system resources: `free -h`, `df -h`
- Increase available RAM if needed

For more help, see **BITSTREAM_GENERATION_GUIDE.md**

---

## 📊 Build Time Expectations

| Step | Tool | Time | Notes |
|------|------|------|-------|
| Synthesis | Yosys | 2-5 min | Reads all RTL, performs optimization |
| Place & Route | nextpnr | 2-10 min | Depends on design complexity |
| Packing | F4PGA pack | 1-3 min | Logic block mapping |
| Placement | F4PGA place | 1-2 min | Initial placement on fabric |
| Routing | F4PGA route | 1-5 min | Signal interconnect routing |
| Bitstream | F4PGA write | <1 min | Final bitstream generation |
| **Total** | - | **8-30 min** | Depends on system speed |

---

## 📝 Output Files Reference

After a successful build, you'll have:

| File | Size | Purpose |
|------|------|---------|
| `riscv_soc_arty100t.json` | ~2-5 MB | Synthesis netlist (JSON format) |
| `riscv_soc_arty100t.net.json` | ~2-5 MB | Placed & routed netlist |
| `riscv_soc_arty100t.bit` | ~500-700 KB | **FPGA Bitstream (upload to board)** |
| `synth_stat.json` | ~50 KB | Synthesis statistics |
| `timing.rpt` | ~50 KB | Timing analysis report |

---

## 🔌 Programming the FPGA

### Method 1: With OpenOCD (Recommended)

```bash
# Connect board via USB first

# Program FPGA
openocd -f board/arty_a7.cfg \
  -c "init" \
  -c "pld load 0 build/riscv_soc_arty100t.bit" \
  -c "exit"

# Bitstream loads in ~1-2 seconds
# LEDs should respond to design behavior
```

### Method 2: With Vivado Lab Edition

```bash
# If Vivado Lab is installed
vivado_lab &
# Use GUI to connect board and load bitstream
```

### Method 3: With quickstart Script

```bash
bash quickstart-bitstream.sh --program
# Automatically builds and programs in one command
```

---

## ✅ Verification

After programming, verify the design:

1. **Visual**: Watch LEDs respond to system activity
2. **UART**: Connect serial terminal:
   ```bash
   picocom -b 115200 /dev/ttyUSB0
   ```
3. **Status**: Run test programs on the cores

---

## 📚 Additional Resources

- **F4PGA Documentation**: https://github.com/chipsalliance/f4pga
- **Arty A7-100T Reference**: https://reference.digilentinc.com/reference/programmable-logic/arty-a7/reference
- **Xilinx Artix-7 Datasheet**: https://www.xilinx.com/products/silicon-devices/fpga/artix-7.html
- **Yosys Documentation**: http://www.clifford.at/yosys/
- **nextpnr Documentation**: https://github.com/YosysHQ/nextpnr

---

## 🎯 Next Steps

1. **Generate Bitstream**: `bash quickstart-bitstream.sh`
2. **Program FPGA**: `bash quickstart-bitstream.sh --program`
3. **Test Design**: Connect UART terminal and verify functionality
4. **Iterate**: Modify RTL → rebuild → reprogram as needed
5. **Deploy**: Use bitstream file for production deployment

---

## 📞 Support

If you encounter issues:

1. Read **BITSTREAM_GENERATION_GUIDE.md** - detailed troubleshooting section
2. Check F4PGA documentation
3. Verify all prerequisites are met
4. Review build log for specific errors
5. Enable verbose output: `bash build.sh -v`

---

## 🎉 You're Ready!

All files are in place. Your project now has:

✅ **flow.json** - F4PGA configuration (the missing piece)
✅ **BITSTREAM_GENERATION_GUIDE.md** - Complete instructions
✅ **quickstart-bitstream.sh** - One-command build automation
✅ **Makefile** - Build automation
✅ **arty100t.xdc** - Pin constraints
✅ **RTL files** - Design implementation

**Start building**: `bash quickstart-bitstream.sh --program`

---

**Last Updated**: 2026-09-09
**Target Device**: XC7A100T-CSG324 (Arty A7-100T)
**F4PGA Version**: Latest
**Status**: Ready for Bitstream Generation ✓
