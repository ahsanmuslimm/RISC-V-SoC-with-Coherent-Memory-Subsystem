/**
 * @file riscv_soc_if.sv
 * @brief Virtual Interface for RISC-V SoC Verification (Day 4 T4.2)
 *
 * Purpose: Define virtual interface for monitoring and stimulus generation
 * in UVM testbench. Provides access to DUT signals and helper functions.
 *
 * Signal Groups:
 *   1. Clock/Reset: clk, rst_n
 *   2. Core domain (per-core): request, write, address, data, response
 *   3. Coherence sideband: write_notify, fill_notify, inv_valid, inv_ack
 *   4. AXI fabric: arbiter outputs, decoder inputs, slave responses
 *   5. MMIO status: hit/miss counters, coherence state
 *   6. Peripherals: UART TX/RX, GPIO LED
 *
 * Monitoring Functions:
 *   - monitor_mem_txn(): Capture memory access transaction
 *   - monitor_coh_event(): Capture coherence protocol event
 *   - Helper: get_coh_state(), is_line_valid()
 */

interface riscv_soc_if (
    input logic clk,
    input logic rst_n
);

    // =====================================================================
    // CLOCK & RESET
    // =====================================================================
    logic        clk;
    logic        rst_n;

    // =====================================================================
    // CORE DOMAIN SIGNALS (FROM riscv_soc_top PORT LIST)
    // =====================================================================

    // Core 0 memory interface (L1 D-cache → arbiter)
    logic        c0_dmem_req;
    logic        c0_dmem_we;
    logic [31:0] c0_dmem_addr;
    logic [31:0] c0_dmem_wdata;
    logic [3:0]  c0_dmem_wmask;
    logic [31:0] c0_dmem_rdata;
    logic        c0_dmem_ack;
    logic        c0_dmem_err;

    // Core 1 memory interface
    logic        c1_dmem_req;
    logic        c1_dmem_we;
    logic [31:0] c1_dmem_addr;
    logic [31:0] c1_dmem_wdata;
    logic [3:0]  c1_dmem_wmask;
    logic [31:0] c1_dmem_rdata;
    logic        c1_dmem_ack;
    logic        c1_dmem_err;

    // =====================================================================
    // COHERENCE SIDEBAND SIGNALS
    // =====================================================================

    // From coherence controller to cache managers
    logic        write_notify;     // Write notification to other core
    logic        fill_notify;      // Cache fill notification
    logic        inv_valid;        // Line invalidation
    logic        inv_ack;          // Invalidation acknowledged
    logic [1:0]  coh_state;        // Current coherence state (I/S/M)

    // =====================================================================
    // AXI FABRIC SIGNALS (FOR MONITORING)
    // =====================================================================

    // Master ports from cache managers
    logic        m0_awvalid, m0_awready;
    logic [31:0] m0_awaddr;
    logic        m0_wvalid, m0_wready;
    logic [31:0] m0_wdata;
    logic [3:0]  m0_wstrb;
    logic        m0_bvalid, m0_bready;
    logic [1:0]  m0_bresp;
    logic        m0_arvalid, m0_arready;
    logic [31:0] m0_araddr;
    logic        m0_rvalid, m0_rready;
    logic [31:0] m0_rdata;
    logic [1:0]  m0_rresp;

    logic        m1_awvalid, m1_awready;
    logic [31:0] m1_awaddr;
    logic        m1_wvalid, m1_wready;
    logic [31:0] m1_wdata;
    logic [3:0]  m1_wstrb;
    logic        m1_bvalid, m1_bready;
    logic [1:0]  m1_bresp;
    logic        m1_arvalid, m1_arready;
    logic [31:0] m1_araddr;
    logic        m1_rvalid, m1_rready;
    logic [31:0] m1_rdata;
    logic [1:0]  m1_rresp;

    // =====================================================================
    // MMIO SIGNALS (COUNTER STATUS)
    // =====================================================================

    logic [31:0] mmio_hit_cnt;      // Hit counter value
    logic [31:0] mmio_miss_cnt;     // Miss counter value
    logic [31:0] mmio_inv_cnt;      // Invalidation counter value
    logic        hit0, miss0;        // Per-core hit/miss status
    logic        hit1, miss1;

    // =====================================================================
    // PERIPHERAL I/O
    // =====================================================================

    logic        uart_tx;           // UART transmit
    logic        uart_rx;           // UART receive
    logic [7:0]  led;               // LED outputs

    // =====================================================================
    // CLOCKING BLOCK (FOR SIMULATION TIMING)
    // =====================================================================

    clocking cb @(posedge clk);
        input  #1 rst_n;
        input  #1 c0_dmem_rdata, c0_dmem_ack, c0_dmem_err;
        input  #1 c1_dmem_rdata, c1_dmem_ack, c1_dmem_err;
        input  #1 write_notify, fill_notify, inv_valid, inv_ack;
        input  #1 mmio_hit_cnt, mmio_miss_cnt, mmio_inv_cnt;
        input  #1 uart_tx, led;
    endclocking

    // =====================================================================
    // MONITORING FUNCTIONS
    // =====================================================================

    /**
     * @function monitor_mem_txn
     * @brief Capture a memory transaction from core memory interface
     *
     * Returns: 1 if transaction occurred, 0 otherwise
     * Captures: Address, data, write/read, response (data, ACK, ERR)
     * Detects: Hit/miss from cache manager signals
     */
    function bit monitor_mem_txn(output soc_uvm_pkg::mem_txn txn);
        bit txn_valid = 1'b0;

        // Check if either core has a pending request
        if (c0_dmem_req || c1_dmem_req) begin
            txn = soc_uvm_pkg::mem_txn::type_id::create();
            
            // Determine which core has the request
            if (c0_dmem_req) begin
                txn.core_id = 0;
                txn.we = c0_dmem_we;
                txn.addr = c0_dmem_addr;
                txn.wdata = c0_dmem_wdata;
                txn.wmask = c0_dmem_wmask;
                txn.rdata = c0_dmem_rdata;
                txn.err = c0_dmem_err;
                txn.hit = hit0 && !c0_dmem_err;
                txn.miss = miss0 && !c0_dmem_err;
            end else begin
                txn.core_id = 1;
                txn.we = c1_dmem_we;
                txn.addr = c1_dmem_addr;
                txn.wdata = c1_dmem_wdata;
                txn.wmask = c1_dmem_wmask;
                txn.rdata = c1_dmem_rdata;
                txn.err = c1_dmem_err;
                txn.hit = hit1 && !c1_dmem_err;
                txn.miss = miss1 && !c1_dmem_err;
            end
            
            txn_valid = 1'b1;
        end

        return txn_valid;
    endfunction : monitor_mem_txn

    /**
     * @function monitor_coh_event
     * @brief Capture a coherence protocol event
     *
     * Returns: 1 if event occurred, 0 otherwise
     * Events: WRITE_NOTIFY, FILL_NOTIFY, INV_VALID, INV_ACK
     * Captures: Event type, address, state transitions
     */
    function bit monitor_coh_event(output soc_uvm_pkg::coh_event_txn txn);
        static bit [1:0] last_state = 2'b00;  // Track state for transitions
        bit event_occurred = 1'b0;

        txn = soc_uvm_pkg::coh_event_txn::type_id::create();

        // Detect coherence events
        if (write_notify) begin
            txn.event_type = soc_uvm_pkg::coh_event_txn::WRITE_NOTIFY;
            // TODO: Infer initiator from AXI master port activity
            txn.state_before = soc_uvm_pkg::coh_event_txn::1'b0;  // S or I
            txn.state_after = 2'b10;   // M (Modified)
            event_occurred = 1'b1;
        end else if (fill_notify) begin
            txn.event_type = soc_uvm_pkg::coh_event_txn::FILL_NOTIFY;
            txn.state_before = 2'b00;  // I
            txn.state_after = 2'b01;   // S (Shared)
            event_occurred = 1'b1;
        end else if (inv_valid) begin
            txn.event_type = soc_uvm_pkg::coh_event_txn::INV_VALID;
            txn.state_before = 2'b01;  // S
            txn.state_after = 2'b00;   // I (Invalidated)
            event_occurred = 1'b1;
        end else if (inv_ack) begin
            txn.event_type = soc_uvm_pkg::coh_event_txn::INV_ACK;
            event_occurred = 1'b1;
        end

        return event_occurred;
    endfunction : monitor_coh_event

    /**
     * @function get_coh_state
     * @brief Get coherence state of a cache line (I/S/M)
     *
     * Returns: 2'b00 (I), 2'b01 (S), 2'b10 (M), 2'b11 (reserved)
     */
    function bit [1:0] get_coh_state();
        return coh_state;
    endfunction : get_coh_state

    /**
     * @function is_line_valid
     * @brief Check if cache line is valid (not in I state)
     *
     * Returns: 1 if line is valid (S or M), 0 if invalid (I)
     */
    function bit is_line_valid();
        return (coh_state != 2'b00);  // Not I
    endfunction : is_line_valid

    /**
     * @function get_cache_hit_miss
     * @brief Get per-core cache hit/miss status
     *
     * Returns: 4'b{hit1, miss1, hit0, miss0}
     */
    function bit [3:0] get_cache_hit_miss();
        return {hit1, miss1, hit0, miss0};
    endfunction : get_cache_hit_miss

endinterface : riscv_soc_if

