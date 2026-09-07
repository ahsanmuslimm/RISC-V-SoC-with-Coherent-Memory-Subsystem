# Implementation Plan

> **Dependency Order:** BUG-001 first (establishes _d/_q discipline that BUG-004/005/006
> build on) → BUG-004/005/006 → BUG-002/003 → BUG-007.
>
> **Files Under Fix:**
> - `rtl/coherence/coherence_ctrl.sv` — BUG-001, BUG-004, BUG-005, BUG-006
> - `rtl/cache/d_cache.sv` — BUG-002
> - `rtl/cache/d_cache_mgr.sv` — BUG-003
> - `rtl/bus/axi_lite_decoder.sv` — BUG-007

---

## Phase 1: Exploratory Testing (BEFORE any fix)

- [ ] 1. Write bug condition exploration tests
  - **Property 1: Bug Condition** - _d/_q Discipline Violations and Address Index Extraction (BUG-001/BUG-004)
  - **CRITICAL**: Write ALL exploration tests BEFORE implementing any fix
  - **GOAL**: Surface counterexamples that demonstrate each bug exists on unfixed code
  - **EXPECTED OUTCOME**: Tests FAIL — failure is the correct outcome and confirms each bug
  - **DO NOT fix the code or tests when they fail; document counterexamples instead**
  - **Scoped PBT Approach**: Scope PBT-1 to concrete failing cases where `write_addr0[3:2]` is non-zero

  **BUG-001 — Line-index boolean-coercion exploration (PBT-1):**
  - Scope: `write_notify0=1`, `write_addr0[3:2] != 2'b0` (triggers boolean coercion)
  - For all 4 non-zero 2-bit values (`2'b01`, `2'b10`, `2'b11`) of `write_addr0[3:2]`,
    drive a write notify from core 0, clock one edge, then read `proc_idx_q`
  - Assert `proc_idx_q == write_addr0[3:2]` (will fail on unfixed code — gets `2'b00` due
    to `write_addr0[3:2] ? 2'b0 : write_addr1[3:2]` boolean coercion)
  - Concrete case: `write_addr0=32'h00000008` (line 2) → expect `proc_idx_q=2'b10`,
    but unfixed code yields `proc_idx_q=2'b00`
  - Document the counterexample: `"write_addr0=0x08 (line 2): expected proc_idx_q=2b10, got 2b00"`

  **BUG-001/004 — Multiple-driver lint check:**
  - Run `verilator --lint-only -Wall rtl/coherence/coherence_ctrl.sv`
  - Confirm linter reports multiple-driver errors on `proc_core` and `proc_idx`
  - Document: `"proc_core driven from both always_comb (COH_IDLE branch) and always_ff"`
  - Document: `"proc_idx driven from both always_comb and always_ff"`

  **BUG-004 — inv_target read-before-write hazard check:**
  - Drive `write_notify0=1, write_notify1=1` simultaneously in `COH_IDLE`
  - Run lint / code inspection to confirm `inv_target = ~proc_core` is read in the same
    `always_comb` block where `proc_core` is written — non-deterministic evaluation order
  - Document: `"inv_target = ~proc_core evaluated in same always_comb where proc_core is written"`

  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_

- [ ] 2. Write preservation property tests (BEFORE implementing any fix)
  - **Property 2: Preservation** - Single-Core Write-Notify Coherence Sequence and Non-Buggy Paths
  - **IMPORTANT**: Follow observation-first methodology
  - **EXPECTED OUTCOME**: Tests PASS on unfixed code — confirms the baseline behavior to preserve
  - Scope: inputs where `isBugCondition_001(X)` does NOT hold — i.e., FSM is NOT in `COH_IDLE`
    with a write notify, AND `write_addr0[3:2]` scenarios where only one core is active

  **Coherence FSM single-notify sequence preservation:**
  - Observe on unfixed code: drive only `write_notify0=1` with `write_addr0=32'h00000000`
    (line 0, addr bits [3:2]=`2'b00` — the one case where boolean coercion is accidentally
    correct), clock through the FSM sequence, record `coh_accept0`, `coh_state` transitions,
    `inv_valid1` assertion, `inv_idx1`, mirror updates
  - Write property: for single write notify with `write_addr[3:2]=2'b00`, the FSM produces
    `COH_IDLE → PROCESS_WRITE → INVALIDATE_OTHER → WAIT_INV_ACK → COH_IDLE` when remote
    has a copy, with matching `inv_valid`, `inv_idx`, and `coh_accept` values
  - Property-based: sweep `coh_state != COH_IDLE` with any notify; assert FSM does NOT
    accept a new notify (output `coh_accept=0`)
  - Verify tests PASS on unfixed code before proceeding

  **Fill-notify mirror update preservation:**
  - Observe on unfixed code: assert `fill_notify0=1, fill_idx0=2'b01`; verify `mirror[0][1]`
    transitions to S regardless of current FSM state
  - Write property: for any `fill_notify` input, mirror[core][idx] → S independently of
    `coh_state`
  - Verify test PASSES on unfixed code

  **coh_enable=0 bypass preservation:**
  - Observe on unfixed code: with `coh_enable=0`, drive `write_notify0=1`; FSM enters
    `PROCESS_WRITE` then returns directly to `COH_IDLE` without asserting `inv_valid`
  - Write property: when `coh_enable=0`, no `inv_valid` is ever asserted during the write
    sequence
  - Verify test PASSES on unfixed code

  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

