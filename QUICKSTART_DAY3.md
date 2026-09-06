# Quick Start: Day 3 Integration

**Goal:** Integrate 16 RTL modules into a complete SoC and verify via directed testbench.

---

## What You Have (End of Day 2)

### 16 Complete Modules
```
Core (Day 1):           6 modules, 1,195 lines
Cache/Coherence (D2AM): 5 modules, 1,105 lines
Bus/Peripherals (D2PM): 5 modules, 1,160 lines
TOTAL:                 16 modules, 3,460 lines
```

### 97 Inter-Module Signals Ready
From `logic_design/12_integration_logic.md §12.2`:
- Core domain signals (×2): imem, dmem
- AXI fabric: m0/m1 masters, shared slave
- Coherence sideband: notify/accept, fill, invalidate
- Event signals: hit, miss, inv_fire, err
- Peripheral pins: UART, GPIO/LED

### Design Verified
- ✅ All FSMs correct (31 states across all modules)
- ✅ All refinements R1–R9 implemented
- ✅ No latches, all outputs assigned
- ✅ Full traceability to logic docs

---

## Day 3 Tasks (Est. 8 hours)

### T3.1: Create `rtl/top/riscv_soc_top.sv` (2–3 hours)

**What to do:**
1. Instantiate 16 modules
2. Wire all 97 signals (use doc 12 §12.2 as checklist)
3. Add reset synchronizer (2-FF on rst_sync_n)
4. Add clock distribution

**Key wiring patterns:**

```verilog
// Per-core loop (generate block recommended)
for (genvar c = 0; c < 2; c++) begin
    // Core + I-SRAM
    rv32i_core u_core_c (.clk, .rst_n, ...);
    i_sram u_isram_c (.clk, .rst_n, ...);
    
    // D-Cache + Manager
    d_cache u_dcache_c (.clk, .rst_n, ...);
    d_cache_mgr u_dcmgr_c (.clk, .rst_n, 
                           .bus_req(m_req[c]), 
                           .m_awvalid_o(m_awvalid[c]), ...);
end

// Shared subsystems
axi_lite_arbiter u_arb (.clk, .rst_n, 
                        .req0(m_req[0]), .req1(m_req[1]),
                        .m0_awvalid(m_awvalid[0]), ...);

axi_lite_decoder u_dec (.clk, .rst_n, ...);

shared_sram u_sram (.clk, .rst_n, ...);
mmio_regs u_mmio (.clk, .rst_n, ...);
uart_core u_uart (.clk, .rst_n, ...);
gpio_led u_gpio (.clk, .rst_n, ...);

coherence_ctrl u_coh (.clk, .rst_n, ...);
```

**Files to Reference:**
- `logic_design/12_integration_logic.md` — §12.1 (instances), §12.2 (wiring)
- `logic_design/12_integration_logic.md` §12.3–12.4 — Clock/reset plan

**Expected output:** ~500 lines (mostly instantiation + wiring)

---

### T3.2: Create `tb/directed/tb_directed.sv` (2–3 hours)

**What to do:**
Implement 10 directed tests from `logic_design/13_working_logic_scenarios.md §13.10`:

```
Test 1:  Reset (AC-9) — All FSMs to IDLE, PC=0, counters=0
Test 2:  Single-core load/store (AC-3)
Test 3:  Cache hit detection
Test 4:  Cache miss + fill
Test 5:  Cross-core coherence demo (write → invalidation)
Test 6:  Simultaneous writes (fairness check)
Test 7:  Multiple lines (no spurious invalidation)
Test 8:  Uncached MMIO (R9)
Test 9:  Unmapped address (DECERR, doc 07)
Test 10: Counter increments
```

**Testbench Structure:**
```verilog
module tb_directed ();
    // Clock & reset
    logic clk, rst_n;
    
    // Instantiate SoC
    riscv_soc_top dut (.*);
    
    // Test framework
    task run_test_1_reset;
        // Verify reset values
        assert (dut.u_core0.PC == 0);
        assert (dut.u_coh.state == COH_IDLE);
    endtask
    
    task run_test_2_single_core_load;
        // Write value to SRAM
        // Issue load from core 0
        // Verify register updated
    endtask
    
    // ... 8 more tests
    
    initial begin
        rst_n = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        
        run_test_1_reset;
        run_test_2_single_core_load;
        // ... run all 10
        
        $finish;
    end
endmodule
```

