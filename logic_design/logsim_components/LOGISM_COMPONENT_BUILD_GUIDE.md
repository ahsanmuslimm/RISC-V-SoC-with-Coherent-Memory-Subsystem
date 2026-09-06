# LOGISM CLASSIC: Component Build Guide & Integration Plan
## Dual-Core RV32I SoC with Coherent Memory Subsystem

**Project:** Capstone Project 05  
**Target:** Logism Classic  
**Timeline:** Sequential component builds → Full integration  
**Date:** September 6, 2026  

---

## PART I: PROJECT OVERVIEW & BUILD STRATEGY

### 1. System Architecture Recap

Your dual-core RISC-V SoC consists of **11 major stand-alone components** that will be built incrementally in Logism and then integrated into a single `.circ` project file. The hierarchy flows from **primitive components → core components → subsystems → top-level integration**.

```
┌──────────────────────────────────────────────────────────────────┐
│                    riscv_soc_top.circ (Main Project)              │
├──────────────────────────────────────────────────────────────────┤
│  ├─ COMPUTE DOMAIN                                               │
│  │  ├─ RV32I Core 0 (single-cycle)                              │
│  │  │  ├─ ALU (arithmetic/logical/shift operations)             │
│  │  │  ├─ RegFile (32 × 32-bit + x0=0 enforcement)             │
│  │  │  ├─ Control Unit (RV32I decoder table)                    │
│  │  │  ├─ PC Logic (fetch, branch, jump)                        │
│  │  │  └─ Core FSM (RUN/STALL_MEM, 2 states)                   │
│  │  ├─ D-Cache Manager 0 (13-state FSM)                        │
│  │  ├─ I-SRAM 0 (256×32, async read)                           │
│  │  └─ D-Cache 0 (4 lines, direct-mapped, I/S/M state)         │
│  │                                                              │
│  ├─ RV32I Core 1 (identical structure)                         │
│  │  ├─ ALU                                                      │
│  │  ├─ RegFile                                                  │
│  │  ├─ Control Unit                                             │
│  │  ├─ PC Logic                                                 │
│  │  ├─ Core FSM                                                 │
│  │  ├─ D-Cache Manager 1 (13-state FSM)                        │
│  │  ├─ I-SRAM 1 (256×32, async read)                           │
│  │  └─ D-Cache 1                                                │
│  │                                                              │
│  ├─ INTERCONNECT DOMAIN                                        │
│  │  ├─ AXI4-Lite Arbiter (2 masters → shared slave)           │
│  │  └─ AXI4-Lite Address Decoder                              │
│  │                                                              │
│  ├─ COHERENCE DOMAIN                                           │
│  │  └─ Coherence Controller (4-state FSM, 8-entry mirror)     │
│  │                                                              │
│  └─ MEMORY & PERIPHERALS DOMAIN                               │
│     ├─ Shared Data SRAM (1024×32, sync R/W)                   │
│     ├─ MMIO Registers (counters, status, control)             │
│     ├─ UART Core (115200 8N1)                                 │
│     └─ GPIO/LED (8 outputs)                                   │
│                                                              │
└──────────────────────────────────────────────────────────────────┘
```

### 2. Build Phases (Recommended Sequence)

| Phase | Components | Focus | Est. Logism subcircuits |
|-------|------------|-------|------------------------|
| **Phase 1** | Primitives | Simple gates, adders, MUXes, comparators | ALU building blocks |
| **Phase 2** | Core Elements | ALU, RegFile, PC logic, Control decoder | 50 subcircuits |
| **Phase 3** | Single Core | Integrate Phase 2 into 1 RV32I core + I-SRAM | 10 subcircuits |
| **Phase 4** | Caches & Coherence | D-Cache (4 lines), D-Cache Manager (13-state FSM), Coherence (4-state FSM) | 30 subcircuits |
| **Phase 5** | Bus & Memory | Arbiter, Decoder, Shared SRAM, MMIO, UART, GPIO | 20 subcircuits |
| **Phase 6** | Integration | Wire all into `riscv_soc_top`; add test vectors | 1 top circuit |
| **Phase 7** | Verification | Smoke tests per scenario (13.1–13.9 from docs) | Test harness |

---

## PART II: STAND-ALONE COMPONENTS FOR LOGISM

### 3. Component Inventory: 11 Major Building Blocks

Each component below is **self-contained** and can be built as a separate Logism subcircuit. Dependencies are listed to guide build order.

---

#### **COMPONENT 1: ALU (Arithmetic Logic Unit)**

**Purpose:** Execute all RV32I arithmetic, logical, and shift operations.

**Location in project:** `logic_design/02_alu_logic.md` + `logic_design/gate_level/01_alu_gate_level.md`