---

## Phase 2: Additional Exploration Tests for BUG-002, BUG-003, BUG-005, BUG-006, BUG-007

- [ ] 3. Write bug condition exploration tests for d_cache, d_cache_mgr, and axi_lite_decoder
  - **Property 1: Bug Condition** - Dead Port Widths, Illegal Assignments, FSM/Arbitration, AXI Channel Mixing
  - **CRITICAL**: Write ALL these exploration tests BEFORE implementing fixes for BUG-002 through BUG-007
  - **EXPECTED OUTCOME**: Tests FAIL or linter/compiler reports errors — confirms each bug exists

  **BUG-002 — Dead port width lint checks:**
  - Run `verilator --lint-only -Wall rtl/cache/d_cache.sv`
  - Expect width-mismatch warning: "`line_valid[i]` declared `[1:0]` but driven by 1-bit
    `line_valid_reg[i]` — upper bit is permanently zero"
  - Drive a valid line (`line_valid_reg[0]=1`); read `line_valid[0]`; assert bit 1 is always `0`
    (will pass — confirming the dead bit exists)
  - Drive `line_state_reg[0]=2'b10` (M), `req_idx=2'b11`; read `line_state[0]`; assert
    bits [3:2] = state `2'b10` AND bits [1:0] = `req_idx=2'b11` (semantic mixing confirmed)
  - Document: `"line_valid[i][1] is always 0 — dead bit confirmed"`
  - Document: `"line_state[0] packs {state=2b10, req_idx=2b11} = 4b1011 — semantic mixing"`
  - Document: `"line_out[i][63] is always 0 — declared 64 bits but only 63 bits of content"`
  - _Requirements: 1.12, 1.13, 1.14_

  **BUG-003 — Illegal NBA and multi-driver checks:**
  - Run `verilator --lint-only -Wall rtl/cache/d_cache_mgr.sv`
  - Expect: `%Error: Non-blocking assignment '<=' in combinational always block for fill_data_q`
  - Expect: `%Error: Signal 'notify_pending' has multiple drivers (always_comb + always_ff)`
  - If VCS/Questa available: compile with `-sv`; expect `%Error-MDRIVEN: notify_pending`
  - Document exact linter messages as counterexamples
  - _Requirements: 1.15, 1.16_

  **BUG-005 — inv_valid hold and dropped simultaneous notify:**
  - Scoped PBT: Drive `coh_state = INVALIDATE_OTHER` (by first processing a write notify),
    hold `inv_ack=0` for 3 cycles; observe `inv_valid` on each cycle
  - Assert `inv_valid` stays asserted all 3 cycles (will FAIL on unfixed code — FSM moves
    to `WAIT_INV_ACK` after 1 cycle, `inv_valid` deasserts momentarily)
  - Simultaneous notify test: drive `write_notify0=1` and `write_notify1=1` simultaneously
    in `COH_IDLE`; process core 0; immediately de-assert `write_notify1` after `coh_accept0`
    rises; verify `write_notify1` is NOT acknowledged (confirms silent drop risk)
  - Document: `"inv_valid deasserted for 1 cycle between INVALIDATE_OTHER and WAIT_INV_ACK"`
  - Document: `"write_notify1 dropped if core 1 de-asserts before FSM returns to COH_IDLE"`
  - _Requirements: 1.7, 1.8, 1.9_

  **BUG-006 — Starvation and back-pressure:**
  - Starvation PBT: Assert `write_notify0=1` and `write_notify1=1` simultaneously for
    10 consecutive IDLE entry cycles; count `coh_accept0` and `coh_accept1`
  - Assert counts are approximately equal (will FAIL on unfixed code — core 0 gets all 10,
    core 1 gets 0)
  - Back-pressure test: Assert `write_notify1=1` while FSM is in `PROCESS_WRITE`; observe
    `coh_accept1` stays `0`; then de-assert `write_notify1` early; confirm notification lost
  - Document: `"Starvation: coh_accept0=10, coh_accept1=0 across 10 simultaneous cycles"`
  - Document: `"Back-pressure: no pending-request register → notify dropped if de-asserted early"`
  - _Requirements: 1.10, 1.11_

  **BUG-007 — AXI channel address mixing:**
  - Scoped PBT: Assert `awvalid_m=1, awaddr_m=32'h0000_0100` (SRAM write) and
    `arvalid_m=1, araddr_m=32'h0001_0100` (UART read) simultaneously
  - Assert `sel_sram=1` AND `sel_uart=1` simultaneously (will PASS on unfixed code —
    confirming both are asserted when they should be exclusive per channel)
  - Assert that write-channel `bvalid_m` is corrupted (UART `bvalid` leaks into write path)
  - Try 4 combinations: (SRAM-wr, UART-rd), (MMIO-wr, SRAM-rd), (UART-wr, GPIO-rd),
    (GPIO-wr, MMIO-rd); confirm `sel_*` cross-contamination in each
  - Document counterexamples table:
    `"awaddr=0x100 (SRAM), araddr=0x10100 (UART) → sel_sram=1, sel_uart=1 simultaneously"`
  - _Requirements: 1.17, 1.18, 1.19_

