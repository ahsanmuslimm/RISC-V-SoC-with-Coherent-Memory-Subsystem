# Bugfix Requirements Document

## Introduction

Seven RTL bugs have been identified across three files in the RISC-V dual-core SoC with coherent memory subsystem. The bugs span the coherence controller FSM (`rtl/coherence/coherence_ctrl.sv`), the data cache storage module (`rtl/cache/d_cache.sv`), and the AXI-Lite address decoder (`rtl/bus/axi_lite_decoder.sv`). Left unresolved, these bugs risk data corruption in multi-core scenarios, simulation-synthesis mismatches, and incorrect peripheral addressing or bus lockup. The fixes must be applied in dependency order: BUG-001 first (foundation for coherence fixes), followed by BUG-004/BUG-005/BUG-006, then BUG-002/BUG-003, and finally BUG-007.

---

## Bug Analysis

### BUG-001 — Coherence Controller _d / _q Signal Rework (`coherence_ctrl.sv`)

#### Current Behavior (Defect)

1.1 WHEN the coherence FSM is in `COH_IDLE` and a write notify arrives THEN the system makes illegal assignments to `proc_core` and `proc_idx` inside an `always_comb` block, violating the rule that registered signals must only be driven from `always_ff`.

1.2 WHEN the coherence FSM transitions from `COH_IDLE` to `PROCESS_WRITE` THEN the system relies on `proc_core` and `proc_idx` values that are also being driven in the combinational block, creating a race between the combinational and sequential drivers.

1.3 WHEN `rst_n` is asserted (driven low) for reset THEN the system's `always_ff` block checks `if (!rst_n)` correctly, but combinational helpers (`proc_idx`, `inv_target`) computed in `always_comb` reference registered signals (`proc_core`, `proc_idx`) before they have been updated, producing stale values on the first active cycle after reset.

1.4 WHEN the FSM is computing `proc_idx` in `always_comb` THEN the system evaluates `write_addr0[3:2] ? 2'b0 : write_addr1[3:2]`, which is a boolean condition on a 2-bit value rather than a line-index selection, producing an incorrect index whenever `write_addr0[3:2]` is non-zero.

#### Expected Behavior (Correct)

2.1 WHEN the coherence FSM is in `COH_IDLE` and a write notify arrives THEN the system SHALL assign `proc_core` and `proc_idx` exclusively inside the `always_ff` sequential block (or an equivalent registered update), removing all assignments to these signals from `always_comb`.

2.2 WHEN the coherence FSM transitions from `COH_IDLE` to `PROCESS_WRITE` THEN the system SHALL use only the registered (_q) values of `proc_core` and `proc_idx` in subsequent combinational logic, ensuring the values are stable for the full `PROCESS_WRITE` cycle.

2.3 WHEN `rst_n` is deasserted after reset THEN the system SHALL present deterministic, reset-initialised values for all registered coherence signals (`proc_core`, `proc_idx`, `inv_target`, `mirror`) on the very first active clock edge.

2.4 WHEN computing `proc_idx` from a write address THEN the system SHALL extract the line index directly from the address bits (e.g., `write_addr0[3:2]`) without applying an unintended boolean conversion.

#### Unchanged Behavior (Regression Prevention)

3.1 WHEN coherence is enabled and a write arrives from core 0 while core 1 holds the line in S or M state THEN the system SHALL CONTINUE TO transition through `COH_IDLE → PROCESS_WRITE → INVALIDATE_OTHER → WAIT_INV_ACK → COH_IDLE` and dispatch an invalidation to core 1.

3.2 WHEN coherence is enabled and a write arrives and the remote core does not hold the line THEN the system SHALL CONTINUE TO return to `COH_IDLE` from `PROCESS_WRITE` without dispatching an invalidation.

3.3 WHEN a fill notify arrives from either core THEN the system SHALL CONTINUE TO update the mirror entry to S state independently of the FSM's current state.

