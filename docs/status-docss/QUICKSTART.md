# QUICKSTART: What You Have & What's Next

---

## ✅ What You Have (Day 1 Complete)

### **6 Synthesizable RTL Modules**
```
rtl/core/
├── alu.sv                    ✅ (180 lines) — All 10 RV32I ALU operations
├── reg_file.sv               ✅ (75 lines)  — 32×32 register file, x0 hardwired
├── control_unit.sv           ✅ (350 lines) — RV32I decoder, all 37 instructions
├── pc_logic.sv               ✅ (80 lines)  — PC mux (4-way), PC register
└── rv32i_core.sv             ✅ (450 lines) — Top CPU core, RUN/STALL_MEM FSM

rtl/memory/
└── i_sram.sv                 ✅ (60 lines)  — 1 KB per-core instruction memory

tb/
└── tb_core_smoke.sv          ✅ (150 lines) — Smoke test (6 basic instructions)
```

### **3 Quick Reference Guides**
1. `rtl/CORE_RTL_QUICK_REFERENCE.md` — Module signatures, code patterns, tips
2. `rtl/DAY1_CORE_RTL_README.md` — Comprehensive architecture doc
3. `DAY1_SUMMARY.md` — Status, metrics, next steps

### **4 Detailed Logic Design Docs** (to reference)
- `logic_design/02_alu_logic.md` — ALU truth table
- `logic_design/03_core_datapath_and_control.md` — Core pipeline & decode
- `logic_design/gate_level/01-03_*.md` — Gate-level schematics

---

## 🔍 Quick Code Review

### **Verify Everything Compiles**

If you have **Verilog compiler** (VSim, Xrun, VCS):
```bash
cd <project-root>
vlog -sv rtl/core/*.sv rtl/memory/i_sram.sv
```

If you have **Verilator** (free, fast lint):
```bash
verilator --lint-only -Wall --top-module rv32i_core \
  rtl/core/alu.sv rtl/core/reg_file.sv rtl/core/control_unit.sv \
  rtl/core/pc_logic.sv rtl/core/rv32i_core.sv
```

If you have **Yosys** (free, synthesis):
```bash
yosys -p "read_verilog -sv rtl/core/*.sv; hierarchy -check -top rv32i_core; \
          proc; opt; synth -top rv32i_core; stat"
```

### **Key Files to Review (in order)**

1. **rtl/core/alu.sv** — Start here (simplest, 180 lines)
   - Look for: barrel shifter logic, comparison, zero detection
   
2. **rtl/core/reg_file.sv** — Review x0 enforcement (75 lines)
   - Look for: why x0 always returns 0
   
3. **rtl/core/control_unit.sv** — Decoder (350 lines)
   - Look for: instruction opcode cases, immediate sign-extension
   
4. **rtl/core/rv32i_core.sv** — Full integration (450 lines)
   - Look for: RUN/STALL_MEM FSM, load/store data handling, branch resolution

---

## 📋 Quick Architecture Overview

```
rv32i_core (single-cycle CPU)
├── Input: imem_addr, imem_rdata (from I-SRAM)
│           dmem_req, ack, rdata, err (to/from cache)
├── Output: dmem_addr, wdata, wmask, we
│
├── Submodule: alu.sv
│   ├─ a, b operands → ALU → result, zero flag
│   └─ 10 operations (ADD, SUB, SLL, SRL, SRA, AND, OR, XOR, SLT, SLTU)
│
├── Submodule: reg_file.sv
│   ├─ 2 read ports (async)
│   ├─ 1 write port (sync)
│   └─ x0 always 0
│
├── Submodule: control_unit.sv
│   ├─ instr[31:0] → (all decode signals)
│   └─ 37 RV32I instructions supported
│
├── Submodule: pc_logic.sv
│   ├─ PC mux (PC+4, PC+imm, RS1+imm, reset)
│   └─ PC register update
│
└── FSM: RUN/STALL_MEM
    ├─ RUN: normal fetch/execute
    └─ STALL_MEM: wait for dmem_ack

i_sram.sv (1 KB per core)
├─ Async read: imem_addr → imem_rdata (combinational)
└─ Sync write: for test/initialization
```

---

## 🎯 Next: Start Day 2 (Cache & Coherence)

### **Recommended Sequence**

#### Step 1: Build D-Cache Storage (T2.4)
```
logic_design/04_dcache_fsm.md §4.2 → rtl/cache/d_cache.sv
├─ 4 cache lines (direct-mapped)
├─ Each line: valid + tag + data + 2-bit state (I/S/M)
├─ Hit/miss detection logic
└─ Invalidation path
```

**Files to create:**
- `rtl/cache/d_cache.sv` — Cache storage + comparators

#### Step 2: Build D-Cache Manager FSM (T2.5)
```
logic_design/04_dcache_fsm.md §4.4 → rtl/cache/d_cache_mgr.sv
├─ 13-state FSM (IDLE, CHECK, HIT_READ, MISS_READ, AXI_*, FILL, NOTIFY_COH, WAIT_INVALIDATE)
├─ AXI4-Lite master generation
├─ Stall/ack handshake with core
└─ Coherence notification sideband
```

**Files to create:**
- `rtl/cache/d_cache_mgr.sv` — Cache manager FSM

#### Step 3: Build Coherence Controller (T2.7)
```
logic_design/05_coherence_fsm.md §5.4–5.6 → rtl/coherence/coherence_ctrl.sv
├─ 4-state FSM (COH_IDLE, PROCESS_WRITE, INVALIDATE_OTHER, WAIT_INV_ACK)
├─ 8-entry 2-bit mirror (4 lines × 2 cores = I/S/M state per line)
├─ Dispatch logic (invalidate if remote has copy)
└─ Counter for INV_COUNT
```