- [ ] 4. Write preservation property tests for BUG-002, BUG-003, BUG-007 non-buggy paths
  - **Property 2: Preservation** - Cache Storage, Cache-Manager Pipeline, Single-Channel AXI
  - **IMPORTANT**: Follow observation-first methodology; observe then capture
  - **EXPECTED OUTCOME**: Tests PASS on unfixed code

  **BUG-002 preservation — Cache hit/miss path:**
  - Observe on unfixed code: fill line 0 with tag `0xABCD`, data `0xDEAD_BEEF`, state M;
    then request same tag — record `hit=1`, `hit_idx=0`, `hit_data=0xDEAD_BEEF`
  - Write property (PBT-4): for all `line_state_reg` / `line_valid_reg` / `line_tag_reg`
    combinations, `hit_data`, `hit`, `miss`, `hit_idx` are identical on unfixed and fixed
    code (port-width fix must not change the data path)
  - Observe invalidation: fill a line, assert `inv_we`; verify `line_valid_reg=0` and
    `line_state_reg=I` — write property that invalidation clears both fields
  - Verify tests PASS on unfixed code
  - _Requirements: 3.11, 3.12_

  **BUG-003 preservation — Load-miss fill and write-through pipeline:**
  - Observe on unfixed code: run IDLE→CHECK→MISS_READ→AXI_AR→AXI_R (with `m_rdata=0xCAFE_BABE`)
    →FILL; record `cache_wr_data=0xCAFE_BABE`
  - Write property (PBT-5): for random `m_rdata` values, `fill_data_q` after `AXI_R` equals
    `m_rdata`, and `cache_wr_data` in `FILL` equals `fill_data_q`
  - Observe write-through: NOTIFY_COH → wait for `coh_accept=1` → `dmem_ack=1`; write
    property that `notify_pending` hold-until-accept behavior is preserved
  - Verify tests PASS on unfixed code
  - _Requirements: 3.13, 3.14_

  **BUG-007 preservation — Single-channel AXI transactions:**
  - Observe on unfixed code (write-only, `arvalid_m=0`): write to SRAM at `awaddr=0x100`;
    record `awready_m`, `wready_m`, `bvalid_m`, `bresp_m`; all route correctly to SRAM slave
  - Observe on unfixed code (read-only, `awvalid_m=0`): read from UART at `araddr=0x10100`;
    record `arready_m`, `rvalid_m`, `rdata_m`, `rresp_m`; routes correctly to UART slave
  - Write property (PBT-6): for all 4 slaves write-only, AXI signals match expected slave
    outputs; for all 4 slaves read-only, AXI signals match expected slave outputs
  - Observe DECERR: unmapped write address → `bresp_m=2'b11`; unmapped read → `rresp_m=2'b11`
  - Write property: DECERR behavior unchanged for both channels in isolation
  - Verify tests PASS on unfixed code
  - _Requirements: 3.15, 3.16, 3.17, 3.18_

---

## Phase 3: Implement Fixes (in dependency order)