3.4 WHEN `coh_enable` is deasserted THEN the system SHALL CONTINUE TO skip invalidation dispatch and return directly to `COH_IDLE` from `PROCESS_WRITE`.

---

### BUG-004 — Coherence Controller _d/_q Signal Synchronization (`coherence_ctrl.sv`)

#### Current Behavior (Defect)

1.5 WHEN the `coh_state_next` combinational logic references `proc_core` and `proc_idx` THEN the system reads these signals from their `always_ff` registered values, but because `always_comb` also assigns them, simulators may see X or incorrect values depending on evaluation order.

1.6 WHEN `inv_target` is computed inside `always_comb` as `~proc_core` THEN the system uses the registered `proc_core` value, but `proc_core` is also written in the same `always_comb` block in the `COH_IDLE` branch, creating a read-before-write hazard within a single combinational evaluation.

#### Expected Behavior (Correct)

2.5 WHEN any combinational block references `proc_core`, `proc_idx`, or `inv_target` THEN the system SHALL use the registered (_q suffix) copies of these signals exclusively, so that combinational reads always observe stable, clock-edge-captured values.

2.6 WHEN `inv_target` is needed in combinational logic THEN the system SHALL derive it from the registered `proc_core_q` value (i.e., `inv_target = ~proc_core_q`) so there is no write–read conflict within the same `always_comb` block.

#### Unchanged Behavior (Regression Prevention)

3.5 WHEN a write arrives from core 0 THEN the system SHALL CONTINUE TO correctly identify core 1 as the invalidation target on the cycle after the `COH_IDLE→PROCESS_WRITE` transition.

3.6 WHEN a write arrives from core 1 THEN the system SHALL CONTINUE TO correctly identify core 0 as the invalidation target on the cycle after the `COH_IDLE→PROCESS_WRITE` transition.

---

### BUG-005 — Coherence Controller State Machine Issue (`coherence_ctrl.sv`)

#### Current Behavior (Defect)

1.7 WHEN the `PROCESS_WRITE` state is entered THEN the system does not explicitly update the mirror to M for the writing core inside the FSM combinational block; the mirror update is performed in `always_ff` only when `coh_state_next == PROCESS_WRITE`, meaning a missed edge causes the mirror to be incorrect for a full FSM cycle.

1.8 WHEN the FSM is in `INVALIDATE_OTHER` THEN the system unconditionally asserts `inv_fire` as a combinational pulse and simultaneously advances to `WAIT_INV_ACK` in the same cycle, meaning the invalidation address is presented for only one cycle before the FSM moves on, with no hold guarantee if the target cache is not ready.

1.9 WHEN `write_notify0` and `write_notify1` arrive simultaneously THEN the system grants `coh_accept0` but does not record `write_notify1`, which is silently dropped without any queuing or stall mechanism.

#### Expected Behavior (Correct)

2.7 WHEN the FSM enters `PROCESS_WRITE` THEN the system SHALL ensure the mirror for the writing core's line is updated to M before or during that cycle, so any coherence decision made in `PROCESS_WRITE` observes the correct, up-to-date mirror state.

2.8 WHEN the FSM is in `INVALIDATE_OTHER` and the target acknowledges THEN the system SHALL hold `inv_valid` asserted until the acknowledgement is received, combining the send-and-wait behaviour currently split across `INVALIDATE_OTHER` and `WAIT_INV_ACK` if needed, so the invalidation is never dropped.

2.9 WHEN `write_notify0` is being processed and `write_notify1` arrives THEN the system SHALL NOT drop `write_notify1`; instead, it SHALL keep `coh_accept1` deasserted until the current transaction completes, allowing core 1's cache manager to hold its notify.

#### Unchanged Behavior (Regression Prevention)

3.7 WHEN only one core sends a write notify at a time THEN the system SHALL CONTINUE TO process it within the four-state FSM sequence without modification to the core notification handshake.

