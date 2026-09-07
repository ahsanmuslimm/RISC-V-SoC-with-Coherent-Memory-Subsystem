# Coherence Controller RISC-V SoC — Bugfix Design

## Overview

Seven RTL bugs have been identified across three files in the dual-core RV32I SoC with
coherent memory subsystem. This document formalizes the bug conditions, root cause
analyses, concrete implementation changes, and testing strategy for each bug.

**Files Under Fix:**
- `rtl/coherence/coherence_ctrl.sv` — BUG-001, BUG-004, BUG-005, BUG-006
- `rtl/cache/d_cache.sv` and `rtl/cache/d_cache_mgr.sv` — BUG-002, BUG-003
- `rtl/bus/axi_lite_decoder.sv` — BUG-007

The fixes must be applied in dependency order: BUG-001 first (establishes the _d/_q
discipline that BUG-004/005/006 build on), then BUG-002/003 (independent of coherence
controller changes), then BUG-007 (independent of cache changes).

**Design Methodology:** For each bug we define:
- **C(X)**: the bug condition — input or state that triggers defective behavior
- **P(result)**: the property the fixed function must satisfy when C(X) holds
- **¬C(X)**: inputs that do not trigger the bug and must be preserved identically

---

## Glossary

- **Bug_Condition (C)**: The predicate C(X) that is true when the bug is triggered for input/state X
- **Property (P)**: The assertion that must hold on the output/behavior of the fixed function F' when C(X) is true
- **Preservation**: The requirement that F'(X) = F(X) for all X where ¬C(X) — the fix must not change correct behavior
- **_d / _q discipline**: SystemVerilog convention where `_q` denotes a registered (flip-flop output) signal and `_d` denotes the combinational next-value signal driven into that flip-flop
- **always_comb**: A SystemVerilog procedural block that infers purely combinational (stateless) logic; non-blocking assignments (`<=`) are illegal inside it
- **always_ff**: A SystemVerilog procedural block that infers sequential (flip-flop) logic; all signal updates use non-blocking assignments
- **NBA**: Non-Blocking Assignment — the `<=` operator; legal only in `always_ff`, illegal in `always_comb`
- **COH_IDLE / PROCESS_WRITE / INVALIDATE_OTHER / WAIT_INV_ACK**: The four states of the coherence controller FSM (encoded `2'd0`–`2'd3`)
- **I / S / M**: Coherence states: Invalid (`2'b00`), Shared (`2'b01`), Modified (`2'b10`)
- **mirror**: The 8-entry coherence state table in `coherence_ctrl.sv`, indexed as `mirror[core][line]`
- **proc_core_q / proc_idx_q**: Registered copies (flip-flop outputs) of the currently-processing core ID and line index inside `coherence_ctrl.sv`
- **proc_core_d / proc_idx_d**: Combinational next-values (flip-flop inputs) for `proc_core_q` / `proc_idx_q`
- **inv_target**: Derived signal identifying which core to invalidate (`~proc_core_q`)
- **last_served**: 1-bit round-robin arbitration register tracking which core was last granted `coh_accept`
- **wr_sel_* / rd_sel_***: Separate write-channel and read-channel address-decode select signals in `axi_lite_decoder.sv`
- **sel_decerr**: Asserted when the incoming address does not map to any known slave
- **fill_data_q**: Register in `d_cache_mgr.sv` that captures AXI read data for the cache fill operation
- **notify_pending**: Flag register in `d_cache_mgr.sv` that records a pending coherence write-notify handshake
- **line_valid_reg**: 1-bit per-line valid storage inside `d_cache.sv`
- **line_state_reg**: 2-bit per-line I/S/M coherence state storage inside `d_cache.sv`

---

## Bug Details

### BUG-001 — _d/_q Discipline: Illegal Registered-Signal Assignments in always_comb

#### Bug Condition

The bug manifests in `coherence_ctrl.sv` when the `always_comb` FSM block makes direct
assignments to `proc_core` and `proc_idx` — signals that are also updated in `always_ff`.
This creates multiple drivers and undefined evaluation order.  Additionally, the
`always_comb` block computes `proc_idx` using a boolean test (`write_addr0[3:2] ? 2'b0 :
write_addr1[3:2]`) rather than a direct bit extraction, yielding an incorrect index
whenever `write_addr0[3:2]` is non-zero.

**Formal Specification:**
```
FUNCTION isBugCondition_001(X)
  INPUT: X = (coh_state, write_notify0, write_notify1, write_addr0, write_addr1)
  OUTPUT: boolean

  RETURN (coh_state = COH_IDLE AND (write_notify0 OR write_notify1))
         // always_comb assigns proc_core/proc_idx: multiple-driver violation
         OR (write_addr0[3:2] != 2'b0 AND write_notify0)
         // boolean coercion makes proc_idx = 2'b0 instead of write_addr0[3:2]
END FUNCTION
```

#### Concrete Examples

| Scenario | `write_addr0[3:2]` | Defective `proc_idx` | Correct `proc_idx` |
|---|---|---|---|
| Core 0 writes to line 2 (`addr=0x08`) | `2'b10` | `2'b00` (boolean TRUE→0) | `2'b10` |
| Core 0 writes to line 1 (`addr=0x04`) | `2'b01` | `2'b00` (boolean TRUE→0) | `2'b01` |
| Core 0 writes to line 0 (`addr=0x00`) | `2'b00` | `2'b11` (boolean FALSE→addr1) | `2'b00` |
| Simultaneous always_comb + always_ff write to `proc_core` | any | X / race | stable _q value |

---

### BUG-004 — _d/_q Synchronization: Read-Before-Write Hazard on `inv_target`

#### Bug Condition

In the existing `always_comb` dispatch decision block, `inv_target` is computed as
`~proc_core`. However, `proc_core` is also assigned in the same `always_comb` block
(under the `COH_IDLE` branch), creating a read-before-write hazard: whether `inv_target`
sees the old or new value of `proc_core` depends on simulator evaluation order.

**Formal Specification:**
```
FUNCTION isBugCondition_004(X)
  INPUT: X = (coh_state, write_notify0, write_notify1)
  OUTPUT: boolean

  RETURN coh_state = COH_IDLE
         AND (write_notify0 OR write_notify1)
         // inv_target reads proc_core in same always_comb where proc_core is written
         // evaluation order is non-deterministic → inv_target may be stale
END FUNCTION
```

#### Concrete Examples

- **Core 0 write arrives in IDLE**: `proc_core` is written `1'b0` in the IDLE branch, but
  `inv_target = ~proc_core` earlier in the block may still read the previous cycle's
  `proc_core` value, giving `inv_target = ~(prev_proc_core)` instead of `1'b1`.
- **After reset**: `proc_core` was reset to `1'b0`; the first write from core 0 correctly
  gives `inv_target = 1'b1` only by accident because reset value matches. A write from
  core 1 first would set `proc_core = 1'b1` and then `inv_target` might read `~0 = 1`
  instead of `0`.

---

### BUG-005 — FSM Completeness: Dropped Simultaneous Notifies and Missing `inv_valid` Hold

#### Bug Condition

Three sub-issues:
1. `INVALIDATE_OTHER` asserts `inv_fire` and immediately advances to `WAIT_INV_ACK` in
   one cycle — the inv_valid is never held in `INVALIDATE_OTHER` (it disappears after one
   cycle before the target can ack).