- [ ] 5. Fix BUG-001 and BUG-004 — _d/_q Signal Discipline in `coherence_ctrl.sv`

  - [ ] 5.1 Introduce `proc_core_q`, `proc_idx_q`, `proc_core_d`, `proc_idx_d`, and `last_served` declarations
    - Remove bare `logic proc_core` and `logic [1:0] proc_idx` declarations
    - Add registered (_q) signals: `logic proc_core_q`, `logic [1:0] proc_idx_q`
    - Add next-value (_d) signals: `logic proc_core_d`, `logic [1:0] proc_idx_d`
    - Add round-robin register: `logic last_served` (0 = core 0 last granted, 1 = core 1)
    - Keep `inv_target` as a purely combinational wire derived from `proc_core_q`
    - _Bug_Condition: isBugCondition_001(X) — coh_state=COH_IDLE AND (write_notify0 OR write_notify1), OR write_addr0[3:2]!=2'b0 AND write_notify0_
    - _Expected_Behavior: proc_core_q and proc_idx_q updated exclusively in always_ff via _d next-values; no multiple drivers_
    - _Preservation: FSM transitions, inv_valid, coh_accept, mirror updates for single-notify sequences unchanged_
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [ ] 5.2 Fix the `proc_idx_d` address extraction (boolean coercion bug)
    - Remove from `always_comb`: `proc_idx = write_addr0[3:2] ? 2'b0 : write_addr1[3:2]`
    - Add new `always_comb` block for `proc_core_d` / `proc_idx_d` next-values with direct bit extraction:
      - `write_notify0` only: `proc_idx_d = write_addr0[3:2]` (direct extraction, no ternary)
      - `write_notify1` only: `proc_idx_d = write_addr1[3:2]`
      - Both simultaneously: use round-robin `last_served` tiebreaker (see BUG-006 change)
      - Default: hold `proc_core_d = proc_core_q`, `proc_idx_d = proc_idx_q`
    - _Bug_Condition: write_addr0[3:2] != 2'b0 AND write_notify0 triggers incorrect proc_idx=2'b00_
    - _Expected_Behavior: proc_idx_d = write_addr0[3:2] directly for all 4 line indices_
    - _Requirements: 2.4_

  - [ ] 5.3 Fix `inv_target` and `always_comb` dispatch block (BUG-004)
    - Remove all `proc_core = ...` and `proc_idx = ...` assignments from `always_comb`
    - Derive `inv_target = ~proc_core_q` at the top of the dispatch `always_comb` block
      (reads registered `_q` value only — no write–read conflict)
    - Update `remote_mirror_is_not_i`, `remote_has_copy` to use `proc_core_q`, `proc_idx_q`
    - _Bug_Condition: isBugCondition_004(X) — inv_target reads proc_core in same always_comb where proc_core is written_
    - _Expected_Behavior: inv_target = ~proc_core_q derived purely combinationally from stable registered value_
    - _Preservation: inv_target correct for both cores on cycle after COH_IDLE→PROCESS_WRITE transition_
    - _Requirements: 2.5, 2.6_

  - [ ] 5.4 Update `always_ff` sequential block to latch `_d` signals and initialize on reset
    - In reset branch: initialize `proc_core_q=1'b0`, `proc_idx_q=2'b0`, `last_served=1'b0`,
      all `mirror[c][l] = I`
    - In clocked branch: `proc_core_q <= proc_core_d`, `proc_idx_q <= proc_idx_d`
    - Remove any existing direct assignments to `proc_core` / `proc_idx` from `always_ff`
    - _Expected_Behavior: deterministic reset-initialised values on first active clock edge (Req 2.3)_
    - _Requirements: 2.1, 2.2, 2.3_

  - [ ] 5.5 Verify BUG-001/004 exploration test now passes (Property 1 — Fix Check)
    - **Property 1: Expected Behavior** - _d/_q Register Discipline
    - **IMPORTANT**: Re-run the SAME tests from task 1 — do NOT write new tests
    - Re-run PBT-1 (line-index extraction): `write_addr0=0x08` → assert `proc_idx_q=2'b10` — **MUST NOW PASS**
    - Re-run lint check: `verilator --lint-only -Wall rtl/coherence/coherence_ctrl.sv` — **MUST report zero multiple-driver errors**
    - Re-run `inv_target` hazard check: `inv_target = ~proc_core_q` reads only registered value — **MUST PASS**
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_

  - [ ] 5.6 Verify BUG-001/004 preservation tests still pass
    - **Property 2: Preservation** - Single-Core Coherence Sequence Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 2 — do NOT write new tests
    - Re-run all preservation tests from task 2 (single-notify FSM sequence, fill-notify, coh_enable=0)
    - **EXPECTED OUTCOME**: All tests still PASS — no regressions introduced
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

