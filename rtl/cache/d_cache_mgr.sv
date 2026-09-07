/**
 * @file d_cache_mgr.sv
 * @brief D-Cache Manager FSM (13-state)
 * @project Dual-Core RV32I SoC with Coherent Memory Subsystem
 * @doc_ref logic_design/04_dcache_fsm.md §4.4
 * @date Day 2, Task T2.5
 *
 * FIXES APPLIED (Second Draft):
 *  BUG-003a: Removed illegal non-blocking assignment (<=) for fill_data_q inside
 *            always_comb (AXI_R state). fill_data_q is now captured exclusively in
 *            always_ff when (state == AXI_R && m_rvalid). FILL state reads fill_data_q
 *            (latched value from prior cycle) instead of m_rdata directly.
 *  BUG-003b: Removed notify_pending assignment from always_comb (NOTIFY_COH state).
 *            notify_pending is now driven exclusively from always_ff, eliminating the
 *            multi-driver conflict between the combinational and sequential always blocks.
 *
 * 13-state FSM managing cache operations:
 *  - Hit detection
 *  - Load/store miss handling (AXI4-Lite sequencing)
 *  - Write-through to shared SRAM
 *  - Coherence notification (R1: hold+escape pattern)
 *  - Invalidation servicing (R1 escape rule)
 *  - Uncached bypass (R9)
 *
 * States (per doc 04 §4.4):
 *  0: IDLE
 *  1: CHECK
 *  2: HIT_READ
 *  3: HIT_WRITE
 *  4: MISS_READ
 *  5: AXI_AR
 *  6: AXI_R
 *  7: FILL
 *  8: AXI_AW
 *  9: AXI_W
 * 10: AXI_B
 * 11: NOTIFY_COH
 * 12: WAIT_INVALIDATE
 */