2. When both `write_notify0` and `write_notify1` arrive simultaneously in `COH_IDLE`, the
   FSM grants `coh_accept0` but no mechanism prevents `write_notify1` from being lost if
   core 1 de-asserts its notify before the FSM returns to IDLE.
3. The mirror M-update for the writing core happens in `always_ff` only when
   `coh_state_next == PROCESS_WRITE`, so on the transition cycle the mirror may be stale.

**Formal Specification:**
```
FUNCTION isBugCondition_005(X)
  INPUT: X = (coh_state, write_notify0, write_notify1, inv_ack0, inv_ack1)
  OUTPUT: boolean

  RETURN (coh_state = INVALIDATE_OTHER AND NOT (inv_ack0 OR inv_ack1))
         // inv_valid dropped after 1 cycle even though ack not received
         OR (coh_state = COH_IDLE AND write_notify0 AND write_notify1)
         // write_notify1 may be dropped if core 1 doesn't hold it long enough
END FUNCTION
```

#### Concrete Examples

- **INVALIDATE_OTHER with slow target**: `inv_valid1=1` for one cycle, FSM moves to
  `WAIT_INV_ACK`; if the target cache manager requires 2 cycles to respond, the first
  cycle of `WAIT_INV_ACK` has `inv_valid1=0`, which breaks the level-signal contract.
- **Simultaneous writes**: Both cores assert notify; core 0 gets `coh_accept0`; if core 1
  de-asserts `write_notify1` before the FSM returns to IDLE (e.g., cache manager has a
  timeout), the notify is silently dropped.

---

### BUG-006 — Arbitration Fairness: Core 0 Starvation Risk

#### Bug Condition

`COH_IDLE` always checks `write_notify0` first with a static `if / else if` priority.
If core 0 continuously issues write notifies (e.g., streaming stores), core 1 can never
acquire the coherence FSM.

**Formal Specification:**
```
FUNCTION isBugCondition_006(X)
  INPUT: X = (write_notify0, write_notify1, last_served)
  OUTPUT: boolean

  // Bug fires when both notifies are simultaneously asserted AND
  // the arbitration ignores last_served, always preferring core 0
  RETURN write_notify0 AND write_notify1
         AND (arbitration_winner = 1'b0)  // core 0 always wins
         AND (last_served = 1'b0)         // even when core 0 was just served
END FUNCTION
```

#### Concrete Example

- Cycle 1: both notifies high → core 0 granted (core 0 last served)
- Cycle 2: core 0 re-asserts immediately → core 0 granted again (starvation)
- Core 1's write is never coherence-processed → stale S-state line persists → data hazard

---

### BUG-002 — Dead Signal Cleanup: Incorrect Port Widths in `d_cache.sv`

#### Bug Condition

Three output ports carry structurally dead bits:

1. `line_valid[i]` is declared `logic [1:0]` but driven as `{1'b0, line_valid_reg[i]}` —
   the upper bit is permanently zero.
2. `line_state[i]` is declared as a 2-D array mixing coherence state and `req_idx` by
   packing `{line_state_reg[i], req_idx}` — the lower 2 bits carry an unrelated index.
3. `line_out[i]` is declared 64 bits but only 63 bits of data exist
   (`2+28+32+1 = 63`) — bit 63 is always zero.

**Formal Specification:**
```
FUNCTION isBugCondition_002(X)
  INPUT: X = (elaboration of d_cache.sv module)
  OUTPUT: boolean

  RETURN (line_valid port width > 1)                  // upper bit always 0
         OR (line_state port packs req_idx with state)  // semantic mixing
         OR (line_out port width > 63)                  // bit 63 always 0
END FUNCTION
```

#### Concrete Examples

- `line_valid[0]` = `{1'b0, 1'b1}` = `2'b01` when line 0 is valid. A downstream
  consumer testing `if (line_valid[0])` gets `2'b01` (non-zero = true), but testing
  `if (line_valid[0][1])` always gets `1'b0` — misleadingly dead.
- `line_state[2]` = `{2'b10, 2'b11}` = `4'b1011` where bits [3:2] = M state and
  bits [1:0] = current `req_idx = 2'b11` (address bits of an unrelated request).
- `line_out[3]` bit 63 = always `1'b0`; synthesis tools may warn or trim it, causing
  mismatches if downstream logic uses `line_out[i][63]`.

---

### BUG-003 — Illegal Signal Assignments: NBA in `always_comb`, Multi-Driver `notify_pending`

#### Bug Condition

Two violations of synthesisable SystemVerilog in `d_cache_mgr.sv`:

1. In the `AXI_R` state: `fill_data_q <= m_rdata` appears inside `always_comb` — a
   non-blocking assignment in a combinational block is illegal and causes
   simulation–synthesis mismatch (synthesizers ignore it; simulators may or may not
   execute it).
2. `notify_pending` is assigned in `always_comb` (inside `NOTIFY_COH` state) AND also
   implicitly driven by `always_ff` reset. Two separate always blocks driving the same
   `logic` signal creates a multi-driver conflict.

**Formal Specification:**
```
FUNCTION isBugCondition_003(X)
  INPUT: X = (source text of d_cache_mgr.sv)
  OUTPUT: boolean

  RETURN (NBA assignment "<=" found in always_comb block)
         OR (signal driven from both always_comb and always_ff)
END FUNCTION
```

#### Concrete Examples

- **Simulation**: `fill_data_q <= m_rdata` in `always_comb` is scheduled as an NBA
  update; on the same delta cycle, `always_ff` may not fire, so `fill_data_q` may be
  updated — but on synthesis it is ignored, causing post-synthesis simulation to diverge.
- **notify_pending multi-driver**: `always_comb` sets `notify_pending = 1'b1` in
  `NOTIFY_COH`; `always_ff` resets it to `1'b0`. VCS/Questa issue a "multiple drivers"
  error; Verilator may silently pick one, causing non-deterministic behavior.

---

### BUG-007 — AXI-Lite Decoder Channel Separation (`axi_lite_decoder.sv`)

#### Bug Condition

The existing decoder computes `sel_sram`, `sel_mmio`, `sel_uart`, `sel_gpio` by OR-ing
both `awaddr_m` and `araddr_m` decode results into a single set of select signals. When
a write transaction and a read transaction are simultaneously active (targeting different
slaves), one slave's ready/response signals leak into the other channel.

**Formal Specification:**
```
FUNCTION isBugCondition_007(X)
  INPUT: X = (awvalid_m, awaddr_m, arvalid_m, araddr_m)
  OUTPUT: boolean

  RETURN awvalid_m AND arvalid_m
         AND (slave_decode(awaddr_m) != slave_decode(araddr_m))
         // e.g., write to SRAM (0x00000100) and read from UART (0x00010100)
         // → sel_sram = 1 (from awaddr) | 0 = 1
         //   sel_uart = 0 | 1 (from araddr) = 1
         // Both sel_sram and sel_uart are simultaneously asserted → mux corruption
END FUNCTION
```

#### Concrete Examples