3.8 WHEN the FSM reaches `WAIT_INV_ACK` and the ack arrives THEN the system SHALL CONTINUE TO transition back to `COH_IDLE` in one cycle and deassert `inv_valid`.

---

### BUG-006 — Coherence Controller Arbitration Logic (`coherence_ctrl.sv`)

#### Current Behavior (Defect)

1.10 WHEN both `write_notify0` and `write_notify1` are asserted simultaneously THEN the system always grants priority to core 0 with no fairness mechanism, allowing core 0 to starve core 1 if core 0 continuously issues write notifications.

1.11 WHEN the FSM is busy (not in `COH_IDLE`) and a new write notify arrives THEN the system silently ignores the new request because no pending-request register or back-pressure signal is maintained, potentially causing the cache manager to wait indefinitely.

#### Expected Behavior (Correct)

2.10 WHEN both cores simultaneously assert write notify THEN the system SHALL implement a fairness mechanism (e.g., round-robin or alternating priority) so that neither core can indefinitely starve the other.

2.11 WHEN the FSM is busy and a new write notify arrives from a core THEN the system SHALL keep `coh_accept` for that core deasserted until the FSM returns to `COH_IDLE`, providing implicit back-pressure that prevents the notify from being dropped.

#### Unchanged Behavior (Regression Prevention)

3.9 WHEN only one core asserts a write notify THEN the system SHALL CONTINUE TO accept it immediately in `COH_IDLE` regardless of which core it is.

3.10 WHEN the FSM is processing an invalidation sequence THEN the system SHALL CONTINUE TO complete the current sequence before accepting a new write notify.

---

### BUG-002 — Data Cache Dead Signal Cleanup (`d_cache.sv`)

#### Current Behavior (Defect)

1.12 WHEN `d_cache.sv` is elaborated THEN the system declares output ports `line_valid[LINES-1:0]` as `logic [1:0]` (2-bit), but the underlying register `line_valid_reg` is 1-bit, causing the output to carry a constant zero in the upper bit — the signal is effectively dead in its upper half.

1.13 WHEN `d_cache.sv` is elaborated THEN the system declares `line_state[LINES-1:0][$clog2(LINES)-1:0]` as a 2-D output port where each element is `$clog2(4)` = 2 bits wide, but packs `{line_state_reg[i], req_idx}` — mixing state and address index into a single port — producing a signal whose upper bits carry coherence state and lower bits carry an unrelated request index, making the port semantically ambiguous and partially dead.

1.14 WHEN `d_cache.sv` is elaborated THEN the output `line_out[i]` is declared as 64 bits but only 63 bits of meaningful data exist (`2+28+32+1`), leaving bit 63 always zero — a dead bit that complicates downstream consumption.

#### Expected Behavior (Correct)

2.12 WHEN `d_cache.sv` is elaborated THEN the system SHALL declare `line_valid` as a 1-bit-wide array (matching `line_valid_reg`) so that no dead upper bit is generated.

2.13 WHEN `d_cache.sv` is elaborated THEN the system SHALL separate coherence state and line index into distinct, correctly typed output ports so that each port carries exactly the information it names and no dead bits exist.

2.14 WHEN `d_cache.sv` is elaborated THEN the system SHALL either trim `line_out` to 63 bits or correctly fill bit 63 with a meaningful value, eliminating the always-zero dead bit.

#### Unchanged Behavior (Regression Prevention)

3.11 WHEN a cache line is filled by the cache manager THEN the system SHALL CONTINUE TO correctly store valid, tag, data, and state fields and return them through `hit_data` on a subsequent hit.

3.12 WHEN an invalidation is received THEN the system SHALL CONTINUE TO clear the valid bit and set the state to I for the targeted line.

---

### BUG-003 — Data Cache Illegal Signal Assignments (`d_cache.sv`)

#### Current Behavior (Defect)