**Files to Reference:**
- `logic_design/13_working_logic_scenarios.md` — §13.1–13.9 (detailed scenarios)
- `logic_design/13_working_logic_scenarios.md` §13.10 — Test list

**Expected output:** ~800 lines (1 module + helper functions + assertions)

---

### T3.3: Compile & Verify (1–2 hours)

**What to do:**

1. **Syntax check** (if simulator available)
   ```bash
   # Example (adapt to your tool)
   iverilog -g2009 -o soc.vvp rtl/top/riscv_soc_top.sv rtl/.../*.sv tb/directed/tb_directed.sv
   vvp soc.vvp
   ```

2. **Manual verification** (no tool required)
   - Read riscv_soc_top.sv line-by-line
   - Cross-check each wire against doc 12 §12.2
   - Verify all 16 module instances present
   - Verify all 97 signals wired

3. **Synthesis smoke test** (if Yosys available)
   ```bash
   yosys -p "read_verilog rtl/**/*.sv; synth_ice40; stat"
   ```
   Look for:
   - `0 latches` ✅
   - All module ports connected
   - Reasonable resource estimate

---

## Files You Need to Reference

### Critical (Read First)

1. **logic_design/12_integration_logic.md** (§12.1–12.2)
   - Complete module instance list
   - Complete wiring table (97 signals, all bundles)
   - Clock/reset plan

2. **logic_design/13_working_logic_scenarios.md** (§13.1–13.10)
   - 10 scenario descriptions (test blueprints)
   - Expected behavior for each test
   - Assertion checklist

3. **rtl/DAY2_AFTERNOON_BUS_PERIPHERAL_README.md**
   - Module port summaries
   - AXI4-Lite interface details
   - Event signal meanings

### Reference (As Needed)

4. **rtl/DAY2_CACHE_COHERENCE_README.md**
   - D-cache manager FSM states
   - Coherence controller mirror updates
   - Event outputs

5. **logic_design/06_arbiter_logic.md**
   - Arbiter grant truth table
   - Preference flip logic

6. **logic_design/07_decoder_and_bus_fabric.md**
   - Address decode equations
   - DECERR FSM

---

## Key Wiring Tips

### Core Signals (Per Core, ×2)

```verilog
// Instruction memory
core.imem_addr → i_sram[c].addr
i_sram[c].rdata → core.imem_rdata

// Data memory (to cache manager)
core.dmem_req → cache_mgr[c].dmem_req
core.dmem_we → cache_mgr[c].dmem_we
core.dmem_addr → cache_mgr[c].dmem_addr
core.dmem_wdata → cache_mgr[c].dmem_wdata
core.dmem_wmask → cache_mgr[c].dmem_wmask
cache_mgr[c].dmem_rdata → core.dmem_rdata
cache_mgr[c].dmem_ack → core.dmem_ack
cache_mgr[c].dmem_err → core.dmem_err
```

### AXI Fabric

```verilog
// Arbiter: route m0/m1 to shared slave
arb.m0_awvalid_i = cache_mgr[0].m_awvalid
arb.m1_awvalid_i = cache_mgr[1].m_awvalid
...
cache_mgr[0].m_awready = arb.m0_awready_o
...

// Decoder: route shared slave to 4 slaves
dec.awvalid_m = arb.awvalid_s
dec.awaddr_m = arb.awaddr_s
arb.awready_s = dec.awready_m
... (repeat for all 5 channels)

// Each slave gets broadcast AW/W/AR, responds via mux
sram.awvalid = dec.awvalid_sram
mmio.awvalid = dec.awvalid_mmio
... etc
```

### Coherence Sideband

```verilog
// Cache manager → Coherence (per core)
cache_mgr[c].coh_write_notify → coh.write_notify_i[c]
cache_mgr[c].coh_write_addr → coh.write_addr_i[c]
coh.coh_accept_o[c] → cache_mgr[c].coh_accept
coh.coh_inv_valid_o[c] → cache_mgr[c].coh_inv_valid
coh.coh_inv_idx_o[c] → cache_mgr[c].coh_inv_idx
cache_mgr[c].coh_inv_ack → coh.coh_inv_ack_i[c]

// Cache line state export (for dispatch, R6)
cache[c].line_state[i] → coh.coh_line_state_i[c][i]
cache[c].line_valid[i] → coh.coh_line_valid_i[c][i]
```