| `awaddr_m` | `araddr_m` | Current `sel_sram` | Current `sel_uart` | Effect |
|---|---|---|---|---|
| `0x0000_0100` (SRAM) | `0x0001_0100` (UART) | `1` | `1` | Both high — write response corrupted |
| `0x0001_0000` (MMIO) | `0x0000_0800` (SRAM) | `1` | `0` | sel_sram=1 causes write to go to SRAM instead of MMIO |
| `0x0001_0200` (GPIO) | `0x0001_0100` (UART) | `0` | `1` | sel_uart=1 — GPIO write may get UART's bready |

---

## Expected Behavior

### Preservation Requirements

**BUG-001/004 (coherence_ctrl.sv — signal discipline):**
- Single-core write sequences (`COH_IDLE → PROCESS_WRITE → INVALIDATE_OTHER →
  WAIT_INV_ACK → COH_IDLE`) must continue to function exactly as before.
- Fill-notify updates to the mirror (R2, independent of FSM state) must continue.
- `coh_enable = 0` must continue to skip invalidation and return to IDLE directly.
- Reset must initialize all signals deterministically (`proc_core_q=0`, `proc_idx_q=0`,
  `inv_target=0`, all mirror entries = I).

**BUG-005/006 (coherence_ctrl.sv — FSM and arbitration):**
- When only one core asserts write notify, it must be accepted immediately in COH_IDLE.
- The WAIT_INV_ACK → COH_IDLE transition on ack receipt must be unchanged.
- `inv_valid` must remain asserted until `inv_ack` is received (already correct in
  `WAIT_INV_ACK`; must also be held if INVALIDATE_OTHER is merged).

**BUG-002 (d_cache.sv — port widths):**
- Cache hit/miss detection (tag match + valid + state != I) must be unchanged.
- Write and invalidation paths must continue to correctly update `line_valid_reg`,
  `line_state_reg`, `line_tag_reg`, `line_data_reg`.
- `hit_data` must continue to return the correct word on a cache hit.

**BUG-003 (d_cache_mgr.sv — illegal assignments):**
- Load miss → AXI read → cache fill data path must continue to store `m_rdata` correctly.
- Write-through store → coherence notify → `dmem_ack` sequence must be unchanged.
- `notify_pending` behavior (hold notify until accept) must continue to work.

**BUG-007 (axi_lite_decoder.sv — channel separation):**
- Write-only transactions to any mapped slave must continue to route correctly.
- Read-only transactions to any mapped slave must continue to route correctly.
- DECERR for unmapped addresses must continue on both channels.
- RST-to-IDLE behavior of the DECERR FSM must be unchanged.

**Scope of non-buggy inputs:**
- Any scenario where at most one AXI channel is active at a time is a ¬C(X) for BUG-007.
- Any scenario where the FSM is not in COH_IDLE and no simultaneous notifies are active
  is a ¬C(X) for BUG-005/006.
- Any `d_cache.sv` operation that does not inspect the dead upper bits is a ¬C(X)
  for BUG-002.

---

## Hypothesized Root Cause

### BUG-001 / BUG-004

1. **Missing _d/_q split**: The original author treated `proc_core` and `proc_idx` as
   simple variables rather than registers, placing next-value assignments inside
   `always_comb` alongside their use as combinational inputs.
2. **Boolean-coercion typo**: `write_addr0[3:2] ? 2'b0 : write_addr1[3:2]` was likely
   intended as `write_addr0[3:2]` but was accidentally written as a ternary with the
   wrong true-branch (`2'b0` instead of `write_addr0[3:2]`).
3. **Single-variable usage**: Because `proc_core` and `proc_idx` were written in
   `always_comb`, the author believed `always_ff` "latched" them via another path, not
   realizing the dual-driver conflict.

### BUG-005

1. **Two-state split for send-and-wait**: The design split `INVALIDATE_OTHER` (one-cycle
   send) and `WAIT_INV_ACK` (hold) — but the `inv_valid` output in `WAIT_INV_ACK` was
   correctly added, while `INVALIDATE_OTHER` was missing it. The `INVALIDATE_OTHER` state
   was supposed to be a transition-only state, but the output logic is deasserted on entry
   to `WAIT_INV_ACK`.
2. **Silent drop of second notify**: Priority arbitration without queuing means the second
   notify is only visible in IDLE; if the FSM is busy, back-pressure was never implemented.
3. **Mirror update timing**: Mirror M-update placed only in `always_ff` under
   `coh_state_next == PROCESS_WRITE` creates a one-cycle window where the mirror is stale.

### BUG-006

1. **Static `if / else if` priority**: The author used a simple priority chain without
   considering starvation scenarios under continuous core-0 write pressure.
2. **No pending-request register**: There is no mechanism to record that a notify arrived
   while the FSM was busy, so back-pressure relies entirely on the cache manager holding
   the notify signal indefinitely.

### BUG-002

1. **Padding oversight**: `line_valid` was likely declared `logic [1:0]` to match a
   neighboring 2-bit signal width without noticing the underlying register is 1-bit.
2. **Debug convenience turned into port**: `line_state` was packed with `req_idx` for
   waveform debugging convenience, but was left as a formal output port.
3. **Bit-count error**: `line_out` was declared 64 bits (`next power of 2` thinking) while
   the actual content is 63 bits.

### BUG-003

1. **NBA in always_comb**: `fill_data_q <= m_rdata` was copy-pasted from an `always_ff`
   context into `always_comb` without changing `<=` to `=`.
2. **Multi-driver flag**: `notify_pending` was first managed only in `always_ff`, then
   a combinational assignment was added later to immediately reflect the pending state,
   introducing the second driver.

### BUG-007

1. **Single decode block**: The original design used a single combinational decode that
   OR'd both addresses to simplify the code, not accounting for simultaneous
   active transactions on the two independent AXI-Lite channels.
2. **Shared `sel_*` output ports**: Because `sel_sram` etc. are module outputs (used by
   external monitors), they were kept as single signals rather than duplicated per-channel.

---

## Correctness Properties

Property 1: Bug Condition — _d/_q Register Discipline (BUG-001/BUG-004)

_For any_ state X where `isBugCondition_001(X)` or `isBugCondition_004(X)` holds —
specifically when `coh_state = COH_IDLE` and a write notify arrives — the fixed
`coherence_ctrl` SHALL assign `proc_core_q` and `proc_idx_q` exclusively from the
`always_ff` sequential block using next-value signals (`proc_core_d`, `proc_idx_d`), and
the `always_comb` block SHALL read only the registered `_q` versions of these signals,
so that no signal has more than one procedural driver and no evaluation-order dependency
exists.

**Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.6**

---

Property 2: Preservation — Single-Core Coherence Sequence Unchanged (BUG-001/BUG-004)

_For any_ input X where `¬isBugCondition_001(X)` — specifically any scenario where the
FSM is not in `COH_IDLE` or only one write notify arrives — the fixed `coherence_ctrl`
SHALL produce the same FSM transitions, `inv_valid`, `inv_idx`, `coh_accept`, and mirror
update behavior as the original module.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4**

---

Property 3: Bug Condition — FSM Completeness and Notify Integrity (BUG-005)

_For any_ input X where `isBugCondition_005(X)` holds — specifically when both write
notifies are simultaneously active or when `INVALIDATE_OTHER` is entered — the fixed
`coherence_ctrl` SHALL (a) hold `inv_valid` asserted until the corresponding `inv_ack`
is received, and (b) keep `coh_accept` deasserted for any core whose notify cannot be
immediately processed, preventing silent drops.