- [ ] 6. Fix BUG-005 — FSM Completeness: `inv_valid` Hold and Back-Pressure (`coherence_ctrl.sv`)

  - [ ] 6.1 Merge send-and-wait into `INVALIDATE_OTHER` — hold `inv_valid` until ack received
    - Rewrite `INVALIDATE_OTHER` case in `always_comb` FSM block:
      - Assert `inv_valid` for the target core every cycle while in `INVALIDATE_OTHER`
      - Advance `coh_state_next = COH_IDLE` AND assert `inv_fire = 1'b1` ONLY when `inv_ack` received
      - Do NOT advance to `WAIT_INV_ACK` in the same cycle as asserting `inv_valid`
    - Retain `WAIT_INV_ACK` encoding as safe-default fallback (`coh_state_next = COH_IDLE`)
    - _Bug_Condition: coh_state=INVALIDATE_OTHER AND NOT inv_ack — inv_valid dropped after 1 cycle_
    - _Expected_Behavior: inv_valid held asserted every cycle in INVALIDATE_OTHER until inv_ack received_
    - _Preservation: WAIT_INV_ACK→COH_IDLE transition on ack unchanged for any in-flight state_
    - _Requirements: 2.8, 3.8_

  - [ ] 6.2 Implement back-pressure for simultaneous write notifies (BUG-005 / BUG-006)
    - In `COH_IDLE` `always_comb` case:
      - When both `write_notify0` and `write_notify1` are asserted, grant only one
        (selected by round-robin `last_served`); keep `coh_accept` deasserted for the other
      - When FSM is NOT in `COH_IDLE`, assert `coh_accept0=0` and `coh_accept1=0`
        (back-pressure — do not silently drop the pending notify)
    - _Bug_Condition: coh_state=COH_IDLE AND write_notify0 AND write_notify1 — notify1 may be dropped_
    - _Expected_Behavior: coh_accept deasserted for un-granted core; cache manager holds notify until next IDLE_
    - _Preservation: single-notify processing unchanged — accepted immediately in IDLE (Req 3.7)_
    - _Requirements: 2.9, 3.7_

  - [ ] 6.3 Fix mirror M-update timing — update on COH_IDLE→PROCESS_WRITE transition cycle
    - In `always_ff`, add: when `coh_state == COH_IDLE && coh_state_next == PROCESS_WRITE`,
      set `mirror[proc_core_d][proc_idx_d] <= M`
    - (This uses `_d` values captured this cycle, so the mirror is correct on the very next cycle)
    - _Bug_Condition: mirror M-update happened in always_ff only when coh_state_next==PROCESS_WRITE, one cycle late_
    - _Expected_Behavior: mirror for writing core's line is M before or during PROCESS_WRITE cycle_
    - _Requirements: 2.7_

  - [ ] 6.4 Verify BUG-005 exploration test now passes (Property 1 — Fix Check)
    - **Property 1: Expected Behavior** - FSM Completeness and Notify Integrity
    - **IMPORTANT**: Re-run the SAME tests from task 3 (BUG-005 section) — do NOT write new tests
    - Re-run `inv_valid` hold test: hold `inv_ack=0` for 3 cycles in `INVALIDATE_OTHER` — `inv_valid` must stay asserted all 3 cycles — **MUST NOW PASS**
    - Re-run simultaneous notify drop test: `write_notify1` de-asserted early after `coh_accept0` — `write_notify1` must still be processed when FSM returns to IDLE — **MUST NOW PASS**
    - _Requirements: 2.7, 2.8, 2.9_

  - [ ] 6.5 Verify BUG-005/006 preservation tests still pass
    - **Property 2: Preservation** - Single-Notify Priority Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 2 — do NOT write new tests
    - Re-run preservation tests: single write notify accepted immediately in IDLE, WAIT_INV_ACK→IDLE on ack
    - **EXPECTED OUTCOME**: All tests PASS — no regressions
    - _Requirements: 3.7, 3.8, 3.9, 3.10_

