# FPGA Bitstream Generation - File Index & Navigation Guide

Quick navigation to all documentation and tools for generating FPGA bitstream for Arty A7-100T.

---

## 🎯 Start Here

**First Time?** → Read this first:
- [`README_BITSTREAM.md`](README_BITSTREAM.md) - 5-minute quick reference

**Want to build?** → Run this command:
```bash
bash quickstart-bitstream.sh
```

**Need help?** → Check these:
- [`BITSTREAM_GENERATION_GUIDE.md`](BITSTREAM_GENERATION_GUIDE.md) - Comprehensive guide with troubleshooting
- [`CONFIG_REFERENCE.txt`](CONFIG_REFERENCE.txt) - Concise configuration reference

---

## 📚 Documentation Files

### Essential Reading

| File | Content | Time | For |
|------|---------|------|-----|
| [`README_BITSTREAM.md`](README_BITSTREAM.md) | Quick reference, methods, specs | 5 min | Quick overview |
| [`BITSTREAM_GENERATION_GUIDE.md`](BITSTREAM_GENERATION_GUIDE.md) | Step-by-step guide + troubleshooting | 20 min | Detailed instructions |
| [`CONFIG_REFERENCE.txt`](CONFIG_REFERENCE.txt) | Copy-paste commands + device specs | 10 min | Configuration reference |

### Advanced Reference

| File | Content |
|------|---------|
| [`flow.json`](flow.json) | F4PGA design flow configuration (technical) |
| Makefile | Make-based build system documentation |
| `build.sh` | Detailed bash script with logging |

---

## 🚀 Build Scripts

### Quickstart Script (Recommended) ⭐

**File**: [`quickstart-bitstream.sh`](quickstart-bitstream.sh)

**Usage**:
```bash
# Full build
bash quickstart-bitstream.sh

# Build and program FPGA
bash quickstart-bitstream.sh --program

# Synthesis only
bash quickstart-bitstream.sh --synthesis-only

# Clean artifacts
bash quickstart-bitstream.sh --clean

# Show help
bash quickstart-bitstream.sh --help
```

**Features**:
- ✅ Automatic environment verification
- ✅ Color-coded progress output
- ✅ Error checking at each step
- ✅ Optional FPGA programming
- ✅ ~8-30 minute build time

### Makefile Build System

**File**: `Makefile`

**Usage**:
```bash
make build              # Full build
make synthesis          # Synthesis only
make pnr               # Place & route
make generate_bitstream # Bitstream generation
make program           # Program FPGA
make clean             # Remove artifacts
make help              # Show targets
```

### Build Script

**File**: `build.sh`

**Usage**:
```bash
bash build.sh              # Full build
bash build.sh --synthesis  # Synthesis only
bash build.sh --pnr       # PnR only
bash build.sh --program   # Program FPGA
bash build.sh --clean     # Clean
```

---

## ⚙️ Configuration Files

| File | Purpose |
|------|---------|
| [`flow.json`](flow.json) | **KEY FILE** - F4PGA design flow orchestration |
| [`arty100t.xdc`](arty100t.xdc) | Pin and timing constraints for Arty A7-100T |

---

## 📁 Input & Output

### Input Files

Located in parent directories:

```
rtl/
  ├── core/          - RISC-V processor cores
  ├── memory/        - Memory modules
  ├── cache/         - L1 cache implementations
  ├── coherence/     - Coherence protocol controller
  ├── bus/           - AXI4-Lite bus fabric
  ├── peripheral/    - UART and GPIO modules
  └── top/           - Top-level integration
```

### Output Files

Generated in `build/` directory:

```
build/
├── riscv_soc_arty100t.bit      ← FPGA BITSTREAM (ready to program)
├── riscv_soc_arty100t.json     - Synthesis output
├── riscv_soc_arty100t.net.json - Place & Route output
├── riscv_soc_arty100t.eblif    - Packed design
├── riscv_soc_arty100t.place    - Placement output
├── riscv_soc_arty100t.route    - Routing output
└── reports/
    ├── synth_stat.json         - Synthesis statistics
    ├── timing.rpt              - Timing report
    └── pnr.rpt                 - Place & Route report
```

---

## 🔧 Quick Commands

### Setup (First Time Only)
```bash
cd ~/f4pga-examples
export F4PGA_INSTALL_DIR=~/opt/f4pga
export FPGA_FAM="xc7"
source "$F4PGA_INSTALL_DIR/$FPGA_FAM/conda/etc/profile.d/conda.sh"
conda env create -f xc7/environment.yml
```

### Every Session
```bash
cd ~/f4pga-examples
export F4PGA_INSTALL_DIR=~/opt/f4pga
export FPGA_FAM="xc7"
source "$F4PGA_INSTALL_DIR/$FPGA_FAM/conda/etc/profile.d/conda.sh"
conda activate xc7
cd xc7/RISC-V-SoC-with-Coherent-Memory-Subsystem/fpga/f4pga
```

### Build Bitstream
```bash
bash quickstart-bitstream.sh
```

### Program FPGA
```bash
bash quickstart-bitstream.sh --program
```

---

## 🎯 Common Tasks

### Task 1: Build Bitstream
1. Activate F4PGA environment (see "Every Session" above)
2. Run: `bash quickstart-bitstream.sh`
3. Wait 8-30 minutes
4. Find output: `build/riscv_soc_arty100t.bit`

### Task 2: Build and Program FPGA
1. Activate F4PGA environment
2. Connect Arty A7-100T via USB
3. Run: `bash quickstart-bitstream.sh --program`
4. FPGA will be programmed automatically