module d_cache_mgr #(
  parameter int CORE_ID = 0         // 0 or 1
) (
  input  logic        clk,
  input  logic        rst_n,

  // From core
  input  logic        dmem_req,         // Data memory request
  input  logic        dmem_we,          // Write enable (1=store, 0=load)
  input  logic [31:0] dmem_addr,        // Request address
  input  logic [31:0] dmem_wdata,       // Write data
  input  logic [3:0]  dmem_wmask,       // Byte mask
  output logic [31:0] dmem_rdata,       // Read data
  output logic        dmem_ack,         // Acknowledge
  output logic        dmem_err,         // Error

  // Cache storage interface
  input  logic        cache_hit,
  input  logic        cache_miss,
  input  logic [1:0]  cache_hit_idx,
  input  logic [31:0] cache_hit_data,
  output logic [1:0]  cache_wr_idx,
  output logic [31:0] cache_wr_data,
  output logic [27:0] cache_wr_tag,
  output logic [1:0]  cache_wr_state,
  output logic        cache_wr_valid,
  output logic [3:0]  cache_wr_we,      // 1-hot write enable

  // Coherence sideband (R1, R2, R6)
  output logic        coh_write_notify,
  output logic [31:0] coh_write_addr,
  input  logic        coh_accept,       // (1-cycle pulse, R1)
  output logic        coh_fill_notify,
  output logic [1:0]  coh_fill_idx,
  input  logic        coh_inv_valid,
  input  logic [1:0]  coh_inv_idx,
  output logic        coh_inv_ack,

  // AXI4-Lite master interface
  output logic        m_awvalid,
  output logic [31:0] m_awaddr,
  input  logic        m_awready,
  output logic        m_wvalid,
  output logic [31:0] m_wdata,
  output logic [3:0]  m_wstrb,
  input  logic        m_wready,
  input  logic        m_bvalid,
  input  logic [1:0]  m_bresp,
  output logic        m_bready,
  output logic        m_arvalid,
  output logic [31:0] m_araddr,
  input  logic        m_arready,
  input  logic        m_rvalid,
  input  logic [31:0] m_rdata,
  input  logic [1:0]  m_rresp,
  output logic        m_rready,

  // Bus request (for arbiter)
  output logic        bus_req,

  // Event outputs (for counters/LEDs)
  output logic        hit_event,
  output logic        miss_event,
  output logic        err_event
);

  // ==================== State Machine ====================
  typedef enum logic [3:0] {
    IDLE            = 4'd0,
    CHECK           = 4'd1,
    HIT_READ        = 4'd2,
    HIT_WRITE       = 4'd3,
    MISS_READ       = 4'd4,
    AXI_AR          = 4'd5,
    AXI_R           = 4'd6,
    FILL            = 4'd7,
    AXI_AW          = 4'd8,
    AXI_W           = 4'd9,
    AXI_B           = 4'd10,
    NOTIFY_COH      = 4'd11,
    WAIT_INVALIDATE = 4'd12
  } state_t;

  state_t state, state_next;

  // ==================== Registers ====================
  logic [31:0] addr_q;          // Latched address
  logic [31:0] wdata_q;         // Latched write data
  logic [3:0]  wmask_q;         // Latched write mask
  logic        we_q;            // Latched write enable
  logic        is_write_q;      // Is this a store?
  logic        pending_store;   // Store waiting for data (R3)
  logic        uncached;        // Uncached address (R9)
  logic [31:0] fill_data_q;     // Data captured from AXI read (BUG-003a: only in always_ff)
  logic [1:0]  fill_idx_q;      // Index of line to fill
  logic [27:0] fill_tag_q;      // Tag of line to fill
  // BUG-003b: notify_pending driven ONLY from always_ff (no always_comb driver)
  logic        notify_pending;  // Write notify held (R1)

  // ==================== Address Decode & Uncached Bypass (R9) ====================
  logic uncached_addr;
  assign uncached_addr = (dmem_addr[31:12] != 20'h00000);

  // ==================== FSM Transition & Output Logic ====================
  always_comb begin
    // Default outputs
    state_next           = state;
    dmem_rdata           = 32'b0;
    dmem_ack             = 1'b0;
    dmem_err             = 1'b0;

    m_awvalid            = 1'b0;
    m_awaddr             = 32'b0;
    m_wvalid             = 1'b0;
    m_wdata              = 32'b0;
    m_wstrb              = 4'b0;
    m_bready             = 1'b0;
    m_arvalid            = 1'b0;
    m_araddr             = 32'b0;
    m_rready             = 1'b0;
    bus_req              = 1'b0;

    coh_write_notify     = 1'b0;
    coh_write_addr       = 32'b0;
    coh_fill_notify      = 1'b0;
    coh_fill_idx         = 2'b0;
    coh_inv_ack          = 1'b0;

    cache_wr_idx         = 2'b0;
    cache_wr_data        = 32'b0;
    cache_wr_tag         = 28'b0;
    cache_wr_state       = 2'b0;
    cache_wr_valid       = 1'b0;
    cache_wr_we          = 4'b0;

    hit_event            = 1'b0;
    miss_event           = 1'b0;
    err_event            = 1'b0;

    case (state)

      IDLE: begin
        if (dmem_req) begin
          state_next = CHECK;
        end
      end

      CHECK: begin
        if (cache_hit && !dmem_we) begin
          state_next = HIT_READ;
        end else if (cache_hit && dmem_we) begin
          state_next = HIT_WRITE;
        end else begin
          state_next = MISS_READ;
        end
      end

      HIT_READ: begin
        dmem_rdata = cache_hit_data;
        dmem_ack   = 1'b1;
        hit_event  = 1'b1;
        state_next = IDLE;
      end

      HIT_WRITE: begin
        cache_wr_idx                = cache_hit_idx;
        cache_wr_data               = merge_bytes(cache_hit_data, dmem_wdata, dmem_wmask);
        cache_wr_tag                = dmem_addr[31:4];
        cache_wr_state              = 2'b10;  // M
        cache_wr_valid              = 1'b1;
        cache_wr_we[cache_hit_idx]  = 1'b1;
        state_next                  = AXI_AW;
      end

      MISS_READ: begin
        bus_req    = 1'b1;
        miss_event = 1'b1;
        state_next = AXI_AR;
      end

      AXI_AR: begin
        m_arvalid  = 1'b1;
        m_araddr   = addr_q;
        bus_req    = 1'b1;
        if (m_arready) begin
          state_next = AXI_R;
        end
      end

      AXI_R: begin
        // BUG-003a fix: NO non-blocking assignment here.
        // fill_data_q is captured in always_ff when (state==AXI_R && m_rvalid).
        m_rready = 1'b1;
        if (m_rvalid) begin
          state_next = FILL;
        end
      end

      FILL: begin
        // BUG-003a fix: use fill_data_q (registered from prior AXI_R cycle),
        // not m_rdata directly, for the cache write data.
        if (!uncached) begin
          if (pending_store) begin
            cache_wr_data  = merge_bytes(fill_data_q, wdata_q, wmask_q);
            cache_wr_state = 2'b10;  // M (store miss)
          end else begin
            cache_wr_data  = fill_data_q;
            cache_wr_state = 2'b01;  // S (load miss)
          end

          cache_wr_idx                    = dmem_addr[3:2];
          cache_wr_tag                    = dmem_addr[31:4];
          cache_wr_valid                  = 1'b1;
          cache_wr_we[dmem_addr[3:2]]     = 1'b1;
          coh_fill_notify                 = 1'b1;
          coh_fill_idx                    = dmem_addr[3:2];
        end

        state_next = AXI_AW;
      end

      AXI_AW: begin
        m_awvalid  = 1'b1;
        m_awaddr   = addr_q;
        bus_req    = 1'b1;
        if (m_awready) begin
          state_next = AXI_W;
        end
      end

      AXI_W: begin
        m_wvalid   = 1'b1;
        m_wdata    = wdata_q;
        m_wstrb    = wmask_q;
        bus_req    = 1'b1;
        if (m_wready) begin
          state_next = AXI_B;
        end
      end

      AXI_B: begin
        m_bready = 1'b1;
        if (m_bvalid) begin
          if (m_bresp == 2'b00) begin
            state_next = NOTIFY_COH;
          end else begin
            dmem_err   = 1'b1;
            dmem_ack   = 1'b1;
            err_event  = 1'b1;
            state_next = IDLE;
          end
        end
      end

      NOTIFY_COH: begin
        // BUG-003b fix: notify_pending is NOT assigned here (removed combinational driver).
        // It is managed exclusively in always_ff.
        coh_write_notify = 1'b1;
        coh_write_addr   = addr_q;

        if (coh_inv_valid) begin
          // Invalidation arrived while notifying (R1 escape)
          state_next = WAIT_INVALIDATE;
        end else if (coh_accept) begin
          dmem_ack   = 1'b1;
          state_next = IDLE;
        end
        // else: hold – state_next defaults to state (NOTIFY_COH)
      end

      WAIT_INVALIDATE: begin
        // Service invalidation while holding notify (R1 escape rule)
        coh_inv_ack = 1'b1;
        if (!coh_inv_valid) begin
          state_next = NOTIFY_COH;
        end
        // else: hold
      end

      default: begin
        state_next = IDLE;
      end

    endcase
  end

  // ==================== Registered State Update ====================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state          <= IDLE;
      addr_q         <= 32'b0;
      wdata_q        <= 32'b0;
      wmask_q        <= 4'b0;
      we_q           <= 1'b0;
      pending_store  <= 1'b0;
      uncached       <= 1'b0;
      fill_data_q    <= 32'b0;
      fill_idx_q     <= 2'b0;
      fill_tag_q     <= 28'b0;
      notify_pending <= 1'b0;
    end else begin
      state <= state_next;

      // Latch core request on IDLE→CHECK transition
      if (dmem_req && state == IDLE) begin
        addr_q  <= dmem_addr;
        wdata_q <= dmem_wdata;
        wmask_q <= dmem_wmask;
        we_q    <= dmem_we;
        uncached <= uncached_addr;
      end

      // Track if store is waiting for load data (R3)
      if (state == MISS_READ) begin
        pending_store <= dmem_we;
      end else if (state == FILL) begin
        pending_store <= 1'b0;
      end

      // BUG-003a fix: capture AXI read data in sequential block only.
      // Previously this was a non-blocking assignment inside always_comb (illegal).
      if (state == AXI_R && m_rvalid) begin
        fill_data_q <= m_rdata;
      end

      // BUG-003b fix: notify_pending has a single driver here in always_ff.
      // Previously it was also driven from always_comb (multi-driver conflict).
      if (state == NOTIFY_COH) begin
        notify_pending <= 1'b1;
      end else if (state == IDLE || (state == NOTIFY_COH && coh_accept)) begin
        notify_pending <= 1'b0;
      end
    end
  end

  // ==================== Helper Functions ====================
  function logic [31:0] merge_bytes (
    logic [31:0] old_data,
    logic [31:0] new_data,
    logic [3:0]  mask
  );
    logic [31:0] result;
    for (int i = 0; i < 4; i++) begin
      if (mask[i]) begin
        result[i*8 +: 8] = new_data[i*8 +: 8];
      end else begin
        result[i*8 +: 8] = old_data[i*8 +: 8];
      end
    end
    return result;
  endfunction

endmodule