- [ ] 7. Fix BUG-006 — Arbitration Fairness: Round-Robin `last_served` (`coherence_ctrl.sv`)

  - [ ] 7.1 Add round-robin arbitration using `last_served` register
    - In the `proc_core_d` / `proc_idx_d` `always_comb` block (Change 3 from design):
      - When both `write_notify0` and `write_notify1` are asserted simultaneously:
        - If `last_served == 1'b0` (core 0 was last): grant core 1 (`proc_core_d=1'b1`, `proc_idx_d=write_addr1[3:2]`)
        - If `last_served == 1'b1` (core 1 was last): grant core 0 (`proc_core_d=1'b0`, `proc_idx_d=write_addr0[3:2]`)
    - In the FSM `always_comb` `COH_IDLE` case, use the same `last_served` tiebreaker to set `coh_accept0/1`
    - In `always_ff`: update `last_served <= 1'b0` when `coh_accept0=1`; `last_served <= 1'b1` when `coh_accept1=1`
    - _Bug_Condition: isBugCondition_006(X) — write_notify0 AND write_notify1 AND arbitration_winner always core 0_
    - _Expected_Behavior: last_served alternates which core wins, max 1 consecutive grant when both competing_
    - _Preservation: single-notify (only one core active) accepted immediately regardless of last_served_
    - _Requirements: 2.10, 2.11, 3.9, 3.10_

  - [ ] 7.2 Verify BUG-006 exploration test now passes (Property 1 — Fix Check)
    - **Property 1: Expected Behavior** - Round-Robin Fairness
    - **IMPORTANT**: Re-run the SAME starvation test from task 3 (BUG-006 section) — do NOT write new tests
    - Re-run starvation PBT: 10 simultaneous-notify cycles — assert `coh_accept0` count ≈ `coh_accept1` count (max delta = 1) — **MUST NOW PASS**
    - Re-run back-pressure test: FSM busy + `write_notify1` asserted → `coh_accept1=0` until IDLE — **MUST NOW PASS**
    - _Requirements: 2.10, 2.11_

  - [ ] 7.3 Verify BUG-006 preservation tests still pass
    - **Property 2: Preservation** - Single-Notify Priority Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 2 and task 4 — do NOT write new tests
    - Single-notify sequences for both cores must still be accepted immediately in `COH_IDLE`
    - Full FSM sequence (`COH_IDLE → PROCESS_WRITE → INVALIDATE_OTHER → COH_IDLE`) must be unchanged
    - **EXPECTED OUTCOME**: All tests PASS
    - _Requirements: 3.9, 3.10_

- [ ] 8. Fix BUG-002 — Dead Signal Cleanup in `d_cache.sv`

  - [ ] 8.1 Fix `line_valid` port width from `[1:0]` to 1-bit
    - Change output declaration: `output logic line_valid[LINES-1:0]` (remove `[1:0]` width)
    - Update generate block assignment: `assign line_valid[i] = line_valid_reg[i]` (remove `{1'b0, ...}` padding)
    - _Bug_Condition: isBugCondition_002(X) — line_valid port width > 1, upper bit permanently zero_
    - _Expected_Behavior: line_valid[i] is 1-bit matching line_valid_reg[i] — no dead bit_
    - _Preservation: hit/miss detection uses line_valid_reg internally; port width change is transparent to cache logic_
    - _Requirements: 2.12, 3.11_

  - [ ] 8.2 Separate coherence state and request index into distinct output ports
    - Remove the mixed port: `output logic [1:0] line_state[LINES-1:0][$clog2(LINES)-1:0]`
    - Add clean coherence state port: `output logic [1:0] line_coh_state[LINES-1:0]`
    - Add clean request index port: `output logic [1:0] line_req_idx`
    - Update generate block: `assign line_coh_state[i] = line_state_reg[i]` for each line
    - Add standalone assignment: `assign line_req_idx = req_idx`
    - Update all consumers of the old `line_state` port (e.g., `coherence_ctrl.sv` instantiation,
      `state0_i` / `state1_i` connections) to use `line_coh_state`
    - _Bug_Condition: line_state port packs coherence state with req_idx — semantic mixing, dead bits_
    - _Expected_Behavior: line_coh_state[i] carries exactly I/S/M state; line_req_idx carries request index_
    - _Requirements: 2.13_

  - [ ] 8.3 Fix `line_out` width from 64 bits to 63 bits
    - Change output declaration: `output logic [62:0] line_out[LINES-1:0]`
    - Verify packing formula `{state[1:0], tag[27:0], data[31:0], valid}` = 2+28+32+1 = 63 bits
    - No assignment logic change needed — only the declared port width changes
    - Update any downstream consumers that reference `line_out[i][63]` (was always 0)
    - _Bug_Condition: line_out declared 64 bits with bit 63 permanently zero_
    - _Expected_Behavior: line_out is 63 bits wide with no dead bits; synthesis tools emit no width warnings_
    - _Requirements: 2.14_

  - [ ] 8.4 Verify BUG-002 exploration test now passes (Property 1 — Fix Check)
    - **Property 1: Expected Behavior** - Port Width Correctness
    - **IMPORTANT**: Re-run the SAME tests from task 3 (BUG-002 section) — do NOT write new tests
    - Re-run lint check: `verilator --lint-only -Wall rtl/cache/d_cache.sv` — **MUST report zero width-mismatch warnings**
    - Re-run dead bit test: `line_valid[i]` is 1-bit — no dead upper bit — **MUST NOW PASS**
    - Re-run state packing test: `line_coh_state[i]` carries only I/S/M state — **MUST NOW PASS**
    - Re-run `line_out` test: declared width is 63 bits — **MUST NOW PASS**
    - _Requirements: 2.12, 2.13, 2.14_

  - [ ] 8.5 Verify BUG-002 preservation tests still pass
    - **Property 2: Preservation** - Cache Storage and Hit/Miss Behavior Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 4 (BUG-002 preservation section) — do NOT write new tests
    - Re-run PBT-4: for all line states, `hit_data`, `hit`, `miss`, `hit_idx` are identical
    - Re-run invalidation test: `line_valid_reg=0`, `line_state_reg=I` after invalidation
    - **EXPECTED OUTCOME**: All tests PASS
    - _Requirements: 3.11, 3.12_