**Logism Subcircuits Needed:**
- `Adder32` — 32-bit binary adder (RCA or faster tree)
- `Subtractor32` — 32-bit subtractor (2's complement)
- `BarrelShifter32` — Barrel shifter for SLL/SRL/SRA
- `Comparator32` — 32-bit comparator for SLT/SLTU/BEQ/BNE/BLT/BGE/BLTU/BGEU
- `ZeroDetect32` — Output 1 if all 32 bits are 0 (used for branch resolution)
- `ALU` — Top-level MUX (function selector selects 32-bit output from above)

**Inputs:**
- `a[31:0]` — operand A
- `b[31:0]` — operand B
- `func[3:0]` — operation select (encodes RV32I ALU ops, see doc 02 §2.3)

**Outputs:**
- `result[31:0]` — 32-bit result
- `zero` — 1 if result == 0 (for BEQ/BNE/BLTU/BGE resolution)

**Approx. Logism Gate Count:** ~60 primitives

**Dependencies:** None (primitives only)

**Build Notes:**
1. Start with a basic 32-bit adder using Logism's **Adder** component or ripple-carry
2. Add a subtractor using NOT gates + 1-bit carry-in (2's complement)
3. Implement barrel shifter using cascaded MUXes (5 levels for 32 positions)
4. Build comparators: use subtraction + sign/zero flag detection
5. Create a 32-bit 4:1 MUX (or 16:1 for all ops) to select output based on `func[3:0]`

**Test in isolation:**
- ADD: a=1, b=2 → result=3
- SLL: a=1, b=2 → result=4 (1 << 2)
- BEQ flags: a=1, b=1 → zero=1

---

#### **COMPONENT 2: Register File (32×32)**

**Purpose:** Store CPU state (registers x0–x31); 2 read ports, 1 write port.

**Location in project:** `logic_design/03_core_datapath_and_control.md` + `logic_design/gate_level/02_regfile_pc_gate_level.md`

**Logism Subcircuits Needed:**
- `RegFile32` — 32 × 32-bit register array with:
  - 2 read ports (combinational)
  - 1 write port (synchronous, on `posedge clk`)
  - x0 hardwired to 0 (write ignored, read always 0)

**Inputs:**
- `clk` — clock (write on rising edge)
- `rst_n` — reset (async active-low)
- `ra[4:0]` — read address A
- `rb[4:0]` — read address B
- `wa[4:0]` — write address
- `wd[31:0]` — write data
- `we` — write enable

**Outputs:**
- `rd_a[31:0]` — data from register ra
- `rd_b[31:0]` — data from register rb

**Approx. Logism Gate Count:** ~100 primitives (32 registers × 32 bits + decoders + MUXes)

**Dependencies:** None (uses Logism Register component + gates)

**Build Notes:**
1. Create 32 × **Register(32-bit)** components, one per register
2. Add async reset to each (clear input, active-low)
3. Add x0 enforcement: **NOT gate on write address decoder output for register 0**
4. Create a 5-to-32 decoder for write address (OR multiple AND gates)
5. Create two 32:1 MUXes (one for each read port) using the read addresses as selectors
6. Final port mapping: (ra,rb,wa,wd,we) → (rd_a, rd_b)

**Test in isolation:**
- Write x1=5, then read x1 → rd_a=5
- Write x0=10, then read x0 → rd_a=0 (enforced)
- Simultaneous read from ra and rb

---

#### **COMPONENT 3: PC Logic (Program Counter)**

**Purpose:** Manage fetch address; implement jumps, branches, sequential increment.

**Location in project:** `logic_design/03_core_datapath_and_control.md` + `logic_design/gate_level/02_regfile_pc_gate_level.md`

**Logism Subcircuits Needed:**
- `PCLogic` — PC update multiplexer:
  - `PC + 4` (sequential fetch)
  - `PC + imm` (branch-taken)
  - `RS1 + imm` (JALR indirect)
  - Reset value (0x0000_0000)

**Inputs:**
- `clk`, `rst_n`
- `pc_sel[1:0]` — select PC source (0=+4, 1=+imm, 2=RS1+imm, 3=reset)
- `pc_current[31:0]` — current PC (fed back from previous cycle)
- `imm[31:0]` — immediate value
- `rs1[31:0]` — register for JALR

**Outputs:**
- `pc_next[31:0]` — next PC to fetch
- `pc_plus_4[31:0]` — PC+4 for link register (JAL/JALR)

**Approx. Logism Gate Count:** ~20 primitives

**Dependencies:** Adder32 (from ALU)

**Build Notes:**
1. Instantiate 4 **Adder32** blocks:
   - Adder 1: pc + 4 (imm hardcoded to 4)
   - Adder 2: pc + imm (branch)
   - Adder 3: rs1 + imm (JALR)
   - Adder 4: for pc_plus_4 output (copy of Adder 1 output)
2. Create a 4:1 MUX selecting one of the 4 adder outputs via `pc_sel[1:0]`
3. Add register to hold PC (synchronously updated on clock)
4. Async reset to 0x0000_0000

**Test in isolation:**
- Sequential: pc_sel=0 → pc_next = pc + 4
- Branch-taken: pc_sel=1, imm=0x100 → pc_next = pc + 0x100
- Reset: rst_n=0 → pc_next = 0x0

---

#### **COMPONENT 4: Control Unit (RV32I Instruction Decoder)**

**Purpose:** Decode 32-bit RV32I instruction into control signals (ALU op, write-back sel, memory op, branch flags, etc.).

**Location in project:** `logic_design/03_core_datapath_and_control.md` + `logic_design/gate_level/03_control_unit_gate_level.md`

**Logism Subcircuits Needed:**
- `ControlUnit` — combinational decoder:
  - Opcode comparators
  - Func3/Func7 comparators
  - Logic tables for each signal
- `ImmGen` — immediate value generator (sign-extend, shift, select based on instruction type)
- `LoadResize` — load data resize (byte/halfword/word expansion)
- `StoreRotate` — store data rotation (align based on address[1:0])
- `CoreFSM` — core RUN/STALL_MEM FSM (2 states, 1-bit register)

**Inputs:**
- `instr[31:0]` — instruction word
- `core_state` — RUN or STALL_MEM (from CoreFSM)
- `dmem_ack` — memory subsystem has completed access

**Outputs:**
- `alu_func[3:0]` — ALU operation select
- `rf_we` — register file write enable
- `rf_wa[4:0]` — register file write address (rd)
- `rf_wd_sel[1:0]` — write-back source (ALU result / load data / PC+4)
- `dmem_req` — data memory request
- `dmem_we` — write enable (1=store, 0=load)
- `pc_sel[1:0]` — PC mux select
- `imm[31:0]` — immediate value (sign-extended)
- `core_next_state` — next core FSM state
- (and branch flags for ALU zero comparison)

**Approx. Logism Gate Count:** ~100 primitives (ROM table + select logic)

**Dependencies:** None (combinational logic + simple FSM register)

**Build Notes:**
1. Use Logism's **ROM (Read-Only Memory)** component configured as 128×4 (covers opcode space for RV32I)
   - Alternative: build truth table with cascaded comparators and AND/OR logic
2. Break instruction into fields: opcode[6:0], rd[11:7], func3[14:12], rs1[19:15], rs2[24:20], func7[31:25]
3. For each instruction type (I/R/S/B/U/J), decode:
   - ALU operation
   - Register file controls
   - Memory controls
   - PC mux select
4. Implement immediate generation via sign-extension and shifting (splitters + bit-extend blocks)
5. Implement load/store lane logic: splitters to select byte/word, multiplexers to route

**Test in isolation:**
- ADDI x1, x0, 5: alu_func=ADD, rf_wa=1, rf_we=1, imm=5
- LW x2, 0(x1): dmem_req=1, dmem_we=0, rf_wa=2, rf_we=1
- BEQ x1, x2, label: comparator outputs branch condition

---

#### **COMPONENT 5: RV32I Single-Cycle Core**

**Purpose:** Integrate ALU + RegFile + PC + Control Unit into a working CPU core.

**Location in project:** `logic_design/03_core_datapath_and_control.md`

**Logism Subcircuits Needed:**
- `RV32I_Core` (top-level subcircuit that instantiates and wires Components 1–4)

**Inputs:**
- `clk`, `rst_n`
- `imem_addr[31:0]` → to I-SRAM (output, combinational)
- `imem_rdata[31:0]` ← from I-SRAM (input)
- `dmem_req`, `dmem_we`, `dmem_addr[31:0]`, `dmem_wdata[31:0]`, `dmem_wmask[3:0]` → to cache (outputs)
- `dmem_rdata[31:0]`, `dmem_ack`, `dmem_err` ← from cache (inputs)

**Outputs:**
- Program counter (for debugging)
- Register file state (for debugging)
- Instruction decode (for debugging)

**Approx. Logism Gate Count:** ~200 primitives (combining 1–4)

**Dependencies:** Components 1, 2, 3, 4

**Build Notes:**
1. Create a new Logism subcircuit named `RV32I_Core`
2. Instantiate:
   - 1× `ALU`
   - 1× `RegFile32`
   - 1× `PCLogic`
   - 1× `ControlUnit` (includes CoreFSM, ImmGen, LoadResize, StoreRotate)
   - 1× `I-SRAM` instance (or wire to top-level for now)
3. Wire datapath:
   - PC → I-SRAM addr (imem_addr)
   - I-SRAM output → ControlUnit (instr)
   - ControlUnit alu_func → ALU func input
   - RegFile ra/rb → ALU inputs and immediate gen
   - ALU result → register file write data (one of N sources)
   - Load data (dmem_rdata) → write-back mux
   - PC+4 → write-back mux (for JAL/JALR)
   - Branch flags from ALU → ControlUnit (for PC mux select)
4. Add tunnels for clk/rst_n (distributed globally)
5. Test with a simple instruction sequence

**Test in isolation:**
- Execute ADD x1, x2, x3 → x1 = x2 + x3
- Execute LW x1, 0(x2) → stall memory, wait for dmem_ack
- Execute BEQ x1, x2, label → branch condition resolved

---

#### **COMPONENT 6: Instruction SRAM (I-SRAM)**

**Purpose:** Private instruction memory (256×32 = 1 KB) with asynchronous read for single-cycle fetch.

**Location in project:** `logic_design/08_memory_subsystem.md` + `logic_design/gate_level/09_memory_gate_level.md`

**Logism Subcircuits Needed:**
- `SRAM_RegArray_Async` — parameterized register array (async read variant)
- One instance per core (×2 for dual-core, but build/test as Component 6a and 6b separately)

**Inputs:**
- `clk` (write clock)
- `rst_n` (async reset; typically inactive for memories, but included for hygiene)
- `raddr[9:2]` — read address (word-addressed, 256 locations)
- `waddr[9:2]` — write address (test/initialization only)
- `wdata[31:0]` — write data (test/initialization)
- `we` — write enable (1 for init, 0 during normal operation)

**Outputs:**
- `rdata[31:0]` — read data (combinational, no latency)

**Approx. Logisim Gate Count:** ~5 primitives (1 ROM component + mux for write port)

**Dependencies:** None (Logism RAM component)

**Build Notes:**
1. Use Logism's **RAM** component:
   - Capacity: 256 × 32-bit
   - Address width: 8-bit (selects 1 of 256 words)
   - Data width: 32-bit
   - Access type: **Asynchronous** (combinational read, no latency)
2. Single **Memory Editor** window for initialization (option: load `.hex` file)
3. Wire:
   - `raddr[7:0]` → RAM read address
   - `rdata[31:0]` ← RAM read output (directly to core's imem_rdata)
   - `waddr[7:0]`, `wdata[31:0]`, `we` → RAM write port (for simulation init)
4. Do NOT use write port during normal operation (set `we=0`)

**Test in isolation:**
- Pre-load instruction: ADDI x1, x0, 5 at address 0x0
- Read from address 0x0 → rdata = 0x00500093 (ADDI encoding)

---

#### **COMPONENT 7: D-Cache (Data Cache)**

**Purpose:** 4-line direct-mapped cache with coherence state tracking (I/S/M).

**Location in project:** `logic_design/04_dcache_fsm.md` + `logic_design/gate_level/04_dcache_store_gate_level.md`

**Logism Subcircuits Needed:**
- `DCacheStore` — 4 cache line registers (each line: valid bit + 28-bit tag + 32-bit data + 2-bit state)
- `TagCompare` — parallel tag comparison for all 4 lines
- `HitLogic` — determine hit/miss and select hit line

**Inputs:**
- `clk`, `rst_n`
- `addr[31:0]` — memory address (from core)
- `data_in[31:0]` — write data (from core)
- `state_in[1:0]` — new coherence state (from cache mgr FSM)
- `valid_in` — validity of new state
- `idx_we[3:0]` — which line to update (1-hot, from cache mgr FSM)
- `inv_idx` — line to invalidate (from coherence controller)
- `inv_we` — invalidation write enable

**Outputs:**
- `hit` — combinational hit signal (1 if tag matches any line and state != I)
- `miss` — combinational miss signal
- `hit_line_idx[1:0]` — index of hit line (for mux)
- `line_valid[3:0]` — valid bits of all 4 lines (to coherence controller)
- `line_state[1:0]` (×4) — coherence state of each line (to coherence controller)
- `hit_data[31:0]` — data from hit line (combinational)

**Approx. Logism Gate Count:** ~40 primitives (4 registers + comparators + muxes)

**Dependencies:** None (uses Logism Register and Comparator)

**Build Notes:**
1. Create 4 **Register(64-bit)** components, one per cache line:
   - Bits[63:62] = coherence state (I/S/M encoding: I=00, S=01, M=10)
   - Bits[61:34] = tag (28 bits, for addr[31:4])
   - Bits[33:32] = reserved
   - Bits[31:0] = data
2. Add valid bit separately (1 bit per line) as a **Register(1-bit)**
3. Build tag comparator: split input `addr[31:4]` into 28-bit tag, compare against each line's tag register via **Comparator(28-bit)** ×4
4. Combine tag match + valid + (state != I) to get `hit` per line: `hit_i = tag_match_i && valid_i && (state_i != 2'b00)`
5. OR all 4 hit signals: `hit = hit_0 | hit_1 | hit_2 | hit_3`
6. Use a 4:1 **MUX(32-bit)** to select data from hit line (selector = hit line index)
7. Invalidation logic: OR the `inv_we` condition into the appropriate line's valid bit clear

**Test in isolation:**
- Load from 0x0000_0004 (tag=0, idx=1) → miss (all I)
- After fill (mgr loads line): read 0x0000_0004 → hit, data returned
- Another load 0x0000_0008 (tag=0, idx=2) → miss (different line)

---

#### **COMPONENT 8: D-Cache Manager FSM (13-State)**

**Purpose:** Control cache operations: hit/miss sequencing, AXI4-Lite transaction generation, coherence handshake.

**Location in project:** `logic_design/04_dcache_fsm.md` + `logic_design/gate_level/05_dcache_mgr_fsm_gate_level.md`

**Logism Subcircuits Needed:**
- `DCacheMgrFSM` — 13-state FSM register (+ combinational state transition + output logic)

**Inputs:**
- `clk`, `rst_n`
- `dmem_req` — core request (level signal)
- `dmem_we` — write enable (1=store, 0=load)
- `dmem_addr[31:0]` — request address
- `dmem_wdata[31:0]` — write data
- `dmem_wmask[3:0]` — byte mask
- `hit` — cache hit signal
- `miss` — cache miss signal
- `arready, rvalid, bvalid, bresp[1:0]` — AXI slave response signals
- `rdata[31:0]` — AXI read data
- `coh_accept` — coherence controller accepts write notification
- `inv_valid` — coherence controller requests invalidation

**Outputs:**
- `dmem_rdata[31:0]` — core read data
- `dmem_ack` — core transaction acknowledged
- `dmem_err` — error (DECERR, SLVERR)
- `arvalid, araddr[31:0]` — AXI read address channel
- `rready` — ready for read data
- `awvalid, awaddr[31:0], wvalid, wdata[31:0], wstrb[3:0]` — AXI write address/data channels
- `bready` — ready for write response
- `write_notify` — write-through completed (to coherence)
- `write_addr[31:0]` — address written (to coherence)
- `fill_notify` — line filled to S/M (to coherence)
- `fill_idx[1:0]` — line index filled (to coherence)
- `inv_ack` — invalidation acknowledged (to coherence)
- `hit_event, miss_event, err_event` — pulse outputs for counters
- `bus_req` — request bus arbitration

**Approx. Logism Gate Count:** ~120 primitives (13-state register + mux trees + output logic)

**Dependencies:** None (pure FSM + combinational decoding)

**Build Notes:**
1. Create a **Register(4-bit)** to hold the 13-state encoding (states 0–12, with some unused)
2. Build a massive **combinational logic tree**:
   - Input: current state + all FSM inputs
   - Output: next state + all control outputs
   - Use Logism **Truth Table** builder or hand-wire with AND/OR/NOT gates
3. State encodings (from doc 04):
   - 0 = IDLE
   - 1 = CHECK
   - 2 = HIT_READ
   - 3 = HIT_WRITE
   - 4 = MISS_READ
   - 5 = AXI_AR
   - 6 = AXI_R
   - 7 = FILL
   - 8 = AXI_AW
   - 9 = AXI_W
   - 10 = AXI_B
   - 11 = NOTIFY_COH
   - 12 = WAIT_INVALIDATE
4. Transition table (from doc 04 §4.4):
   - IDLE + dmem_req → CHECK
   - CHECK (combinational) → HIT_READ or HIT_WRITE or MISS_READ (immediate next state)
   - HIT_READ → IDLE (return data same cycle if hit, ack immediately)
   - ... (full table in doc 04)
5. Output logic: each state generates its own control signals
   - MISS_READ: set bus_req=1, arvalid=1, miss_event=1
   - AXI_AR: hold arvalid until arready
   - AXI_R: wait for rvalid, capture rdata
   - ... (see doc 04 §4.4 tables)
6. At the combinational level, detect current/next state and mux outputs accordingly

**Test in isolation:**
- (Requires AXI bus simulator)
- Smoke: IDLE + dmem_req=1 (hit) → CHECK (combinational) → HIT_READ → ack + data (3 cycles total if hit immediate)

---

#### **COMPONENT 9: Coherence Controller FSM (4-State)**

**Purpose:** Track cache coherence state (I/S/M) for both cores; dispatch invalidations on writes.

**Location in project:** `logic_design/05_coherence_fsm.md` + `logic_design/gate_level/06_coherence_fsm_gate_level.md`

**Logism Subcircuits Needed:**
- `CohMirror` — 8-entry 2-bit register array (4 lines × 2 cores = 8 entries, I/S/M per entry)
- `CoherenceCtrl` — 4-state FSM
- `DispatchLogic` — combinational logic to decide whether to dispatch invalidation

**Inputs:**
- `clk`, `rst_n`
- `write_notify0, write_notify1` — write completion from each cache mgr (level signals)
- `write_addr0[31:0], write_addr1[31:0]` — addresses written
- `fill_notify0, fill_notify1` — load fill from each cache mgr (pulse)
- `fill_idx0[1:0], fill_idx1[1:0]` — line indices filled
- `inv_ack0, inv_ack1` — cache invalidation acknowledged (pulse)
- `state0_i[1:0]`, `state1_i[1:0]` (×4 lines) — **actual** coherence state from each cache (for dispatch truth)
- `valid0_i`, `valid1_i` (×4 lines) — valid bits from each cache
- `coh_enable` — enable coherence (MMIO control bit)

**Outputs:**
- `coh_accept0, coh_accept1` — write notify accepted (1-cycle pulse)
- `inv_valid0, inv_valid1` — invalidation request (level signal, held until ack)
- `inv_idx0[1:0], inv_idx1[1:0]` — line index to invalidate
- `inv_fire` — pulse when invalidation dispatched (for counters, LED2)
- `coh_status[15:0]` — 8 × 2-bit mirror snapshot (for MMIO read)

**Approx. Logism Gate Count:** ~100 primitives (8-entry register + 4-state FSM + dispatch tree)

**Dependencies:** None (FSM + register array)

**Build Notes:**
1. Create the **CohMirror** (8-entry 2-bit register):
   - `mirror[0][0:3]` = core 0 lines 0–3 (2 bits each)
   - `mirror[1][0:3]` = core 1 lines 0–3 (2 bits each)
   - Use 8 × **Register(2-bit)** components
2. Create the **4-state FSM**:
   - State encodings: COH_IDLE=0, PROCESS_WRITE=1, INVALIDATE_OTHER=2, WAIT_INV_ACK=3
   - Register(2-bit) to hold state
3. Build transition table (from doc 05 §5.6):
   - COH_IDLE + write_notify0 → PROCESS_WRITE (capture core=0, idx from addr)
   - COH_IDLE + write_notify1 → PROCESS_WRITE (capture core=1)
   - PROCESS_WRITE → COH_IDLE or INVALIDATE_OTHER (based on dispatch condition)
   - INVALIDATE_OTHER → WAIT_INV_ACK (immediately, pulse inv_valid + inv_fire)
   - WAIT_INV_ACK + inv_ack → COH_IDLE (clear inv_valid, update mirror[remote][idx]←I)
4. Dispatch logic (combinational):
   - Extract line index from write address: `idx = write_addr[3:2]`
   - Read remote mirror: `remote_mirror_state = mirror[~write_core][idx]`
   - Read actual remote state: `remote_actual_state = state_i[~write_core][idx]`
   - Dispatch condition: `(remote_mirror_state != I) OR (remote_actual_state != I) AND coh_enable`
5. Mirror update rules:
   - On `write_notify accepted`: `mirror[core][idx] ← M`
   - On `fill_notify`: `mirror[core][idx] ← S`
   - On `inv_ack`: `mirror[core][idx] ← I`

**Test in isolation:**
- Write from core 0 to line 0 (core 1 has S copy) → COH_IDLE→PROCESS_WRITE→INVALIDATE_OTHER→WAIT_INV_ACK
- inv_ack from core 1 → COH_IDLE, mirror[1][0]=I

---

#### **COMPONENT 10: AXI4-Lite Arbiter (2-Master Round-Robin)**

**Purpose:** Arbitrate requests from 2 cache managers to shared AXI4-Lite bus; provide grant-held sequencing.

**Location in project:** `logic_design/06_arbiter_logic.md` + `logic_design/gate_level/07_arbiter_gate_level.md`

**Logism Subcircuits Needed:**
- `AXIArbiter` — 2-to-1 multiplexer with round-robin grant logic
- `ArbFSM` — 2-state FSM (ARB_IDLE, ARB_G0 or ARB_G1)
- `AXIMux` — multiplexer selecting active master's AXI channels

**Inputs:**
- `clk`, `rst_n`
- `m0_bus_req, m1_bus_req` — bus request from each master (level signals)
- All AXI4-Lite channels from both masters (m0_* and m1_*)

**Outputs:**
- `m0_grant, m1_grant` — grant to each master (1 at a time)
- `s_awvalid, s_awaddr, s_wvalid, s_wdata, s_wstrb, s_arvalid, s_araddr` — muxed AXI channels to shared slave
- `s_awready, s_wready, s_bvalid, s_bresp, s_arready, s_rvalid, s_rdata, s_rresp` — slave responses fed back to winners

**Approx. Logism Gate Count:** ~50 primitives (1-bit grant register + mux trees)

**Dependencies:** None (FSM + MUX logic)

**Build Notes:**
1. Create a 1-bit **Register** to hold the preference (`pref` bit):
   - pref=0 → prioritize core 0 (if both request)
   - pref=1 → prioritize core 1 (if both request)
2. Build grant logic (combinational):
   - If pref=0:
     - If m0_req: grant0=1, grant1=0
     - Else if m1_req: grant1=1, grant0=0
     - Else: no grant
   - If pref=1: reverse priority
3. On **any grant completion** (b_resp or r_resp accepted), flip `pref` at next clock edge
4. Build large **2:1 MUXes** for all AXI channels:
   - If grant0: route m0_* signals to s_*
   - If grant1: route m1_* signals to s_*
5. Route slave responses back:
   - If grant0: route s_awready/wready/bvalid/arready/rvalid back to m0_
   - If grant1: route back to m1_

**Test in isolation:**
- m0_req=1, m1_req=0 → grant0=1, grant1=0 (master 0 wins)
- After transaction: pref flips
- m0_req=1, m1_req=1 → next, grant1=1, grant0=0 (round-robin)

---

#### **COMPONENT 11: Address Decoder & Memory-Mapped Subsystem**

**Purpose:** Decode AXI address into slave selection (SRAM/MMIO/UART/GPIO/DECERR); route signals accordingly.

**Location in project:** `logic_design/07_decoder_and_bus_fabric.md` + `logic_design/gate_level/08_decoder_gate_level.md`

**Logism Subcircuits Needed:**
- `AddrDecoder` — combinational decoder (address comparators + select logic)
- `DECERRSlave` — FSM for unmapped addresses (returns SLVERR/DECERR)

**Inputs:**
- Shared AXI address: `s_awaddr[31:0]`, `s_araddr[31:0]`
- Shared AXI control: `s_awvalid, s_arvalid, s_wvalid, s_bready, s_rready`
- All slave AXI responses

**Outputs:**
- `sel_sram, sel_mmio, sel_uart, sel_gpio` — slave selection (1-hot)
- Routed AXI channels to each slave (s_* → slave_*)
- Slave responses back to shared bus

**Approx. Logism Gate Count:** ~45 primitives

**Dependencies:** Component 10 (Arbiter)

**Build Notes:**
1. Decode address ranges (from doc 11 §11.1):
   - `0x0000_0000 – 0x0000_0FFF` → SRAM (sel_sram)
   - `0x0001_0000 – 0x0001_00FF` → MMIO (sel_mmio)
   - `0x0001_0100 – 0x0001_01FF` → UART (sel_uart)
   - `0x0001_0200 – 0x0001_02FF` → GPIO (sel_gpio)
   - Anything else → DECERR (sel_decerr)
2. Build address comparators:
   - For SRAM: check if addr[31:12] == 0x00000 && addr[11:0] < 0x1000
   - For MMIO: check if addr[31:8] == 0x00_0100
   - For UART: check if addr[31:8] == 0x00_0101
   - For GPIO: check if addr[31:8] == 0x00_0102
3. Use **Comparator** blocks for each range
4. Create a priority encoder or cascaded logic to output sel_* (exactly one active)
5. Build MUXes to route AXI channels based on sel_* outputs
6. DECERR slave: on any address outside ranges:
   - Hold bvalid=0 or rvalid=0 until upstream ready
   - Return bresp=2'b11 or rresp=2'b11 on transaction

**Test in isolation:**
- addr=0x0000_0000 → sel_sram=1, others=0
- addr=0x0001_0100 → sel_uart=1, others=0
- addr=0x9999_9999 → sel_decerr=1, others=0

---

### 4. Additional System Components (Built from Primitives)

The following components are referenced in the full system but are simpler and built directly into the integration phase:

#### **COMPONENT 12: Shared Data SRAM (4 KB)**
- Logism **RAM(1024×32)** component
- Synchronous read (1-cycle latency)
- Byte-writable via wstrb
- AXI4-Lite slave interface wrapper

#### **COMPONENT 13: MMIO Registers**
- Counters: INV_COUNT, HIT_COUNT, MISS_COUNT (all 32-bit)
- Status: COH_STATUS (16-bit = 8 × 2-bit mirror)
- Control: coh_enable, cnt_clear, err_clear flags
- Doorbell: cross-core signaling register
- Implemented as register file + comparator for address decode

#### **COMPONENT 14: UART Core**
- TX FSM (transmit state machine)
- RX FSM (receive state machine)
- Baud generator (divide clock by 434 for 115200 baud @ 50 MHz)
- 8-bit shift registers for TX/RX

#### **COMPONENT 15: GPIO/LED**
- 8-bit LED_REG (bits 7:6 user-writable, bits 5:0 event-driven)
- Event stretchers (extend short pulses to visible duration)
- LED assignments: LED0/1=heartbeat, LED2=inv_fire, LED3/4=hit/miss, LED5=err_sticky, LED6/7=GPIO

#### **COMPONENT 16: Reset Synchronizer**
- 2-stage **Register(1-bit)** flip-flop chain
- All FFs cleared by raw `rst_n` (async assert)
- Output `rst_sync_n` released 2 clock edges after raw release

---

## PART III: INTEGRATION GUIDE

### 5. Step-by-Step Integration in Logism

#### **Phase 1: Create Project Structure**

```
1. File → New → Create new project "riscv_soc.circ"
2. Right-click on [Main Circuit] → Add Circuit
3. Rename to "ALU" (Component 1)
4. Repeat: Add CircuitRegFile32, PCLogic, ControlUnit, etc.
5. Create one circuit per component (11 total top-level circuits)
6. Create separate circuits for sub-components (e.g., Adder32, Splitters, MUXes)
```

#### **Phase 2: Build Primitives (Bottom-Up)**

| Order | Component | Depends On |
|-------|-----------|----------|
| 1 | Adder32, NOT gates, AND gates, OR gates, MUX | None |
| 2 | Subtractor32 | Adder32, NOT |
| 3 | BarrelShifter32 | MUX (cascaded) |
| 4 | Comparator32 | Subtractor32, NOT |
| 5 | ZeroDetect32 | OR(32-input) |
| 6 | ALU | 1-5 |

#### **Phase 3: Build Core Components**

| Order | Component | Depends On |
|-------|-----------|----------|
| 7 | RegFile32 | MUX(32:1), Decoder(5→32), Register |
| 8 | PCLogic | Adder32 (×4) |
| 9 | ImmGen | Splitters, BitExtender |
| 10 | LoadResize | Splitters, MUX |
| 11 | StoreRotate | Splitters, MUX |
| 12 | ControlUnit | Comparators, ROM/truth table |
| 13 | CoreFSM | Register(1-bit) |
| 14 | ControlUnit (integrated with CoreFSM) | 12, 13 |
| 15 | RV32I_Core (top) | 6, 7, 8, 14 |

#### **Phase 4: Build Cache & Coherence**

| Order | Component | Depends On |
|-------|-----------|----------|
| 16 | DCacheStore | Register(64-bit) × 4 |
| 17 | TagCompare | Comparator(28-bit) |
| 18 | HitLogic | TagCompare × 4, MUX(32-bit) |
| 19 | D-Cache (integrated 16-18) | 16, 17, 18 |
| 20 | DCacheMgrFSM | Register(4-bit), Mux trees |
| 21 | D-Cache Manager (integrated 19-20) | 19, 20 |
| 22 | CohMirror | Register(2-bit) × 8 |
| 23 | DispatchLogic | Comparators, Mux |
| 24 | CoherenceCtrl FSM | Register(2-bit), Mux trees, 23 |
| 25 | Coherence Controller (integrated 22, 24) | 22, 24 |

#### **Phase 5: Build Bus & Memory**

| Order | Component | Depends On |
|-------|-----------|----------|
| 26 | AXIArbiter FSM | Register(1-bit), Mux trees |
| 27 | Arbiter (integrated) | 26, MUX(all AXI channels) |
| 28 | AddrDecoder | Comparator × 5 |
| 29 | DECERRSlave | Simple FSM register |
| 30 | Decoder (integrated 28-29) | 28, 29 |
| 31 | SRAM_RegArray | RAM(1024×32) + control |
| 32 | MMIO_Regs | Register(32-bit) × 6, Counters |
| 33 | UART_Core | Counter, Register, TX/RX FSM |
| 34 | GPIO_LED | Register(8-bit), Stretcher logic |
| 35 | Reset_Sync | Register(1-bit) × 2 |

#### **Phase 6: Final Integration**

```
36. Create "riscv_soc_top" circuit (main)
37. Instantiate all 11 major components:
    - i_sram_0, rv32i_core_0, d_cache_0, d_cache_mgr_0
    - i_sram_1, rv32i_core_1, d_cache_1, d_cache_mgr_1
    - coherence_ctrl
    - axi_arbiter
    - axi_decoder
    - shared_sram
    - mmio_regs
    - uart_core
    - gpio_led
    - reset_sync
38. Wire all bundles (see doc 12 §12.2, 97 inter-module signals total)
39. Add tunnels for clk, rst_n (distributed)
40. Connect input/output pins for:
    - clk, rst_n (external)
    - uart_tx, uart_rx (external)
    - led[7:0] (external)
41. Save riscv_soc.circ
```

---

### 6. Wiring Reference: Signal Bundles

#### **Bundle 1: Core 0 → I-SRAM 0**
```
Core0.imem_addr[31:0] ────────► I-SRAM0.raddr[9:2]
I-SRAM0.rdata[31:0] ◄────────── Core0.imem_rdata[31:0]
```

#### **Bundle 2: Core 0 ↔ D-Cache Manager 0**
```
Core0.dmem_req ────────► CacheMgr0.dmem_req
Core0.dmem_we ────────► CacheMgr0.dmem_we
Core0.dmem_addr[31:0] ────────► CacheMgr0.dmem_addr[31:0]
Core0.dmem_wdata[31:0] ────────► CacheMgr0.dmem_wdata[31:0]
Core0.dmem_wmask[3:0] ────────► CacheMgr0.dmem_wmask[3:0]

CacheMgr0.dmem_rdata[31:0] ◄────────── Core0.dmem_rdata[31:0]
CacheMgr0.dmem_ack ◄────────── Core0.dmem_ack
CacheMgr0.dmem_err ◄────────── Core0.dmem_err
```

#### **Bundle 3: D-Cache Manager 0 ↔ Arbiter**
```
CacheMgr0.m0_awvalid ────────► Arb.m0_awvalid  (all 17 AXI signals)
CacheMgr0.m0_arvalid ────────► Arb.m0_arvalid
CacheMgr0.bus_req ────────► Arb.m0_bus_req

Arb.m0_awready ◄────────── CacheMgr0.m0_awready
Arb.m0_rvalid ◄────────── CacheMgr0.m0_rvalid
```

#### **Bundle 4: Arbiter ↔ Decoder (Shared AXI Slave)**
```
Arb.s_awvalid ────────► Dec.s_awvalid  (5 channels: AW, W, B, AR, R)
Arb.s_arvalid ────────► Dec.s_arvalid

Dec.s_awready ◄────────── Arb.s_awready
Dec.s_rvalid ◄────────── Arb.s_rvalid
```

#### **Bundle 5: Decoder → SRAM (sel_sram active)**
```
Dec.s_awaddr[11:0] ────────► SRAM.awaddr[11:2]  (byte addr → word addr)
Dec.s_wdata[31:0] ────────► SRAM.wdata[31:0]
Dec.s_wstrb[3:0] ────────► SRAM.wmask[3:0]

SRAM.rdata[31:0] ◄────────── Dec.s_rdata[31:0]
SRAM.awready ◄────────── Dec.s_awready (AXI slave response)
SRAM.bvalid ◄────────── Dec.s_bvalid
```

#### **Bundle 6: D-Cache Manager 0 ↔ Coherence Controller**
```
CacheMgr0.write_notify ────────► Coh.write_notify0
CacheMgr0.write_addr[31:0] ────────► Coh.write_addr0[31:0]
CacheMgr0.fill_notify ────────► Coh.fill_notify0
CacheMgr0.fill_idx[1:0] ────────► Coh.fill_idx0[1:0]
CacheMgr0.inv_ack ────────► Coh.inv_ack0

Coh.coh_accept0 ◄────────── CacheMgr0.coh_accept0
Coh.inv_valid0 ◄────────── CacheMgr0.inv_valid0
Coh.inv_idx0[1:0] ◄────────── CacheMgr0.inv_idx0[1:0]
```

#### **Bundle 7: Coherence ↔ D-Cache Line Registers (for dispatch truth)**
```
DCache0.line[0:3].valid ────────► Coh.valid0_i[3:0]
DCache0.line[0:3].state ────────► Coh.state0_i[1:0][3:0]  (2-bit × 4 lines)
```

#### **Bundle 8: Coherence → MMIO (Status/Events)**
```
Coh.coh_status[15:0] ────────► MMIO.coh_status[15:0]
Coh.inv_fire ────────► MMIO.inv_fire  (pulse for INV_COUNT++)
```

#### **Bundle 9: D-Cache Managers → MMIO (Counters)**
```
CacheMgr0.hit_event ────────► MMIO.hit_event0
CacheMgr0.miss_event ────────► MMIO.miss_event0
CacheMgr0.err_event ────────► MMIO.err_event0
```

#### **Bundle 10: MMIO → Coherence & Counters (Control)**
```
MMIO.coh_enable ────────► Coh.coh_enable
MMIO.cnt_clear ────────► Counters.clear
MMIO.err_clear ────────► ERR_STICKY.clear
```

#### **Bundle 11: Global Clock & Reset**
```
clk (input) ─────► Tunnel "CLK" ─────► All modules
rst_n (input) ─────► Reset_Sync.rst_n_raw
Reset_Sync.rst_sync_n ─────► Tunnel "RST_N" ─────► All modules
```

#### **Bundle 12: Event/LED Plumbing**
```
CacheMgr0.dmem_ack (stretch) ────────► LED0
CacheMgr1.dmem_ack (stretch) ────────► LED1
Coh.inv_fire (stretch) ────────► LED2
HIT events (stretch) ────────► LED3
MISS events (stretch) ────────► LED4
ERR_STICKY ────────► LED5
GPIO_LED.led[7:6] ────────► LED6, LED7
```

---

### 7. Verification & Testing Strategy in Logism

#### **Test 1: Reset (AC-9)**
```
Objective: Verify all registers initialize correctly
Steps:
1. Set rst_n = 0 for 1 tick
2. Observe all FSMs → IDLE, cache lines → I, counters → 0, PC → 0
3. Release rst_n
4. Run 2 ticks (synchronizer)
5. Observe rst_sync_n = 1 after 2 cycles
Pass: All state machines idle, no spurious AXI activity
```

#### **Test 2: Single-Core LW/SW (AC-3)**
```
Objective: Load and store without coherence
Steps:
1. Pre-load I-SRAM with: SW x5, 0(x6) (x6=0x0, x5=0x1234)
2. Then: LW x7, 0(x6)
3. Trace cache mgr states cycle-by-cycle
4. Observe SRAM[0] written with 0x1234
5. Observe x7 = 0x1234 after load completes
Pass: MISS_COUNT +1, HIT_COUNT +1, x7 == x5
```

#### **Test 3: Cross-Core Coherence (AC-4/AC-5)**
```
Objective: Write from core 0, invalidate core 1's cached copy
Steps:
1. Pre-load: Core 1 with LW instruction (line 0 → S in core 1 cache)
2. Core 0 executes SW to same line
3. Trace: coherence controller dispatches inv_valid1
4. Observe: core 1 cache line → I
5. Core 1 LW refetches: must read new data from SRAM
Pass: INV_COUNT +1, core 1 data reflects core 0 write
```

#### **Test 4: No Spurious Invalidation (AC-8)**
```
Objective: Verify Test 8 (no cached copy → no invalidation)
Steps:
1. Both cores in IDLE
2. Core 0 writes to address (no copy in core 1)
3. Trace: coherence mirrors both I
4. Observe: inv_valid1 = 0 (no dispatch)
Pass: INV_COUNT unchanged
```

#### **Test 5: Address Decoder**
```
Objective: Route addresses to correct slaves
Steps:
1. Core 0 LW 0x0000_0000 → SRAM
2. Core 0 LW 0x0001_0000 → MMIO (COH_STATUS)
3. Core 0 LW 0x0001_0100 → UART (RX_DATA)
4. Core 0 LW 0x9999_9999 → DECERR (unmapped)
Pass: Correct slave selected each time, DECERR returns error response
```

#### **Test 6: Arbiter Round-Robin**
```
Objective: Verify both cores can access bus sequentially
Steps:
1. Core 0 requests bus (arvalid=1)
2. Core 1 also requests (arvalid=1)
3. Observe: Arbiter grants core 0 first (pref=0)
4. After core 0 transaction: pref flips
5. Next request: core 1 gets priority
Pass: No arbitration deadlock, deterministic round-robin
```

---

## PART IV: COMPONENT BUILD CHECKLIST

### 8. Quick Reference: Build Sequence

Use this checklist to track completion of each component. For each, verify:
- [ ] Inputs/outputs correctly wired
- [ ] Internal logic matches doc reference
- [ ] All reset values set (async clear on registers)
- [ ] No undriven signals (red lines in Logism)
- [ ] Smoke test passes (isolated functional test)

```
PHASE 1: Primitives
☐ Adder32 (doc 02 §2.5)
☐ Subtractor32
☐ BarrelShifter32 (doc 02 §2.6)
☐ Comparator32 (doc 02 §2.7)
☐ ZeroDetect32

PHASE 2: Core Arithmetic
☐ ALU (doc 02 §2.3, gate_level/01)
☐ RegFile32 (doc 03 §3.2, gate_level/02)
☐ PCLogic (doc 03 §3.3)
☐ ImmGen (doc 03 §3.4)
☐ LoadResize (doc 03 §6.1)
☐ StoreRotate (doc 03 §6.2)

PHASE 3: Control & Core
☐ ControlUnit (doc 03 §3.5, gate_level/03)
☐ CoreFSM (RUN/STALL_MEM)
☐ RV32I_Core (integrated)
☐ I-SRAM (doc 08 §8.2)

PHASE 4: Cache & Coherence
☐ DCacheStore (4 lines, doc 04 §4.2)
☐ TagCompare (doc 04 §4.3)
☐ HitLogic (doc 04 §4.3)
☐ D-Cache (integrated)
☐ DCacheMgrFSM (13-state, doc 04 §4.4, gate_level/05)
☐ D-Cache Manager (integrated)
☐ CohMirror (8-entry, 2-bit, doc 05 §5.2)
☐ CoherenceCtrl FSM (4-state, doc 05 §5.4)
☐ Coherence Controller (integrated)

PHASE 5: Bus & Slaves
☐ AXIArbiter FSM (2-state, doc 06 §6.4)
☐ Arbiter (integrated, gate_level/07)
☐ AddrDecoder (doc 07 §7.1)
☐ DECERRSlave (doc 07 §7.6)
☐ Decoder (integrated, gate_level/08)
☐ Shared SRAM (doc 08 §8.3)
☐ MMIO Regs (doc 09 §9.1)
☐ UART Core (doc 09 §9.2)
☐ GPIO/LED (doc 09 §9.4)

PHASE 6: Integration
☐ Reset Sync (2-FF, doc 12 §12.3)
☐ riscv_soc_top (all instances + wiring, doc 12 §12.2)
☐ Test harness (verification vectors)

PHASE 7: Verification
☐ Test 1: Reset
☐ Test 2: Single-core LW/SW
☐ Test 3: Cross-core coherence
☐ Test 4: No spurious invalidation
☐ Test 5: Address decoder
☐ Test 6: Arbiter RR
☐ Test 7: Simultaneous writes
☐ Test 8: Error handling
☐ Test 9: MMIO read/write
☐ Test 10: Full scenario trace
```

---

## PART V: KEY DESIGN REFERENCE

### 9. Critical Path & Timing (for documentation)

| Path | Stages | Cycle count | Notes |
|------|--------|-------------|-------|
| Instruction fetch | IF (async I-SRAM) | 0 (combinational) | Same-cycle imem_rdata |
| Cache load hit | CHECK + HIT_READ | 1–2 cycles (depends if CHECK is sequential or combinational) | Typically 3 cycles total from req |
| Cache load miss | CHECK→MISS_READ→AXI_AR→AXI_R→FILL→IDLE | ~5–9 cycles | Plus arbiter contention |
| Cache store hit | CHECK→HIT_WRITE→AXI_AW→AXI_W→AXI_B→NOTIFY_COH→IDLE | ~6–8 cycles | Write-through commit point = AXI_B |
| Coherence invalidation dispatch | NOTIFY_COH→PROCESS_WRITE→INVALIDATE_OTHER→WAIT_INV_ACK→IDLE | ~4 cycles | inv_fire pulses in INVALIDATE_OTHER |

### 10. Logism Global Settings

```
Simulate → Preferences:
- Tick frequency: 1 Hz (manual stepping) or slow (~1 cycle/sec for visibility)
- Gate delay: 1 (normalized for gate-level)
- Base radix: Hexadecimal (for addresses/data)
- Library: Standard (built-in gates)
- Layout → Appearance: Black on white (high contrast)

Toolbar shortcuts:
- Poke tool: click to toggle 1-bit inputs
- Hand tool: pan/scroll canvas
- Probe tool: right-click on wire to view value
- Tunnel: Wiring → Tunnel (use "CLK", "RST_N" labels)
```

### 11. Debugging Tips in Logism

| Issue | Diagnosis | Fix |
|-------|-----------|-----|
| Undriven signal (red wire) | Right-click → View → Find | Check for missing connection in MUX select or output mux |
| FSM stuck in one state | Check state register's clock and reset inputs | Verify CLK/RST_N tunnels connected; check reset value |
| Data appears wrong | Use Probe tool to inspect intermediate nodes | Trace back from output; check MUX selects and data paths |
| Slave never responds (transaction hangs) | Check DECERR slave for unhandled state | Verify sel_* signals, slave instance, AXI channel handshake |
| Timing critical path exceeded | Analyze longest combinational chain | May need pipeline stages (cache mgr already has them) |

---

## PART VI: INTEGRATION COMPLETE — NEXT STEPS

### 12. After Logism Verification: Path to RTL

Once you have Logism working end-to-end:

1. **Compare gate-level traces** with RTL simulation
   - Use Logism probe tool to log cycle-by-cycle behavior
   - Cross-check against doc 13 scenarios (13.1–13.9)

2. **Transcribe Logism circuits to SystemVerilog RTL** (if doing ASIC flow)
   - Use FSM transition tables in docs 03–07 as directly as possible
   - Each Logism subcircuit → One `.sv` module
   - Register declarations → Logism Register(N-bit) components

3. **Validate RTL against Logism** (cosimulation or equivalence check)
   - Run directed TB (10 tests from doc 13 §13.10)
   - Verify same cycle-by-cycle behavior

4. **Physical design** (Day 4–5 on the 5-day schedule)
   - Synthesis with Yosys (open-source)
   - Place & route with OpenLane (sky130A PDK)
   - Timing analysis at 20 MHz (50 ns period)

5. **FPGA deployment** (Arty A7-100T or Zybo)
   - RTL synthesis for Vivado
   - Bitstream generation
   - UART console demo
   - LED visualization of coherence events

---

## APPENDIX A: Document Cross-Reference

| Component | Logic Design Doc | Gate-Level Doc | Implementation Task |
|-----------|------------------|----------------|------------------|
| ALU | 02_alu_logic.md | 01_alu_gate_level.md | T1.1 |
| RegFile, PC | 03_core_datapath_and_control.md | 02_regfile_pc_gate_level.md | T1.8–T1.9 |
| Control Unit | 03_core_datapath_and_control.md | 03_control_unit_gate_level.md | T1.9 |
| RV32I Core | 03_core_datapath_and_control.md | 03_control_unit_gate_level.md | T1.10–T1.11 |
| D-Cache | 04_dcache_fsm.md | 04_dcache_store_gate_level.md | T2.4–T2.5 |
| D-Cache Mgr FSM | 04_dcache_fsm.md | 05_dcache_mgr_fsm_gate_level.md | T2.5 |
| Coherence | 05_coherence_fsm.md | 06_coherence_fsm_gate_level.md | T2.7 |
| Arbiter | 06_arbiter_logic.md | 07_arbiter_gate_level.md | T2.9 |
| Decoder | 07_decoder_and_bus_fabric.md | 08_decoder_gate_level.md | T2.10 |
| Memory | 08_memory_subsystem.md | 09_memory_gate_level.md | T2.2–T2.3 |
| Peripherals | 09_peripherals.md | 10_peripherals_gate_level.md | T2.11–T2.13 |
| Integration | 12_integration_logic.md | 11_soc_top_gate_level.md | T3.1 |
| Scenarios | 13_working_logic_scenarios.md | — | Verification (T3.3–T3.6) |

---

## APPENDIX B: Memory Map Quick Reference

```
┌──────────────────┬──────────────────┬────────────────────────────┐
│ Address Range    │ Slave            │ Details                    │
├──────────────────┼──────────────────┼────────────────────────────┤
│ 0x0000_0000      │ Shared Data SRAM │ 4 KB, 1024×32, byte-RW    │
│ 0x0000_0FFF      │ (cont.)          │ Word-addressed [11:2]      │
│                  │                  │                            │
│ 0x0001_0000      │ MMIO Regs        │ 256 B, 6 regs:             │
│ 0x0001_00FF      │ (cont.)          │ COH_STATUS, INV/HIT/MISS   │
│                  │                  │ DOORBELL, CONTROL          │
│                  │                  │                            │
│ 0x0001_0100      │ UART             │ 256 B:                     │
│ 0x0001_01FF      │ (cont.)          │ TX_DATA, TX_STATUS         │
│                  │                  │ RX_DATA, RX_STATUS         │
│                  │                  │                            │
│ 0x0001_0200      │ GPIO/LED         │ 256 B:                     │
│ 0x0001_02FF      │ (cont.)          │ LED_REG (bits 7:6 writable)│
│                  │                  │                            │
│ All others       │ DECERR Slave     │ Returns error response     │
│ (0x0001_0300...) │                  │ (bresp/rresp = 2'b11)      │
└──────────────────┴──────────────────┴────────────────────────────┘

Cache Line Indexing (for coherence):
  Line 0: addr[3:2] = 0 (SRAM [0:3])
  Line 1: addr[3:2] = 1 (SRAM [4:7])
  Line 2: addr[3:2] = 2 (SRAM [8:11])
  Line 3: addr[3:2] = 3 (SRAM [12:15])
```

---

**END OF LOGISM COMPONENT BUILD GUIDE**

**Status:** Ready for Phase 1 (Primitives) construction in Logism Classic  
**Next action:** Open Logism Classic, create `riscv_soc.circ`, and begin with **Component 1: ALU**