**Validates: Requirements 2.7, 2.8, 2.9**

---

Property 4: Bug Condition — Round-Robin Fairness (BUG-006)

_For any_ sequence of N ≥ 2 simultaneous write-notify pairs where both cores assert
concurrently, the fixed `coherence_ctrl` SHALL alternate which core is granted
`coh_accept` such that no core is denied more than 1 consecutive grant when both are
competing, using the `last_served` register as a round-robin tiebreaker.

**Validates: Requirements 2.10, 2.11**

---

Property 5: Preservation — Single-Notify Priority Unchanged (BUG-005/BUG-006)

_For any_ input X where only one write notify is active (`write_notify0 XOR
write_notify1`) and the FSM is in `COH_IDLE`, the fixed `coherence_ctrl` SHALL accept it
immediately (same cycle) regardless of `last_served`, identical to the original behavior.

**Validates: Requirements 3.7, 3.8, 3.9, 3.10**

---

Property 6: Bug Condition — Port Width Correctness (BUG-002)

_For any_ elaboration of the fixed `d_cache`, the module SHALL declare `line_valid` as
a 1-bit-per-element array, `line_coh_state` as a 2-bit-per-element array (separate from
`line_req_idx`), and `line_out` as exactly 63 bits wide (or 64 bits with bit 63 carrying
a documented, non-constant value), so that no output port contains permanently-zero dead
bits.

**Validates: Requirements 2.12, 2.13, 2.14**

---

Property 7: Preservation — Cache Storage and Hit/Miss Behavior Unchanged (BUG-002)

_For any_ cache access X where the bug condition does not affect the hit/miss path
(i.e., `line_valid_reg`, `line_tag_reg`, `line_data_reg`, `line_state_reg` are
unaffected by the port-width change), the fixed `d_cache` SHALL return the same `hit`,
`miss`, `hit_idx`, and `hit_data` values as the original module.

**Validates: Requirements 3.11, 3.12**

---

Property 8: Bug Condition — No Illegal Assignments (BUG-003)

_For any_ state X of the fixed `d_cache_mgr` where `isBugCondition_003(X)` held in the
original code (specifically when the FSM is in `AXI_R` and `m_rvalid` is asserted, or
when `NOTIFY_COH` state is active), the fixed module SHALL capture `fill_data_q <=
m_rdata` only inside `always_ff`, and `notify_pending` SHALL be driven exclusively from
`always_ff`, so that no NBA appears in any `always_comb` block and no signal has two
procedural drivers.

**Validates: Requirements 2.15, 2.16**

---

Property 9: Preservation — Load-Miss Fill and Write-Through Sequences Unchanged (BUG-003)

_For any_ cache-manager transaction X where `¬isBugCondition_003(X)` — i.e., any
transaction that does not involve the AXI_R NBA or notify_pending multi-driver — the
fixed `d_cache_mgr` SHALL produce the same `fill_data_q` value after AXI read, the same
`cache_wr_data` in `FILL`, and the same `dmem_ack` timing as the original module.

**Validates: Requirements 3.13, 3.14**

---

Property 10: Bug Condition — Independent Write and Read Channel Routing (BUG-007)

_For any_ input X where `isBugCondition_007(X)` holds — specifically when `awvalid_m`
and `arvalid_m` are simultaneously asserted with addresses that decode to different
slaves — the fixed `axi_lite_decoder` SHALL route write-channel signals (`awready_m`,
`wready_m`, `bvalid_m`, `bresp_m`, `bready_*`) using only `wr_sel_*` signals decoded
from `awaddr_m`, and route read-channel signals (`arready_m`, `rvalid_m`, `rdata_m`,
`rresp_m`, `rready_*`) using only `rd_sel_*` signals decoded from `araddr_m`, so that
the two channels do not interfere.

**Validates: Requirements 2.17, 2.18, 2.19**

---

Property 11: Preservation — Single-Channel Transactions Unchanged (BUG-007)

_For any_ input X where `¬isBugCondition_007(X)` — i.e., only a write or only a read
is active, or both are active to the same slave — the fixed `axi_lite_decoder` SHALL
produce the same `awready_m`, `bvalid_m`, `bresp_m`, `arready_m`, `rvalid_m`, `rdata_m`,
`rresp_m`, and all `sel_*`, `bready_*`, `rready_*` outputs as the original module.

**Validates: Requirements 3.15, 3.16, 3.17, 3.18**

---

## Fix Implementation

### File: `rtl/coherence/coherence_ctrl.sv` (BUG-001, BUG-004, BUG-005, BUG-006)

#### Change 1 — Introduce _d/_q signal pairs (BUG-001/BUG-004)

**Remove** the existing bare declarations:
```systemverilog
logic        proc_core;
logic [1:0]  proc_idx;
logic        inv_target;
```

**Replace with:**
```systemverilog
// Registered values (_q = flip-flop output)
logic        proc_core_q;
logic [1:0]  proc_idx_q;
logic        inv_target;   // purely combinational, derived from proc_core_q

// Next-value wires (_d = flip-flop input)
logic        proc_core_d;
logic [1:0]  proc_idx_d;

// Round-robin arbitration register (BUG-006)
logic        last_served;  // 0 = core 0 was last granted, 1 = core 1 was last granted
```

#### Change 2 — Fix the dispatch decision logic (BUG-001/BUG-004)

**Remove** the erroneous `proc_idx` and `proc_core` assignments from `always_comb`:
```systemverilog
// REMOVE these lines from always_comb:
proc_idx = write_addr0[3:2] ? 2'b0 : write_addr1[3:2];  // ← delete
```

**Replace the dispatch always_comb block with:**
```systemverilog
always_comb begin
    // Derive inv_target purely from registered proc_core_q (no write in this block)
    inv_target = ~proc_core_q;

    // Check remote copy using registered proc_core_q / proc_idx_q
    remote_mirror_is_not_i = (mirror[inv_target][proc_idx_q] != I);
    remote_actual_is_not_i = (valid1_i[proc_idx_q] && (state1_i[proc_idx_q] != I)) ||
                              (valid0_i[proc_idx_q] && (state0_i[proc_idx_q] != I));
    remote_has_copy = remote_mirror_is_not_i || remote_actual_is_not_i;
end
```

#### Change 3 — Add next-value combinational logic for _d signals (BUG-001)

**Add a new always_comb block** for computing `proc_core_d` and `proc_idx_d` with
round-robin arbitration (also covers BUG-006):
```systemverilog
always_comb begin
    // Default: hold registered values
    proc_core_d = proc_core_q;
    proc_idx_d  = proc_idx_q;

    if (coh_state == COH_IDLE) begin
        if (write_notify0 && write_notify1) begin
            // Simultaneous: use round-robin tiebreaker (BUG-006)
            if (last_served == 1'b0) begin
                // Core 0 was last served → grant core 1
                proc_core_d = 1'b1;
                proc_idx_d  = write_addr1[3:2];
            end else begin
                // Core 1 was last served → grant core 0
                proc_core_d = 1'b0;
                proc_idx_d  = write_addr0[3:2];
            end
        end else if (write_notify0) begin
            proc_core_d = 1'b0;
            proc_idx_d  = write_addr0[3:2];  // direct extraction, no boolean (BUG-001)
        end else if (write_notify1) begin
            proc_core_d = 1'b1;
            proc_idx_d  = write_addr1[3:2];
        end
    end
end
```