1.15 WHEN the `AXI_R` state of `d_cache_mgr.sv` is active and `m_rvalid` is asserted THEN the system performs `fill_data_q <= m_rdata` inside an `always_comb` block (non-blocking assignment in combinational context), which is illegal in synthesisable SystemVerilog and causes simulation–synthesis mismatch.

1.16 WHEN the FSM states `NOTIFY_COH` and `WAIT_INVALIDATE` are active THEN the system assigns `notify_pending` inside `always_comb`, but `notify_pending` is declared as a `logic` register updated in `always_ff`, creating a multi-driver conflict between the combinational and sequential always blocks.

#### Expected Behavior (Correct)

2.15 WHEN `m_rvalid` is asserted in the `AXI_R` state THEN the system SHALL capture `m_rdata` into `fill_data_q` using a blocking assignment inside the `always_ff` sequential block (not in `always_comb`), eliminating the illegal NBA in combinational context.

2.16 WHEN `notify_pending` needs to be set or cleared THEN the system SHALL drive it exclusively from the `always_ff` block, removing any assignment to it from `always_comb`, to eliminate the multi-driver conflict.

#### Unchanged Behavior (Regression Prevention)

3.13 WHEN a load miss completes an AXI read THEN the system SHALL CONTINUE TO fill the correct cache line with the data returned by `m_rdata` and transition to the `FILL` state.

3.14 WHEN a write-through store completes THEN the system SHALL CONTINUE TO notify the coherence controller and wait for `coh_accept` before issuing `dmem_ack` to the core.

---

### BUG-007 — AXI-Lite Decoder Channel Separation (`axi_lite_decoder.sv`)

#### Current Behavior (Defect)

1.17 WHEN a read transaction (AR channel) and a write transaction (AW channel) are both pending simultaneously THEN the system computes `sel_sram`, `sel_mmio`, `sel_uart`, and `sel_gpio` using an OR of the write address (`awaddr_m`) and the read address (`araddr_m`), causing the selected slave to depend on both addresses at once and potentially routing the transaction to the wrong slave.

1.18 WHEN a write transaction targets slave A and a simultaneous read transaction targets slave B THEN the system OR's their address decode results, meaning slave A's ready/response signals are muxed alongside slave B's signals on a channel that should exclusively serve one transaction.

1.19 WHEN the DECERR FSM is active for a write transaction THEN the system checks `awvalid_m` and `wvalid_m` unconditionally in `always_comb`, but `bready_sram`, `bready_mmio`, `bready_uart`, and `bready_gpio` are computed using the shared `sel_*` signals that mix read and write addresses, potentially asserting `bready` to a slave that is not involved in the write transaction.

#### Expected Behavior (Correct)

2.17 WHEN address decode logic is evaluated THEN the system SHALL maintain separate write-channel select signals (computed from `awaddr_m` only) and separate read-channel select signals (computed from `araddr_m` only), so that a simultaneous read and write to different slaves does not corrupt either transaction's routing.

2.18 WHEN the write-channel muxes for `awready_m`, `wready_m`, `bvalid_m`, `bresp_m`, and `bready_*` are evaluated THEN the system SHALL use only write-channel select signals (derived from `awaddr_m`) to route responses.

2.19 WHEN the read-channel muxes for `arready_m`, `rvalid_m`, `rdata_m`, `rresp_m`, and `rready_*` are evaluated THEN the system SHALL use only read-channel select signals (derived from `araddr_m`) to route responses.

#### Unchanged Behavior (Regression Prevention)

3.15 WHEN a write-only transaction targets any mapped slave THEN the system SHALL CONTINUE TO route the AW, W, and B channel signals correctly to that slave and return the slave's `bresp` to the master.

3.16 WHEN a read-only transaction targets any mapped slave THEN the system SHALL CONTINUE TO route the AR and R channel signals correctly to that slave and return the slave's `rdata` and `rresp` to the master.

3.17 WHEN an access targets an unmapped address THEN the system SHALL CONTINUE TO respond with DECERR (response code `2'b11`) on the appropriate channel without hanging.

