/**
 * @file coherence_ctrl.sv
 * @brief Coherence Controller FSM (4-state, I/S/M invalidation protocol)
 * @project Dual-Core RV32I SoC with Coherent Memory Subsystem
 * @doc_ref logic_design/05_coherence_fsm.md §5.4–5.6
 * @date Day 2, Task T2.7
 *
 * FIXES APPLIED (Second Draft):
 *  BUG-001: Removed dual-driver on proc_core/proc_idx. Introduced proper _d/_q
 *           split: combinational next-values (_d) driven exclusively from always_comb,
 *           registered values (_q) updated exclusively from always_ff.
 *  BUG-004: inv_target now derives from registered proc_core_q only, eliminating the
 *           read-before-write hazard in the same always_comb block.
 *  BUG-005: INVALIDATE_OTHER now holds inv_valid asserted every cycle until inv_ack
 *           is received (merged send-and-wait). WAIT_INV_ACK retained as safe-default
 *           fallback. Back-pressure: coh_accept deasserted for un-granted core when
 *           both notify simultaneously, preventing silent drops.
 *  BUG-006: Round-robin last_served register eliminates core-0 starvation. Simultaneous
 *           write notifies are resolved by granting the core NOT last served.
 *
 * 4-state FSM managing cache coherence:
 *  - Tracks per-line, per-core coherence state (I/S/M)
 *  - Dispatches invalidations on write (2-core snooping)
 *  - Maintains 8-entry mirror (4 lines × 2 cores)
 *  - Implements R1 (coh_accept handshake for lossless notify)
 *  - Implements R2 (fill_notify updates mirror to S)
 *  - Implements R6 (dispatch reads actual cache state, not just mirror)
 *
 * States (per doc 05 §5.4):
 *  0: COH_IDLE (reset)
 *  1: PROCESS_WRITE
 *  2: INVALIDATE_OTHER
 *  3: WAIT_INV_ACK  (retained as safe-default; logic merged into INVALIDATE_OTHER)
 */

