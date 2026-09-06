/**
 * @file coherence_ctrl.sv
 * @brief Coherence Controller FSM (4-state, I/S/M invalidation protocol)
 * @project Dual-Core RV32I SoC with Coherent Memory Subsystem
 * @doc_ref logic_design/05_coherence_fsm.md §5.4–5.6
 * @date Day 2, Task T2.7
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
 *  3: WAIT_INV_ACK
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
    COH_IDLE           = 2'd0,
    PROCESS_WRITE      = 2'd1,
    INVALIDATE_OTHER   = 2'd2,
    WAIT_INV_ACK       = 2'd3
  } coh_state_t;

  coh_state_t coh_state, coh_state_next;

  // ==================== Write Processing (Registered) ====================
  logic        proc_core;        // 0 or 1 (which core just wrote)
  logic [1:0]  proc_idx;         // Line index
  logic        inv_target;       // 0 or 1 (which core to invalidate)

  // ==================== Dispatch Decision Logic ====================
  logic remote_has_copy;
  logic remote_mirror_is_not_i;
  logic remote_actual_is_not_i;

  always_comb begin
    // Extract line index from write address
    proc_idx = write_addr0[3:2] ? 2'b0 : write_addr1[3:2];  // Will be set by FSM
    
    // Determine if remote core has a cached copy (R6: check both mirror AND actual)
    inv_target = ~proc_core;  // 0 if proc_core==1, 1 if proc_core==0
    
    remote_mirror_is_not_i = (mirror[inv_target][proc_idx] != I);
    remote_actual_is_not_i = (valid1_i[proc_idx] && (state1_i[proc_idx] != I)) ||
                              (valid0_i[proc_idx] && (state0_i[proc_idx] != I));
    
    remote_has_copy = remote_mirror_is_not_i || remote_actual_is_not_i;
  end

  // ==================== FSM Transition & Output Logic ====================

  always_comb begin
    // Default outputs
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
        // Wait for write notify from either core (priority: core 0 first)
        if (write_notify0) begin
          coh_accept0    = 1'b1;  // Pulse
          coh_state_next = PROCESS_WRITE;
          proc_core      = 1'b0;  // Will be latched
          proc_idx       = write_addr0[3:2];  // Will be latched
        end else if (write_notify1) begin
          coh_accept1    = 1'b1;  // Pulse
          coh_state_next = PROCESS_WRITE;
          proc_core      = 1'b1;  // Will be latched
          proc_idx       = write_addr1[3:2];  // Will be latched
        end
      end

      PROCESS_WRITE: begin
        // Update mirror to M for writing core
        // Decide: dispatch invalidation or return to IDLE
        
        if (remote_has_copy && coh_enable) begin
          // Remote has copy: dispatch invalidation
          coh_state_next = INVALIDATE_OTHER;
        end else begin
          // Remote doesn't have copy: no need to invalidate
          coh_state_next = COH_IDLE;
        end
      end

      INVALIDATE_OTHER: begin
        // Send invalidation, then wait for ack
        if (proc_core == 1'b0) begin
          inv_valid1    = 1'b1;
          inv_idx1      = proc_idx;
        end else begin
          inv_valid0    = 1'b1;
          inv_idx0      = proc_idx;
        end
        inv_fire       = 1'b1;  // Pulse for counter
        coh_state_next = WAIT_INV_ACK;
      end

      WAIT_INV_ACK: begin
        // Hold invalidation until ack (per doc 05 §5.4)
        if (proc_core == 1'b0) begin
          inv_valid1   = 1'b1;
          inv_idx1     = proc_idx;
          if (inv_ack1) begin
            coh_state_next = COH_IDLE;
          end else begin
            coh_state_next = WAIT_INV_ACK;  // Hold
          end
        end else begin
          inv_valid0   = 1'b1;
          inv_idx0     = proc_idx;
          if (inv_ack0) begin
            coh_state_next = COH_IDLE;
          end else begin
            coh_state_next = WAIT_INV_ACK;  // Hold
          end
        end
      end

      default: begin
        coh_state_next = COH_IDLE;
      end

    endcase
  end

  // ==================== Registered State Update ====================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      coh_state <= COH_IDLE;
      proc_core <= 1'b0;
      proc_idx  <= 2'b0;
      inv_target <= 1'b0;
      
      // Reset all cache lines to I
      for (int c = 0; c < 2; c++) begin
        for (int l = 0; l < 4; l++) begin
          mirror[c][l] <= I;
        end
      end
    end else begin
      coh_state <= coh_state_next;
      
      // Latch write info on IDLE→PROCESS_WRITE
      if (coh_state == COH_IDLE) begin
        if (write_notify0) begin
          proc_core <= 1'b0;
          proc_idx <= write_addr0[3:2];
          inv_target <= 1'b1;
        end else if (write_notify1) begin
          proc_core <= 1'b1;
          proc_idx <= write_addr1[3:2];
          inv_target <= 1'b0;
        end
      end
      
      // ==================== Mirror Updates ====================
      
      // Update on write_notify (PROCESS_WRITE entry)
      if (coh_state_next == PROCESS_WRITE) begin
        mirror[proc_core][proc_idx] <= M;
      end
      
      // Update on invalidation ack (WAIT_INV_ACK→IDLE)
      if (coh_state == WAIT_INV_ACK && coh_state_next == COH_IDLE) begin
        mirror[inv_target][proc_idx] <= I;
      end
      
      // Update on fill_notify (R2 - independent of FSM state)
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