3.18 WHEN `rst_n` is deasserted THEN the system SHALL CONTINUE TO reset the DECERR FSM to `DEC_IDLE` and clear `rvalid_decerr`.

---

## Bug Condition Pseudocode

### BUG-001 / BUG-004 — Reset and _d/_q Signal Discipline

```pascal
FUNCTION isBugCondition_001(X)
  INPUT: X = (rst_n, write_notify0, write_notify1, coh_state)
  OUTPUT: boolean

  // Bug fires when proc_core/proc_idx are driven from always_comb
  RETURN (coh_state = COH_IDLE AND (write_notify0 OR write_notify1))
         OR (reset just deasserted AND any combinational read of proc_core/proc_idx occurs)
END FUNCTION

// Property: Fix Checking
FOR ALL X WHERE isBugCondition_001(X) DO
  result ← coherence_ctrl'(X)
  ASSERT proc_core_q and proc_idx_q are only updated in always_ff
  ASSERT no simultaneous always_comb and always_ff driver for proc_core/proc_idx
END FOR

// Property: Preservation Checking
FOR ALL X WHERE NOT isBugCondition_001(X) DO
  ASSERT coherence_ctrl(X) = coherence_ctrl'(X)
END FOR
```

### BUG-005 / BUG-006 — FSM Completeness and Arbitration Fairness

```pascal
FUNCTION isBugCondition_005(X)
  INPUT: X = (write_notify0, write_notify1, coh_state, inv_ack0, inv_ack1)
  OUTPUT: boolean

  RETURN (write_notify0 AND write_notify1)          // Simultaneous notifies
         OR (coh_state != COH_IDLE AND (write_notify0 OR write_notify1))  // Busy drop
         OR (coh_state = INVALIDATE_OTHER AND NOT inv_ack_received)       // Premature advance
END FUNCTION

// Property: Fix Checking
FOR ALL X WHERE isBugCondition_005(X) DO
  result ← coherence_ctrl'(X)
  ASSERT no write notify is silently dropped
  ASSERT inv_valid is held until ack received
  ASSERT fairness: no core is starved across N consecutive accesses
END FOR
```

### BUG-002 / BUG-003 — Dead and Illegal Signals in d_cache

```pascal
FUNCTION isBugCondition_002(X)
  INPUT: X = (line_valid_reg, line_state_reg, req_idx, fill_data_q)
  OUTPUT: boolean

  RETURN (line_valid output width != 1)
         OR (line_state port mixes coherence state and req_idx)
         OR (fill_data_q assigned via NBA in always_comb)
         OR (notify_pending driven from both always_comb and always_ff)
END FUNCTION

// Property: Fix Checking
FOR ALL X WHERE isBugCondition_002(X) DO
  result ← d_cache'(X)
  ASSERT all output port widths match their underlying register widths
  ASSERT no NBA (<=) appears in any always_comb block
  ASSERT no signal has more than one always driver
END FOR
```

### BUG-007 — AXI-Lite Channel Separation

```pascal
FUNCTION isBugCondition_007(X)
  INPUT: X = (awvalid_m, awaddr_m, arvalid_m, araddr_m)
  OUTPUT: boolean

  // Bug fires when both channels are active simultaneously to different slaves
  RETURN awvalid_m AND arvalid_m
         AND (slave_decode(awaddr_m) != slave_decode(araddr_m))
END FUNCTION

// Property: Fix Checking
FOR ALL X WHERE isBugCondition_007(X) DO
  result ← axi_lite_decoder'(X)
  ASSERT write channel routes to slave_decode(awaddr_m)
  ASSERT read  channel routes to slave_decode(araddr_m)
  ASSERT the two channels do not interfere with each other's ready/valid signals
END FOR

// Property: Preservation Checking
FOR ALL X WHERE NOT isBugCondition_007(X) DO
  ASSERT axi_lite_decoder(X) = axi_lite_decoder'(X)
END FOR
```