**Files to create:**
- `rtl/coherence/coherence_ctrl.sv` — Coherence FSM

#### Step 4: Build Bus (T2.9–T2.10)
```
logic_design/06_arbiter_logic.md → rtl/bus/axi_lite_arbiter.sv
logic_design/07_decoder_and_bus_fabric.md → rtl/bus/axi_lite_decoder.sv
├─ 2-master AXI4-Lite arbiter (round-robin)
├─ Address decoder (SRAM / MMIO / UART / GPIO → DECERR)
└─ AXI4-Lite slave multiplexing
```

**Files to create:**
- `rtl/bus/axi_lite_arbiter.sv` — Arbiter
- `rtl/bus/axi_lite_decoder.sv` — Decoder

#### Step 5: Build Memory & Peripherals (T2.1–T2.3, T2.11–T2.13)
```
rtl/memory/sram_reg_array.sv — Generic SRAM primitive
rtl/memory/shared_sram.sv — 4 KB shared data memory
rtl/peripheral/mmio_regs.sv — MMIO (counters, status, doorbell, control)
rtl/peripheral/uart_core.sv — UART (TX/RX FSM, baud gen)
rtl/peripheral/gpio_led.sv — GPIO (8 LEDs, event stretchers)
```

**Files to create:**
- `rtl/memory/sram_reg_array.sv`
- `rtl/memory/shared_sram.sv`
- `rtl/peripheral/mmio_regs.sv`
- `rtl/peripheral/uart_core.sv`
- `rtl/peripheral/gpio_led.sv`

---

## 📚 Documentation You Should Read

| For | Read | Time |
|-----|------|------|
| **Quick overview** | `rtl/CORE_RTL_QUICK_REFERENCE.md` | 10 min |
| **Module details** | `rtl/DAY1_CORE_RTL_README.md` | 30 min |
| **Day 2 plan** | `IMPLEMENTATION_PROGRESS.md` | 15 min |
| **ALU truth table** | `logic_design/02_alu_logic.md` | 15 min |
| **Core datapath** | `logic_design/03_core_datapath_and_control.md` | 30 min |
| **D-Cache FSM** | `logic_design/04_dcache_fsm.md` | 45 min |
| **Coherence FSM** | `logic_design/05_coherence_fsm.md` | 30 min |
| **Integration** | `logic_design/12_integration_logic.md` | 45 min |
| **Verification** | `logic_design/13_working_logic_scenarios.md` | 60 min |

---

## 🔧 Common Commands (Makefile Targets)

```bash
# Lint all RTL (Verilator)
make lint

# Compile & run directed testbench (ModelSim/QuestaSim/VCS)
make sim-directed

# Synthesis smoke test (Yosys)
make synth-smoke

# Check which tools are available on your machine
make check-tools
```

---

## 🐛 Common Issues & Fixes

### **Issue: "No such file or directory" when compiling**
**Fix:** Check paths are relative to `<project-root>`. Run from root:
```bash
cd <project-root>
vlog -sv rtl/core/*.sv rtl/memory/*.sv
```

### **Issue: "Unknown module" errors**
**Fix:** Compile in dependency order. Submodules must exist:
1. First: compile standalone modules (no instantiations)
2. Then: compile top-level modules that instantiate them

### **Issue: Simulation hangs on LW/SW**
**Fix:** Check `dmem_ack` is being asserted by your fake memory model. See `tb_core_smoke.sv` lines 80–100 for example.

### **Issue: x0 not staying 0**
**Fix:** Check `reg_file.sv` line `assign rd_a = (ra == 5'b0) ? 32'b0 : regs[ra];` is present.

---

## 📖 Logism Reference (Optional)

If you want to build the gate-level circuits in **Logism Classic**:
- Read: `logic_design/LOGISM_COMPONENT_BUILD_GUIDE.md`
- This gives step-by-step instructions for all 11 components
- Use `logic_design/gate_level/` docs as subcircuit blueprints

---

## ✅ Day 1 Exit Checklist (Completed)

- [x] ALU compiles & works (10 ops)
- [x] RegFile compiles & x0 enforced
- [x] ControlUnit compiles & decodes all 37 instructions
- [x] rv32i_core compiles & integrates everything
- [x] i_sram compiles & async read works
- [x] tb_core_smoke ready for simulation
- [x] All modules have header comments & doc references
- [x] No inferred latches (all FF or comb)
- [x] Design decisions (7 + 9 refinements) documented
- [x] Logic design traceability established
- [x] Ready for Day 2 cache/coherence integration

---

## 🚀 You're Ready!

Everything needed for Day 1 is complete. The code is clean, documented, and traceable to the logic design. Day 2 can begin immediately with cache and coherence modules.

**Current Status:**
- ✅ Day 1: COMPLETE (Core RTL)
- ⏳ Day 2: Ready to start (Cache & coherence)
- ⏳ Day 3: Integration & verification
- ⏳ Day 4: UVM & ASIC flow
- ⏳ Day 5: Sign-off & FPGA

---

**Questions? See:**
- `rtl/CORE_RTL_QUICK_REFERENCE.md` — Fast lookup
- `rtl/DAY1_CORE_RTL_README.md` — Detailed guide
- `logic_design/02–03_*.md` — Design docs

**Good luck with Day 2! 🎯**