#### Change 4 — Rewrite always_comb FSM output block (BUG-001, BUG-005)

**Remove** all `proc_core = ...` and `proc_idx = ...` assignments from the FSM
`always_comb` case block.  Update `COH_IDLE` to use round-robin arbitration for
`coh_accept` outputs (also covers BUG-006 back-pressure):
```systemverilog
always_comb begin
    coh_state_next  = coh_state;
    coh_accept0     = 1'b0;
    coh_accept1     = 1'b0;
    inv_valid0      = 1'b0;
    inv_valid1      = 1'b0;
    inv_idx0        = 2'b0;
    inv_idx1        = 2'b0;
    inv_fire        = 1'b0;

    case (coh_state)

      COH_IDLE: begin
        if (write_notify0 && write_notify1) begin
            // Round-robin: grant only one, back-pressure the other (BUG-005/BUG-006)
            if (last_served == 1'b0) begin
                coh_accept1    = 1'b1;   // grant core 1
                coh_state_next = PROCESS_WRITE;
            end else begin
                coh_accept0    = 1'b1;   // grant core 0
                coh_state_next = PROCESS_WRITE;
            end
            // The non-granted core keeps coh_accept=0 → back-pressure (BUG-005)
        end else if (write_notify0) begin
            coh_accept0    = 1'b1;
            coh_state_next = PROCESS_WRITE;
        end else if (write_notify1) begin
            coh_accept1    = 1'b1;
            coh_state_next = PROCESS_WRITE;
        end
      end

      PROCESS_WRITE: begin
        if (remote_has_copy && coh_enable) begin
            coh_state_next = INVALIDATE_OTHER;
        end else begin
            coh_state_next = COH_IDLE;
        end
      end

      INVALIDATE_OTHER: begin
        // Assert inv_valid AND hold it here (not dropped after 1 cycle) (BUG-005)
        if (proc_core_q == 1'b0) begin
            inv_valid1 = 1'b1;
            inv_idx1   = proc_idx_q;
            if (inv_ack1) begin
                inv_fire       = 1'b1;
                coh_state_next = COH_IDLE;
            end
        end else begin
            inv_valid0 = 1'b1;
            inv_idx0   = proc_idx_q;
            if (inv_ack0) begin
                inv_fire       = 1'b1;
                coh_state_next = COH_IDLE;
            end
        end
      end

      // WAIT_INV_ACK state is no longer needed (merged into INVALIDATE_OTHER above).
      // Keep it as a safe default that returns to IDLE to avoid X-states on
      // any in-flight simulation that reaches this encoding.
      WAIT_INV_ACK: begin
        coh_state_next = COH_IDLE;
      end

      default: begin
        coh_state_next = COH_IDLE;
      end

    endcase
end
```

> **Note:** Merging send-and-wait into `INVALIDATE_OTHER` (using the ack directly in that
> state) eliminates the one-cycle window where `inv_valid` was deasserted between
> `INVALIDATE_OTHER` and `WAIT_INV_ACK`. The `WAIT_INV_ACK` encoding is retained as a
> safe-default fallback.