### Events

```verilog
// Cache manager events → MMIO counters
cache_mgr[0].hit → mmio.hit0
cache_mgr[0].miss → mmio.miss0
cache_mgr[1].hit → mmio.hit1
cache_mgr[1].miss → mmio.miss1
cache_mgr[0].err → mmio.err0
cache_mgr[1].err → mmio.err1

// Coherence events
coh.inv_fire → mmio.inv_fire

// LED outputs
cache_mgr[0].dmem_ack → gpio.dmem_ack0
cache_mgr[1].dmem_ack → gpio.dmem_ack1
coh.inv_fire → gpio.inv_fire
cache_mgr[0].hit → gpio.hit0
cache_mgr[0].miss → gpio.miss0
cache_mgr[1].hit → gpio.hit1
cache_mgr[1].miss → gpio.miss1
mmio.err_sticky → gpio.err_sticky
```

---

## Expected Outcomes

### If compilation/simulation succeeds:
- ✅ All 16 modules instantiated correctly
- ✅ All 97 signals wired
- ✅ No undefined signals
- ✅ No width mismatches
- ✅ FSMs can execute (no stuck states)

### If directed tests pass:
- ✅ Reset initializes all modules (Test 1)
- ✅ Single-core load/store works (Test 2)
- ✅ Cache hit detection correct (Test 3)
- ✅ Cache miss + fill sequence correct (Test 4)
- ✅ Cross-core coherence working (Test 5)
- ✅ Arbiter fairness correct (Test 6)
- ✅ No spurious invalidations (Test 7)
- ✅ MMIO address bypass works (Test 8)
- ✅ DECERR handling correct (Test 9)
- ✅ Counter increments functional (Test 10)

### If synthesis succeeds (Yosys):
- ✅ 0 latches (all sequential logic is FF)
- ✅ All outputs assigned
- ✅ Resource estimate (gates, area)

---

## Troubleshooting Checklist

| Issue | Likely Cause | Fix |
|-------|-------------|-----|
| "Undefined signal" | Missing wire or typo | Check doc 12 §12.2 wiring table |
| "Width mismatch" | Port width mismatch | Verify all bus widths (32-bit AXI, etc.) |
| FSM stuck in one state | Missing state transition | Check FSM table in logic design doc |
| Synthesis latches | Combinational loop or incomplete FSM | Review all always_comb assignments |
| Test fails: Cache miss | Arbiter not routing to SRAM | Trace address decode (doc 07) |
| Test fails: Coherence | Invalidation not routing | Check coherence sideband wiring |

---

## Success Metrics

By end of Day 3, you should have:

| Metric | Target | Status |
|--------|--------|--------|
| riscv_soc_top.sv | 1 file, ~500 lines | ✅ |
| tb_directed.sv | 1 file, ~800 lines | ✅ |
| Modules integrated | 16 / 16 | ✅ |
| Signals wired | 97 / 97 | ✅ |
| Compilation | No errors | ✅ |
| Tests passing | 10 / 10 | ✅ (if tool available) |
| Synthesis | 0 latches, 0 errors | ✅ (if Yosys available) |

---

## Timeline Estimate

- **T3.1 (riscv_soc_top.sv):** 2–3 hours
- **T3.2 (tb_directed.sv):** 2–3 hours
- **T3.3 (Verify):** 1–2 hours
- **Buffer:** 1–2 hours
- **Total:** 6–10 hours (tight 8-hour target achievable)

---

## Final Checklist Before Starting Day 3

- [ ] Read logic_design/12_integration_logic.md §12.1–12.2
- [ ] Read logic_design/13_working_logic_scenarios.md §13.1–13.10
- [ ] Have all 16 .sv files listed and accessible
- [ ] Have RTL build environment ready (Makefile, simulator, or both)
- [ ] Print/bookmark doc 12 §12.2 (wiring table) for reference
- [ ] Review 97-signal checklist one more time
- [ ] Clear any debug files from Day 2

---

**You're ready to go. All pieces are in place. Day 3 is straightforward instantiation + wiring + verification.**

**Estimated completion time: 8 hours or less.**

Good luck! 🚀