- [ ] 9. Fix BUG-003 — Illegal Assignments in `d_cache_mgr.sv`

  - [ ] 9.1 Move `fill_data_q` capture from `always_comb` to `always_ff`
    - Remove from `always_comb` (inside `AXI_R` state): `fill_data_q <= m_rdata`
    - Add to `always_ff` sequential block (inside `else` branch, state-guarded):
      ```systemverilog
      if (state == AXI_R && m_rvalid) begin
          fill_data_q <= m_rdata;
      end
      ```
    - Update `FILL` state in `always_comb` to use `fill_data_q` (already captured from
      previous cycle) as the source for `cache_wr_data` — do NOT use `m_rdata` directly
    - _Bug_Condition: isBugCondition_003(X) — NBA assignment <= in always_comb for fill_data_q_
    - _Expected_Behavior: fill_data_q captured in always_ff; FILL state reads fill_data_q (latched value)_
    - _Preservation: fill_data_q equals m_rdata after AXI_R cycle; cache_wr_data correct in FILL_
    - _Requirements: 2.15, 3.13_

  - [ ] 9.2 Remove `notify_pending` from `always_comb`, drive exclusively from `always_ff`
    - Remove from `always_comb` (inside `NOTIFY_COH` state): `notify_pending = 1'b1`
    - Drive `notify_pending` only from `always_ff`:
      ```systemverilog
      if (state == NOTIFY_COH) begin
          notify_pending <= 1'b1;
      end else if (state == IDLE || (state == NOTIFY_COH && coh_accept)) begin
          notify_pending <= 1'b0;
      end
      ```
    - Verify `notify_pending` is used only internally (not a module output) — no downstream rename needed
    - _Bug_Condition: notify_pending driven from both always_comb and always_ff — multi-driver conflict_
    - _Expected_Behavior: notify_pending has exactly one procedural driver (always_ff)_
    - _Preservation: hold-notify-until-accept behavior of dmem_ack sequence unchanged_
    - _Requirements: 2.16, 3.14_

  - [ ] 9.3 Verify BUG-003 exploration test now passes (Property 1 — Fix Check)
    - **Property 1: Expected Behavior** - No Illegal Assignments
    - **IMPORTANT**: Re-run the SAME tests from task 3 (BUG-003 section) — do NOT write new tests
    - Re-run Verilator lint: `verilator --lint-only -Wall rtl/cache/d_cache_mgr.sv` — **MUST report zero NBA-in-always_comb errors and zero multi-driver errors**
    - Re-run `fill_data_q` capture test: `m_rdata=0xCAFE_BABE` in `AXI_R` → `cache_wr_data=0xCAFE_BABE` in `FILL` — **MUST PASS in both simulation and post-synthesis simulation**
    - Re-run `notify_pending` multi-driver: VCS/Questa compile — **MUST report zero `%Error-MDRIVEN` errors**
    - _Requirements: 2.15, 2.16_

  - [ ] 9.4 Verify BUG-003 preservation tests still pass
    - **Property 2: Preservation** - Load-Miss Fill and Write-Through Sequences Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 4 (BUG-003 preservation section) — do NOT write new tests
    - Re-run PBT-5: for random `m_rdata` values, `fill_data_q` after `AXI_R` equals `m_rdata`
    - Re-run write-through pipeline: `dmem_ack` timing after `coh_accept` unchanged
    - **EXPECTED OUTCOME**: All tests PASS
    - _Requirements: 3.13, 3.14_