module coherence_ctrl (
  input  logic        clk,
  input  logic        rst_n,

  // Write notifications from cache managers (level signals, held until coh_accept)
  input  logic        write_notify0,
  input  logic [31:0] write_addr0,
  input  logic        write_notify1,
  input  logic [31:0] write_addr1,
  output logic        coh_accept0,     // 1-cycle pulse (R1)
  output logic        coh_accept1,

  // Fill notifications (load fill to S, 1-cycle pulse, R2)
  input  logic        fill_notify0,
  input  logic [1:0]  fill_idx0,
  input  logic        fill_notify1,
  input  logic [1:0]  fill_idx1,

  // Invalidation dispatch to cache managers
  output logic        inv_valid0,
  output logic [1:0]  inv_idx0,
  input  logic        inv_ack0,
  output logic        inv_valid1,
  output logic [1:0]  inv_idx1,
  input  logic        inv_ack1,

  // Actual cache line states (for dispatch truth, R6)
  input  logic [1:0]  state0_i[3:0],   // Actual state per line from cache 0
  input  logic        valid0_i[3:0],
  input  logic [1:0]  state1_i[3:0],   // Actual state per line from cache 1
  input  logic        valid1_i[3:0],

  // Control & status
  input  logic        coh_enable,       // Enable coherence (from MMIO)
  output logic        inv_fire,         // Pulse when invalidation dispatched (for counters)
  output logic [15:0] coh_status        // Mirror snapshot for MMIO (8×2-bit)
);

  // ==================== Coherence State Encoding ====================
  localparam logic [1:0] I = 2'b00;
  localparam logic [1:0] S = 2'b01;
  localparam logic [1:0] M = 2'b10;

  // ==================== 8-Entry Mirror (4 lines × 2 cores) ====================
  logic [1:0] mirror[2][3:0];  // mirror[core][line] = I/S/M state

  // ==================== FSM ====================
  typedef enum logic [1:0] {
    COH_IDLE         = 2'd0,
    PROCESS_WRITE    = 2'd1,
    INVALIDATE_OTHER = 2'd2,
    WAIT_INV_ACK     = 2'd3   // Safe-default fallback; logic merged into INVALIDATE_OTHER
  } coh_state_t;

  coh_state_t coh_state, coh_state_next;

  // ==================== _d/_q Register Pairs (BUG-001/004 fix) ====================
  // Registered values (_q = flip-flop output, stable for combinational reads)
  logic        proc_core_q;    // 0 or 1 – which core is currently being processed
  logic [1:0]  proc_idx_q;     // Cache line index of the write being processed

  // Combinational next-values (_d = flip-flop input, computed in always_comb)
  logic        proc_core_d;
  logic [1:0]  proc_idx_d;

  // Round-robin arbitration register (BUG-006 fix)
  // 0 = core 0 was last granted coh_accept; 1 = core 1 was last granted
  logic        last_served;

  // ==================== Dispatch Decision Logic ====================
  // All combinational reads use _q values – no write–read hazard (BUG-004 fix)
  logic        inv_target;           // Core to invalidate = ~proc_core_q
  logic        remote_has_copy;
  logic        remote_mirror_is_not_i;
  logic        remote_actual_is_not_i;

  always_comb begin
    // inv_target derived purely from registered proc_core_q (BUG-004)
    inv_target = ~proc_core_q;

    remote_mirror_is_not_i = (mirror[inv_target][proc_idx_q] != I);
    remote_actual_is_not_i = (valid1_i[proc_idx_q] && (state1_i[proc_idx_q] != I)) ||
                              (valid0_i[proc_idx_q] && (state0_i[proc_idx_q] != I));

    remote_has_copy = remote_mirror_is_not_i || remote_actual_is_not_i;
  end

  // ==================== Next-Value Logic for proc_core_d / proc_idx_d ====================
  // BUG-001: _d signals computed here; _q signals NEVER assigned here (only in always_ff)
  // BUG-006: Round-robin tiebreaker for simultaneous notifies
  always_comb begin
    // Default: hold registered values
    proc_core_d = proc_core_q;
    proc_idx_d  = proc_idx_q;

    if (coh_state == COH_IDLE) begin
      if (write_notify0 && write_notify1) begin
        // Simultaneous notifies – use last_served for round-robin fairness (BUG-006)
        if (last_served == 1'b0) begin
          // Core 0 was last served → grant core 1 this time
          proc_core_d = 1'b1;
          proc_idx_d  = write_addr1[3:2];   // Direct bit extraction (BUG-001)
        end else begin
          // Core 1 was last served → grant core 0 this time
          proc_core_d = 1'b0;
          proc_idx_d  = write_addr0[3:2];   // Direct bit extraction (BUG-001)
        end
      end else if (write_notify0) begin
        proc_core_d = 1'b0;
        proc_idx_d  = write_addr0[3:2];     // Direct bit extraction, no boolean (BUG-001)
      end else if (write_notify1) begin
        proc_core_d = 1'b1;
        proc_idx_d  = write_addr1[3:2];     // Direct bit extraction (BUG-001)
      end
    end
  end

  // ==================== FSM Transition & Output Logic ====================
  always_comb begin
    // Default outputs
    coh_state_next = coh_state;
    coh_accept0    = 1'b0;
    coh_accept1    = 1'b0;
    inv_valid0     = 1'b0;
    inv_valid1     = 1'b0;
    inv_idx0       = 2'b0;
    inv_idx1       = 2'b0;
    inv_fire       = 1'b0;

    case (coh_state)

      COH_IDLE: begin
        if (write_notify0 && write_notify1) begin
          // Simultaneous notifies: grant one, back-pressure the other (BUG-005/006)
          if (last_served == 1'b0) begin
            // Grant core 1 (core 0 was last)
            coh_accept1    = 1'b1;
            coh_state_next = PROCESS_WRITE;
          end else begin
            // Grant core 0 (core 1 was last)
            coh_accept0    = 1'b1;
            coh_state_next = PROCESS_WRITE;
          end
          // Non-granted core: coh_accept stays 0 → back-pressure (BUG-005)
        end else if (write_notify0) begin
          coh_accept0    = 1'b1;
          coh_state_next = PROCESS_WRITE;
        end else if (write_notify1) begin
          coh_accept1    = 1'b1;
          coh_state_next = PROCESS_WRITE;
        end
      end

      PROCESS_WRITE: begin
        // Uses registered proc_core_q / proc_idx_q (stable _q values)
        if (remote_has_copy && coh_enable) begin
          coh_state_next = INVALIDATE_OTHER;
        end else begin
          coh_state_next = COH_IDLE;
        end
      end

      INVALIDATE_OTHER: begin
        // BUG-005 fix: hold inv_valid every cycle here until ack is received.
        // Previously the FSM moved to WAIT_INV_ACK after one cycle, dropping
        // inv_valid for a cycle. Now the ack check is done here directly.
        if (proc_core_q == 1'b0) begin
          inv_valid1 = 1'b1;
          inv_idx1   = proc_idx_q;
          if (inv_ack1) begin
            inv_fire       = 1'b1;   // Pulse for counter
            coh_state_next = COH_IDLE;
          end
          // else: stay in INVALIDATE_OTHER, inv_valid1 remains asserted
        end else begin
          inv_valid0 = 1'b1;
          inv_idx0   = proc_idx_q;
          if (inv_ack0) begin
            inv_fire       = 1'b1;
            coh_state_next = COH_IDLE;
          end
        end
      end

      WAIT_INV_ACK: begin
        // Safe-default fallback. Any simulation that landed here from old code
        // will safely return to IDLE. Normal flow no longer reaches this state.
        coh_state_next = COH_IDLE;
      end

      default: begin
        coh_state_next = COH_IDLE;
      end

    endcase
  end

  // ==================== Registered State Update ====================
  // BUG-001/004: _q signals ONLY updated here. No direct assignment of proc_core/proc_idx
  //             anywhere in always_comb. Single driver per signal.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      coh_state   <= COH_IDLE;
      proc_core_q <= 1'b0;
      proc_idx_q  <= 2'b0;
      last_served <= 1'b0;

      // Reset all cache lines to I
      for (int c = 0; c < 2; c++) begin
        for (int l = 0; l < 4; l++) begin
          mirror[c][l] <= I;
        end
      end
    end else begin
      coh_state <= coh_state_next;

      // Latch _d next-values into _q registers (BUG-001)
      proc_core_q <= proc_core_d;
      proc_idx_q  <= proc_idx_d;

      // Update round-robin last_served when a core is accepted (BUG-006)
      if (coh_state == COH_IDLE) begin
        if (coh_accept0) last_served <= 1'b0;
        if (coh_accept1) last_served <= 1'b1;
      end

      // ==================== Mirror Updates ====================

      // M-update: writing core's line → M on the transition cycle (BUG-005 timing fix)
      // Use proc_core_d/proc_idx_d (the values being latched this cycle) so the mirror
      // is correct on the very first cycle of PROCESS_WRITE.
      if (coh_state == COH_IDLE && coh_state_next == PROCESS_WRITE) begin
        mirror[proc_core_d][proc_idx_d] <= M;
      end

      // I-update: remote line → I when invalidation completes
      if (coh_state == INVALIDATE_OTHER && coh_state_next == COH_IDLE) begin
        mirror[~proc_core_q][proc_idx_q] <= I;
      end

      // R2: fill_notify updates mirror to S regardless of FSM state
      if (fill_notify0) begin
        mirror[1'b0][fill_idx0] <= S;
      end
      if (fill_notify1) begin
        mirror[1'b1][fill_idx1] <= S;
      end
    end
  end

  // ==================== Export Mirror as Status ====================
  // Pack 8 × 2-bit states into 16-bit word for MMIO read
  assign coh_status = {mirror[1][3], mirror[1][2], mirror[1][1], mirror[1][0],
                       mirror[0][3], mirror[0][2], mirror[0][1], mirror[0][0]};

endmodule