### Task 3: Rebuild After RTL Changes
1. Make your changes to RTL files
2. Run: `bash quickstart-bitstream.sh --clean`
3. Run: `bash quickstart-bitstream.sh`
4. Reprogram FPGA

### Task 4: Debug Build Issues
1. Read [`BITSTREAM_GENERATION_GUIDE.md`](BITSTREAM_GENERATION_GUIDE.md) troubleshooting section
2. Check [`CONFIG_REFERENCE.txt`](CONFIG_REFERENCE.txt) for configuration
3. Run with verbose output: `bash build.sh -v`

---

## 📊 Build Pipeline Overview

```
Step 1: Synthesis (Yosys)
  Input:  RTL files (Verilog/SystemVerilog)
  Output: riscv_soc_arty100t.json
  Time:   2-5 minutes

Step 2: Pack (F4PGA)
  Input:  JSON netlist
  Output: riscv_soc_arty100t.eblif
  Time:   1-3 minutes

Step 3: Place (F4PGA)
  Input:  Packed design
  Output: riscv_soc_arty100t.place
  Time:   1-2 minutes

Step 4: Route (F4PGA)
  Input:  Placement
  Output: riscv_soc_arty100t.route
  Time:   1-5 minutes

Step 5: Bitstream (F4PGA)
  Input:  Routed design
  Output: riscv_soc_arty100t.bit ← READY TO PROGRAM!
  Time:   <1 minute

Total Time: 8-30 minutes
```

---

## 🎓 Learning Resources

### Documentation in This Directory
- **Quick Start**: `README_BITSTREAM.md`
- **Detailed Guide**: `BITSTREAM_GENERATION_GUIDE.md`
- **Configuration**: `CONFIG_REFERENCE.txt`
- **Design Flow**: `flow.json` (technical)

### External Resources
- **F4PGA**: https://github.com/chipsalliance/f4pga
- **Arty A7-100T**: https://reference.digilentinc.com/reference/programmable-logic/arty-a7/reference
- **Yosys**: http://www.clifford.at/yosys/
- **nextpnr**: https://github.com/YosysHQ/nextpnr

---

## ❓ FAQ - Quick Answers

**Q: What's the fastest way to build?**
A: `bash quickstart-bitstream.sh` - handles everything automatically

**Q: How long does it take?**
A: 8-30 minutes depending on your system speed

**Q: Do I need Vivado?**
A: No - F4PGA is open-source and doesn't require Vivado

**Q: Can I modify the design?**
A: Yes - edit RTL files and rebuild with `bash quickstart-bitstream.sh`

**Q: How do I program the FPGA?**
A: `bash quickstart-bitstream.sh --program` (requires USB connection)

**Q: What if it fails?**
A: Check `BITSTREAM_GENERATION_GUIDE.md` troubleshooting section

**Q: Where's the bitstream file?**
A: `build/riscv_soc_arty100t.bit` after successful build

---

## 🚨 Troubleshooting Quick Links

| Issue | Solution |
|-------|----------|
| "Command not found: yosys" | Activate conda: `conda activate xc7` |
| "Device YAML not found" | Check F4PGA installation |
| Build hangs/freezes | Check system RAM with `free -h` |
| JTAG device not found | Connect USB, check with `lsusb \| grep Digilent` |
| Full details | See `BITSTREAM_GENERATION_GUIDE.md` |

---

## 📋 File Organization

```
fpga/f4pga/          ← YOU ARE HERE
├── INDEX.md          ← This file (navigation guide)
├── README_BITSTREAM.md
├── BITSTREAM_GENERATION_GUIDE.md
├── CONFIG_REFERENCE.txt
│
├── flow.json         ← KEY FILE
├── arty100t.xdc
├── Makefile
├── build.sh
├── quickstart-bitstream.sh
│
└── build/            ← Created by build process
    ├── *.bit         ← FPGA bitstream
    ├── *.json, etc.
    └── reports/
```

---

## ✅ Status Checklist

Before building, verify:

- [ ] In correct directory: `fpga/f4pga/`
- [ ] F4PGA installed: `echo $F4PGA_INSTALL_DIR`
- [ ] Conda environment ready: `conda activate xc7`
- [ ] Tools available: `which yosys`, `which nextpnr-xilinx`
- [ ] RTL files exist: `ls ../../rtl/*/`
- [ ] Constraints file exists: `ls arty100t.xdc`
- [ ] Disk space available: `df -h`
- [ ] RAM available: `free -h` (need ~4-8 GB)

---

## 🚀 Ready to Build?

1. **First time?** Read [`README_BITSTREAM.md`](README_BITSTREAM.md)
2. **Need details?** See [`BITSTREAM_GENERATION_GUIDE.md`](BITSTREAM_GENERATION_GUIDE.md)
3. **Just build it!** Run:
   ```bash
   bash quickstart-bitstream.sh --program
   ```

---

## 📞 Need Help?

1. **Quick reference**: `CONFIG_REFERENCE.txt`
2. **Detailed guide**: `BITSTREAM_GENERATION_GUIDE.md`
3. **Quick start**: `README_BITSTREAM.md`
4. **Configuration**: `flow.json`
5. **Troubleshooting**: See guides above

---

## 🎉 Summary

You have everything needed to:
✅ Generate FPGA bitstream
✅ Program Arty A7-100T board
✅ Test your design
✅ Debug and iterate

**Start here**: `bash quickstart-bitstream.sh`

---

**Last Updated**: 2026-09-09
**Target**: XC7A100T-CSG324 (Arty A7-100T)
**Status**: Ready ✓