#### Change 5 — Rewrite always_ff sequential block (BUG-001, BUG-004, BUG-005, BUG-006)

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        coh_state   <= COH_IDLE;
        proc_core_q <= 1'b0;
        proc_idx_q  <= 2'b0;
        last_served <= 1'b0;
        for (int c = 0; c < 2; c++)
            for (int l = 0; l < 4; l++)
                mirror[c][l] <= I;
    end else begin
        coh_state   <= coh_state_next;

        // Latch next-value _d signals into _q registers (BUG-001/BUG-004)
        proc_core_q <= proc_core_d;
        proc_idx_q  <= proc_idx_d;

        // Update last_served when a core is accepted in IDLE (BUG-006)
        if (coh_state == COH_IDLE) begin
            if (coh_accept0) last_served <= 1'b0;
            if (coh_accept1) last_served <= 1'b1;
        end

        // Mirror M-update: writing core's line → M (BUG-005 timing fix)
        // Update on the cycle the FSM accepts the notify (COH_IDLE→PROCESS_WRITE)
        if (coh_state == COH_IDLE && coh_state_next == PROCESS_WRITE) begin
            mirror[proc_core_d][proc_idx_d] <= M;
        end

        // Mirror I-update: remote line → I when invalidation ack received
        if (coh_state == INVALIDATE_OTHER && coh_state_next == COH_IDLE) begin
            mirror[~proc_core_q][proc_idx_q] <= I;
        end

        // Fill notify R2: independent of FSM state
        if (fill_notify0) mirror[1'b0][fill_idx0] <= S;
        if (fill_notify1) mirror[1'b1][fill_idx1] <= S;
    end
end
```

---

### File: `rtl/cache/d_cache.sv` (BUG-002)

#### Change 6 — Fix `line_valid` port width

**Remove:**
```systemverilog
output logic [1:0]  line_valid[LINES-1:0],  // Valid bits
```
**Replace with:**
```systemverilog
output logic        line_valid[LINES-1:0],  // Valid bits (1-bit per line)
```

**Update the generate block:**
```systemverilog
// REMOVE:
assign line_valid[i] = {1'b0, line_valid_reg[i]};
// REPLACE with:
assign line_valid[i] = line_valid_reg[i];
```

#### Change 7 — Separate `line_state` from `line_req_idx`

**Remove the mixed port:**
```systemverilog
output logic [1:0]  line_state[LINES-1:0][$clog2(LINES)-1:0],  // I/S/M per line
```
**Replace with two clean ports:**
```systemverilog
output logic [1:0]  line_coh_state[LINES-1:0],  // Coherence state I/S/M per line
output logic [1:0]  line_req_idx,                // Current request line index (req_addr[3:2])
```

**Update assignments:**
```systemverilog
// In generate block, remove old assignment:
// assign line_state[i] = {line_state_reg[i], req_idx};

// Replace generate block with:
generate
    for (genvar i = 0; i < LINES; i++) begin : output_state
        assign line_coh_state[i] = line_state_reg[i];
    end
endgenerate

// Standalone (outside generate):
assign line_req_idx = req_idx;   // req_addr[3:2], already computed above
```

**Update all consumers** (coherence_ctrl.sv uses `state0_i` / `state1_i` — those ports
connect to `line_coh_state`, so no rename is needed at the top level as long as the
instantiation is updated to use the new port name).

#### Change 8 — Fix `line_out` width (63 bits)

**Remove:**
```systemverilog
output logic [63:0] line_out[LINES-1:0],     // {state, tag, data, valid}
```
**Replace with:**
```systemverilog
output logic [62:0] line_out[LINES-1:0],     // {state[1:0], tag[27:0], data[31:0], valid}
```

The packing is already correct (`2+28+32+1 = 63`); only the declared width changes.

---

### File: `rtl/cache/d_cache_mgr.sv` (BUG-003)

#### Change 9 — Move `fill_data_q` capture to `always_ff`

**Remove from `always_comb` (inside `AXI_R` state):**
```systemverilog
fill_data_q <= m_rdata;   // ← illegal NBA in always_comb — DELETE
```

**Add to `always_ff` sequential block** (inside the `else` branch, guarded by state):
```systemverilog
// Capture AXI read data when valid (BUG-003)
if (state == AXI_R && m_rvalid) begin
    fill_data_q <= m_rdata;
end
```

Also update the `FILL` state in `always_comb` to use `fill_data_q` (already latched from
previous cycle) rather than `m_rdata` directly, since by the time we are in `FILL`,
`fill_data_q` holds the captured data:
```systemverilog
FILL: begin
    if (!uncached) begin
        if (pending_store) begin
            cache_wr_data  = merge_bytes(fill_data_q, wdata_q, wmask_q);
            cache_wr_state = 2'b10;   // M
        end else begin
            cache_wr_data  = fill_data_q;
            cache_wr_state = 2'b01;   // S
        end
        // ... rest unchanged
    end
end
```

#### Change 10 — Remove `notify_pending` from `always_comb`, drive only from `always_ff`

**Remove from `always_comb` (inside `NOTIFY_COH` state):**
```systemverilog
notify_pending = 1'b1;   // ← multi-driver — DELETE from always_comb
```

**Drive exclusively from `always_ff`:**
```systemverilog
// In always_ff:
if (state == NOTIFY_COH) begin
    notify_pending <= 1'b1;
end else if (state == IDLE || (state == NOTIFY_COH && coh_accept)) begin
    notify_pending <= 1'b0;
end
```

The `notify_pending` signal is not used as a combinational output to the outside — it is
only used internally by the FSM — so this change has no downstream effect.

---

### File: `rtl/bus/axi_lite_decoder.sv` (BUG-007)

#### Change 11 — Add separate write-channel and read-channel decode signals

**Remove the shared decode block:**
```systemverilog
// REMOVE:
assign sel_sram  = (awaddr_m[31:12] == 20'h00000) || (araddr_m[31:12] == 20'h00000);
assign sel_mmio  = ...;
assign sel_uart  = ...;
assign sel_gpio  = ...;
assign sel_decerr = ...;
```

**Replace with channel-specific signals:**
```systemverilog
// Write-channel decode (from awaddr_m only)
logic wr_sel_sram, wr_sel_mmio, wr_sel_uart, wr_sel_gpio, wr_sel_decerr;
always_comb begin
    wr_sel_sram  = (awaddr_m[31:12] == 20'h00000);
    wr_sel_mmio  = (awaddr_m[31:16] == 16'h0001) && (awaddr_m[15:8] == 8'h00);
    wr_sel_uart  = (awaddr_m[31:16] == 16'h0001) && (awaddr_m[15:8] == 8'h01);
    wr_sel_gpio  = (awaddr_m[31:16] == 16'h0001) && (awaddr_m[15:8] == 8'h02);
    wr_sel_decerr = !(wr_sel_sram | wr_sel_mmio | wr_sel_uart | wr_sel_gpio);
end

// Read-channel decode (from araddr_m only)
logic rd_sel_sram, rd_sel_mmio, rd_sel_uart, rd_sel_gpio, rd_sel_decerr;
always_comb begin
    rd_sel_sram  = (araddr_m[31:12] == 20'h00000);
    rd_sel_mmio  = (araddr_m[31:16] == 16'h0001) && (araddr_m[15:8] == 8'h00);
    rd_sel_uart  = (araddr_m[31:16] == 16'h0001) && (araddr_m[15:8] == 8'h01);
    rd_sel_gpio  = (araddr_m[31:16] == 16'h0001) && (araddr_m[15:8] == 8'h02);
    rd_sel_decerr = !(rd_sel_sram | rd_sel_mmio | rd_sel_uart | rd_sel_gpio);
end

// Expose the write-channel decode as the external sel_* outputs
// (downstream users wanting the write-side decode; can be changed to
// per-channel outputs if needed by integrators)
assign sel_sram = wr_sel_sram;
assign sel_mmio = wr_sel_mmio;
assign sel_uart = wr_sel_uart;
assign sel_gpio = wr_sel_gpio;
```

#### Change 12 — Route write-channel muxes through `wr_sel_*`

**Update all write-channel muxes** (awready, wready, bvalid, bresp, bready_*) to use
`wr_sel_*`:
```systemverilog
assign awready_sel = wr_sel_sram  ? awready_sram  :
                     wr_sel_mmio  ? awready_mmio  :
                     wr_sel_uart  ? awready_uart  :
                     wr_sel_gpio  ? awready_gpio  :
                     1'b1;   // DECERR

assign wready_sel  = wr_sel_sram  ? wready_sram   :
                     wr_sel_mmio  ? wready_mmio   :
                     wr_sel_uart  ? wready_uart   :
                     wr_sel_gpio  ? wready_gpio   :
                     1'b1;

assign bvalid_sel  = wr_sel_sram  ? bvalid_sram   :
                     wr_sel_mmio  ? bvalid_mmio   :
                     wr_sel_uart  ? bvalid_uart   :
                     wr_sel_gpio  ? bvalid_gpio   :
                     bvalid_decerr;

assign bresp_sel   = wr_sel_sram  ? bresp_sram    :
                     wr_sel_mmio  ? bresp_mmio    :
                     wr_sel_uart  ? bresp_uart    :
                     wr_sel_gpio  ? bresp_gpio    :
                     2'b11;

assign bready_sram = (wr_sel_sram && bready_m) || (!wr_sel_sram && !bvalid_sram);
assign bready_mmio = (wr_sel_mmio && bready_m) || (!wr_sel_mmio && !bvalid_mmio);
assign bready_uart = (wr_sel_uart && bready_m) || (!wr_sel_uart && !bvalid_uart);
assign bready_gpio = (wr_sel_gpio && bready_m) || (!wr_sel_gpio && !bvalid_gpio);
```

#### Change 13 — Route read-channel muxes through `rd_sel_*`

**Update all read-channel muxes** (arready, rvalid, rdata, rresp, rready_*) to use
`rd_sel_*`:
```systemverilog
assign arready_sel = rd_sel_sram  ? arready_sram  :
                     rd_sel_mmio  ? arready_mmio  :
                     rd_sel_uart  ? arready_uart  :
                     rd_sel_gpio  ? arready_gpio  :
                     1'b1;

assign rvalid_sel  = rd_sel_sram  ? rvalid_sram   :
                     rd_sel_mmio  ? rvalid_mmio   :
                     rd_sel_uart  ? rvalid_uart   :
                     rd_sel_gpio  ? rvalid_gpio   :
                     rvalid_decerr;

assign rdata_sel   = rd_sel_sram  ? rdata_sram    :
                     rd_sel_mmio  ? rdata_mmio    :
                     rd_sel_uart  ? rdata_uart    :
                     rd_sel_gpio  ? rdata_gpio    :
                     32'h0;

assign rresp_sel   = rd_sel_sram  ? rresp_sram    :
                     rd_sel_mmio  ? rresp_mmio    :
                     rd_sel_uart  ? rresp_uart    :
                     rd_sel_gpio  ? rresp_gpio    :
                     2'b11;

assign rready_sram = (rd_sel_sram && rready_m) || (!rd_sel_sram && !rvalid_sram);
assign rready_mmio = (rd_sel_mmio && rready_m) || (!rd_sel_mmio && !rvalid_mmio);
assign rready_uart = (rd_sel_uart && rready_m) || (!rd_sel_uart && !rvalid_uart);
assign rready_gpio = (rd_sel_gpio && rready_m) || (!rd_sel_gpio && !rvalid_gpio);
```

#### Change 14 — Fix DECERR FSM to use channel-specific signals

**Update the DECERR write FSM** to use `wr_sel_decerr` instead of the old `sel_decerr`:
```systemverilog
always_comb begin
    dec_state_d   = dec_state_q;
    bvalid_decerr = 1'b0;

    if (wr_sel_decerr) begin   // ← was sel_decerr
        unique case (dec_state_q)
            // ... unchanged logic inside ...
        endcase
    end
end
```

**Update the DECERR read path** to use `rd_sel_decerr`:
```systemverilog
assign ar_capture = arvalid_m && rd_sel_decerr;   // ← was sel_decerr
```

---

## Testing Strategy

### Validation Approach

The testing strategy follows the two-phase bug condition methodology:

**Phase 1 — Exploratory**: Run tests against the UNFIXED code to observe failures and
confirm or refute root cause hypotheses. Each test targets a specific `isBugCondition`
predicate. Counterexamples collected here drive root-cause confirmation.

**Phase 2 — Fix + Preservation**: After applying fixes, run the same tests to verify
Property 1–11 hold. Add property-based tests to sweep the input space for both bug
condition inputs (fix checking) and non-bug inputs (preservation checking).

---

### Exploratory Bug Condition Checking

**Goal:** Surface counterexamples demonstrating each bug on the unfixed code.

#### BUG-001/004 — _d/_q Discipline

**Test Plan:** Use a SystemVerilog testbench that drives `write_notify0=1`,
`write_addr0=32'h00000008` (line 2), monitors `proc_idx` after the clock edge, and
asserts it equals `2'b10`.  Run on unfixed code — expect `proc_idx = 2'b00` (boolean
coercion bug).

**Test Cases:**
1. **Line-index extraction test**: Drive `write_notify0=1`, `write_addr0=32'h00000008`,
   clock edge → assert `proc_idx_q == 2'b10` (will fail on unfixed code, gets `2'b00`)
2. **Index-3 test**: Drive `write_addr0=32'h0000000C`, assert `proc_idx_q == 2'b11`
   (will fail on unfixed code, gets `2'b11` only because `write_addr1[3:2]` happens to
   be `2'b11` if `write_addr1` is undriven — coincidentally correct or wrong)
3. **Multiple-driver check**: Use `$check_synthesis` or linting tool to confirm the
   always_comb/always_ff dual-driver error (Verilator `-Wall`, Questa `-lint`)

**Expected Counterexamples:**
- `proc_idx_q` after write notify from line 2 = `2'b00` instead of `2'b10`
- Linter reports: "multiple drivers for signal proc_core"

#### BUG-005 — FSM Completeness

**Test Cases:**
1. **Dropped simultaneous notify**: Assert `write_notify0=1` and `write_notify1=1`
   simultaneously; after FSM processes core 0, assert `write_notify1` is not
   acknowledged in the next IDLE cycle (will expose lack of back-pressure on unfixed code)
2. **inv_valid hold test**: In `INVALIDATE_OTHER`, hold `inv_ack1=0` for 3 cycles;
   observe whether `inv_valid1` is deasserted after cycle 1 (will fail on unfixed code —
   FSM moves to WAIT_INV_ACK, `inv_valid1` goes to 0 for 1 cycle before re-asserting)

**Expected Counterexamples:**
- `inv_valid1=0` for one cycle between `INVALIDATE_OTHER` and `WAIT_INV_ACK` when ack is slow
- `write_notify1` acknowledged only after core 1's notify is accidentally still asserted
  when FSM returns to IDLE (potential drop if notify was de-asserted)

#### BUG-006 — Arbitration Fairness

**Test Cases:**
1. **Starvation test**: Assert both notifies simultaneously for 10 consecutive IDLE
   cycles; count how many times each core is granted — expect near-equal (will fail on
   unfixed code: core 0 gets all 10)
2. **Back-pressure test**: Assert `write_notify1` while FSM is in `PROCESS_WRITE`;
   observe `coh_accept1` — should be `0` (back-pressure); accept it only on return to
   IDLE (unfixed code passes this since `coh_accept1` is never asserted while busy —
   but the notify itself may be dropped if core 1 stops asserting it)

**Expected Counterexamples:**
- Grant count: core 0 = 10, core 1 = 0 across 10 simultaneous cycles

#### BUG-002 — Dead Signals

**Test Cases:**
1. **Port-width check**: Elaborate `d_cache.sv` in a linter; assert `line_valid[i]` is
   1-bit wide (Verilator `-Wall` will report width mismatch)
2. **Dead bit test**: Drive a valid cache line; read `line_valid[0]`; check that bit 1
   is never `1` (it is always 0 — confirming it is dead, not that it is wrong)
3. **line_state packing check**: Read `line_state[0]` when `req_idx=2'b10` and
   `line_state_reg[0]=2'b01` (S); expect bits [3:2]=`2'b01`, bits [1:0]=`2'b10` —
   this demonstrates the semantic mixing

#### BUG-003 — Illegal Assignments

**Test Cases:**
1. **Lint/compile check**: Run Verilator `--lint-only`; will report "Unsupported: Non-blocking
   assignment in combinational always block" for `fill_data_q <= m_rdata`
2. **fill_data_q capture test**: Drive `m_rvalid=1`, `m_rdata=32'hDEAD_BEEF` in `AXI_R`
   state; in the `FILL` state check `cache_wr_data` equals `0xDEAD_BEEF` — on unfixed
   code this may work in simulation (NBA is processed) but fails post-synthesis
3. **notify_pending multi-driver**: Compile with VCS `-sv`; expect "multiple drivers"
   error on `notify_pending`

**Expected Counterexamples:**
- Verilator: `%Error: ... Non-blocking assignment in combinational always block`
- VCS: `%Error-MDRIVEN: Signal 'notify_pending' has multiple drivers`

#### BUG-007 — AXI Channel Separation

**Test Cases:**
1. **Simultaneous write-SRAM / read-UART**: Assert `awvalid_m=1, awaddr_m=0x00000100`
   and `arvalid_m=1, araddr_m=0x00010100` simultaneously; observe `sel_sram` and
   `sel_uart` — both will be `1` on unfixed code, demonstrating the routing corruption
2. **Write-response routing**: With scenario above, check whether `bvalid_m` reflects
   `bvalid_sram` (correct) or is corrupted by `bvalid_uart` — on unfixed code `sel_uart`
   also being high corrupts the mux

**Expected Counterexamples:**
- `sel_sram=1` AND `sel_uart=1` simultaneously → both will be asserted
- `arready_m` = `arready_uart` but also OR'd with `arready_sram` (both channels mixed)

---

### Fix Checking

**Goal:** After applying each fix, verify that all inputs satisfying the bug condition
now produce the expected (correct) behavior.

**Pseudocode:**
```
FOR ALL X WHERE isBugCondition_N(X) DO
  result := fixed_module(X)
  ASSERT P_N(result)    -- correctness property N holds
END FOR
```

**Specific checks:**
- BUG-001/004: `proc_idx_q` after `write_addr0=0x08` must be `2'b10`; linter reports
  no multiple-driver errors on `proc_core`, `proc_idx`, `notify_pending`
- BUG-005: `inv_valid1` must remain asserted for all cycles in `INVALIDATE_OTHER` until
  `inv_ack1` arrives; `coh_accept1` must be deasserted while FSM is not in `COH_IDLE`
- BUG-006: Across 10 simultaneous-notify cycles, `coh_accept0` count ≈ `coh_accept1`
  count (max delta = 1)
- BUG-002: `line_valid[i]` is 1-bit; `line_coh_state[i]` is 2-bit and carries only
  I/S/M state; `line_out[i]` is 63 bits
- BUG-003: No NBA in any `always_comb` block; `notify_pending` has exactly one driver;
  `fill_data_q` captures `m_rdata` correctly in simulation AND post-synthesis
- BUG-007: With simultaneous SRAM-write and UART-read, `wr_sel_sram=1, rd_sel_uart=1`;
  write mux routes to SRAM; read mux routes to UART; no cross-contamination

---

### Preservation Checking

**Goal:** Verify that for all inputs where the bug condition does NOT hold, the fixed
module produces the same result as the original module.

**Pseudocode:**
```
FOR ALL X WHERE NOT isBugCondition_N(X) DO
  ASSERT original_module(X) = fixed_module(X)
END FOR
```

**Property-based testing is recommended** because it can generate thousands of random
input sequences to confirm behavioral equivalence across the full non-buggy input space.

**Test Plan:**
1. **Coherence single-core preservation**: Generate random sequences of single-core write
   notifies (only `write_notify0` or only `write_notify1` active per cycle); compare FSM
   state sequence, `coh_accept`, `inv_valid`, `inv_idx` between original and fixed modules
2. **Cache hit/miss preservation**: Generate random `req_addr` values and cache-line
   states; verify `hit`, `miss`, `hit_idx`, `hit_data` are identical between original
   and fixed `d_cache`
3. **AXI single-channel preservation**: Generate random AXI write-only or read-only
   transactions; verify all channel signals match between original and fixed decoder
4. **DECERR preservation**: Generate unmapped addresses on either channel alone; verify
   DECERR response behavior is unchanged
5. **Fill + notify pipeline preservation**: In `d_cache_mgr`, run load-miss → AXI read →
   fill sequences; verify `dmem_rdata`, `dmem_ack`, `cache_wr_data` match

---

### Unit Tests

- **coherence_ctrl**:
  - Test reset: all mirror entries = I, `proc_core_q=0`, `proc_idx_q=0`, `coh_state=IDLE`
  - Test single write notify core 0: correct FSM sequence, `inv_valid1` held until ack,
    mirror transitions `I→M` for core 0, `S→I` for core 1
  - Test single write notify core 1: symmetric of above
  - Test `coh_enable=0`: no invalidation dispatched, direct IDLE return
  - Test fill notify: mirror updates to S regardless of FSM state
  - Test `proc_idx` extraction for all 4 line indices (addresses 0x00, 0x04, 0x08, 0x0C)
  - Test round-robin: 4 simultaneous-notify cycles → `last_served` alternates
  - Test back-pressure: notify arrives while FSM busy → `coh_accept=0` until IDLE

- **d_cache**:
  - Test initial state: all `line_valid_reg=0`, `line_state_reg=I`
  - Test write + hit: fill a line, request same tag → `hit=1`, `hit_data` correct
  - Test invalidation: fill a line, assert `inv_we` → `line_valid_reg=0`, `line_state_reg=I`
  - Test `line_coh_state[i]` = `line_state_reg[i]` for each line
  - Test `line_valid[i]` = `line_valid_reg[i]` (1-bit match)
  - Test `line_out[i]` bit packing: `{state,tag,data,valid}` = `line_out[i][62:0]`

- **d_cache_mgr**:
  - Test load-miss pipeline: IDLE→CHECK→MISS_READ→AXI_AR→AXI_R→FILL→AXI_AW→AXI_W→AXI_B→
    NOTIFY_COH→IDLE; verify `dmem_ack=1` after `coh_accept=1`
  - Test `fill_data_q` capture: `m_rdata=0xCAFEBABE` in AXI_R → `cache_wr_data=0xCAFEBABE` in FILL
  - Test `notify_pending` driven only from `always_ff`

- **axi_lite_decoder**:
  - Test write-only SRAM: `awaddr=0x100`, verify `awvalid_sram=1`, `bvalid_m=bvalid_sram`
  - Test read-only UART: `araddr=0x10100`, verify `arvalid_uart=1`, `rdata_m=rdata_uart`
  - Test simultaneous SRAM-write/UART-read: write routes to SRAM, read routes to UART
  - Test DECERR write FSM: unmapped `awaddr` → `bvalid_m=1`, `bresp_m=2'b11` after W
  - Test DECERR read: unmapped `araddr` → `rvalid_m=1`, `rresp_m=2'b11` next cycle

---

### Property-Based Tests

- **PBT-1 (BUG-001/004)**: For random write addresses where `addr[3:2]` is non-zero,
  assert `proc_idx_q == addr[3:2]` after a write notify cycle (covers all 4 line indices
  across thousands of random addresses)

- **PBT-2 (BUG-005)**: For random sequences where both notifies are simultaneously high,
  assert `inv_valid` is never deasserted mid-transaction (between the first assertion and
  the ack); assert no notify is silently dropped (every asserted `write_notify` is
  eventually followed by a matching `coh_accept`)

- **PBT-3 (BUG-006)**: For random interleaved sequences of simultaneous and single-core
  notifies, assert that the maximum consecutive grants to any one core when competing is ≤ 1

- **PBT-4 (BUG-002)**: For all cache line indices and all combinations of
  `line_state_reg` / `line_valid_reg`, assert `line_valid[i] == line_valid_reg[i]` and
  `line_coh_state[i] == line_state_reg[i]`

- **PBT-5 (BUG-003)**: For random AXI read data values, assert that `fill_data_q`
  after `AXI_R` equals the `m_rdata` driven in that cycle, and that `cache_wr_data` in
  `FILL` equals `fill_data_q` (or the merged value for store-misses)

- **PBT-6 (BUG-007)**: For all pairs of (write slave target, read slave target) across
  16 combinations, assert that write-channel signals exclusively use `wr_sel_*` and
  read-channel signals exclusively use `rd_sel_*`, with no cross-signal contamination

---

### Integration Tests

- **IT-1**: Full dual-core write conflict: core 0 writes line 2 while core 1 holds line
  2 in S state → coherence invalidation dispatched, acknowledged, mirror updated → both
  cores then read the correct data
- **IT-2**: Simultaneous write storms: core 0 and core 1 alternate writing the same line
  for 20 cycles → no starvation (core 1 is eventually processed), final cache state is
  coherent
- **IT-3**: AXI bus: simultaneous read from UART (I/O polling) and write to SRAM (DMA
  store) → both transactions complete correctly and independently
- **IT-4**: DECERR on both channels simultaneously: unmapped write address and unmapped
  read address arrive together → both get DECERR responses without interfering
- **IT-5**: Load miss under coherence pressure: cache miss triggers AXI read while
  coherence controller dispatches invalidation → `fill_notify` sent after fill, mirror
  updated to S, no deadlock
- **IT-6**: Reset recovery: assert `rst_n=0` mid-transaction; deassert; verify all FSMs
  return to correct idle states with deterministic register values