- [ ] 10. Fix BUG-007 — AXI-Lite Decoder Channel Separation (`axi_lite_decoder.sv`)

  - [ ] 10.1 Add separate write-channel and read-channel decode signal sets
    - Declare new internal signals: `wr_sel_sram`, `wr_sel_mmio`, `wr_sel_uart`, `wr_sel_gpio`, `wr_sel_decerr`
    - Declare new internal signals: `rd_sel_sram`, `rd_sel_mmio`, `rd_sel_uart`, `rd_sel_gpio`, `rd_sel_decerr`
    - Add write-channel `always_comb` decode block using `awaddr_m` only:
      - `wr_sel_sram = (awaddr_m[31:12] == 20'h00000)`, etc.
      - `wr_sel_decerr = !(wr_sel_sram | wr_sel_mmio | wr_sel_uart | wr_sel_gpio)`
    - Add read-channel `always_comb` decode block using `araddr_m` only:
      - `rd_sel_sram = (araddr_m[31:12] == 20'h00000)`, etc.
      - `rd_sel_decerr = !(rd_sel_sram | rd_sel_mmio | rd_sel_uart | rd_sel_gpio)`
    - Remove the old shared `assign sel_* = (awaddr_m ... ) || (araddr_m ...)` assignments
    - Expose write-channel decode via the external `sel_*` outputs (`assign sel_sram = wr_sel_sram`, etc.)
    - _Bug_Condition: isBugCondition_007(X) — awvalid AND arvalid with addresses decoding to different slaves_
    - _Expected_Behavior: wr_sel_* from awaddr only; rd_sel_* from araddr only; no cross-contamination_
    - _Requirements: 2.17_

  - [ ] 10.2 Route all write-channel muxes through `wr_sel_*`
    - Update `awready_sel`, `wready_sel`, `bvalid_sel`, `bresp_sel` to use `wr_sel_*`
    - Update `bready_sram`, `bready_mmio`, `bready_uart`, `bready_gpio` to gate on `wr_sel_*`
    - Update write-DECERR FSM `always_comb` to use `wr_sel_decerr` (was `sel_decerr`)
    - _Expected_Behavior: write-channel signals route exclusively via wr_sel_* decoded from awaddr_m_
    - _Requirements: 2.18_

  - [ ] 10.3 Route all read-channel muxes through `rd_sel_*`
    - Update `arready_sel`, `rvalid_sel`, `rdata_sel`, `rresp_sel` to use `rd_sel_*`
    - Update `rready_sram`, `rready_mmio`, `rready_uart`, `rready_gpio` to gate on `rd_sel_*`
    - Update read-DECERR path to use `rd_sel_decerr` for `ar_capture` (`arvalid_m && rd_sel_decerr`)
    - _Expected_Behavior: read-channel signals route exclusively via rd_sel_* decoded from araddr_m_
    - _Requirements: 2.19_

  - [ ] 10.4 Verify BUG-007 exploration test now passes (Property 1 — Fix Check)
    - **Property 1: Expected Behavior** - Independent Write and Read Channel Routing
    - **IMPORTANT**: Re-run the SAME tests from task 3 (BUG-007 section) — do NOT write new tests
    - Re-run simultaneous SRAM-write / UART-read test: `awaddr=0x100, araddr=0x10100` —
      assert `wr_sel_sram=1, rd_sel_uart=1` (exclusive, not both on same `sel_uart`) — **MUST NOW PASS**
    - Re-run all 4 cross-slave combinations — no `sel_*` cross-contamination — **MUST NOW PASS**
    - Verify `bvalid_m` reflects only SRAM `bvalid_sram` (write path) — **MUST NOW PASS**
    - _Requirements: 2.17, 2.18, 2.19_

  - [ ] 10.5 Verify BUG-007 preservation tests still pass
    - **Property 2: Preservation** - Single-Channel Transactions Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 4 (BUG-007 preservation section) — do NOT write new tests
    - Re-run PBT-6: write-only and read-only transactions to all 4 slaves — all channel signals match original
    - Re-run DECERR preservation: unmapped addresses on either channel alone produce correct DECERR response
    - Re-run RST-to-IDLE: `rst_n` deasserted → DECERR FSM returns to `DEC_IDLE`, `rvalid_decerr=0`
    - **EXPECTED OUTCOME**: All tests PASS
    - _Requirements: 3.15, 3.16, 3.17, 3.18_

---

## Phase 4: Checkpoint — All Tests Pass

- [ ] 11. Checkpoint — Verify all tests pass and fixes are complete
  - Run the full test suite across all three fixed modules:
    - `rtl/coherence/coherence_ctrl.sv` — BUG-001, 004, 005, 006
    - `rtl/cache/d_cache.sv` — BUG-002
    - `rtl/cache/d_cache_mgr.sv` — BUG-003
    - `rtl/bus/axi_lite_decoder.sv` — BUG-007
  - Confirm all exploration tests (Property 1) now PASS on fixed code
  - Confirm all preservation tests (Property 2) still PASS on fixed code
  - Run Verilator `--lint-only -Wall` on all three files — zero errors or warnings
  - Run unit tests from design.md Testing Strategy (coherence_ctrl reset, proc_idx extraction
    for all 4 lines, round-robin, d_cache hit/miss, d_cache_mgr pipeline, axi_lite_decoder
    simultaneous channels)
  - Run integration tests IT-1 through IT-6 from design.md if the simulation environment is available
  - Confirm fix ordering was respected: BUG-001 → BUG-004/005/006 → BUG-002/003 → BUG-007
  - If any test fails or questions arise, pause and ask the user before proceeding
  - All 11 correctness properties (Properties 1–11 from design.md) must hold
