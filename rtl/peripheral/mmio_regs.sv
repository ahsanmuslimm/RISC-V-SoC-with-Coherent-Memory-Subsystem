/**
 * @module mmio_regs.sv
 * @brief MMIO Registers (T2.11)
 *
 * Source: logic_design/09_peripherals.md §9.1
 *
 * Purpose: Expose system counters, status, control, and doorbell register.
 * Base address: 0x0001_0000
 *
 * Register Map:
 *   0x00  COH_STATUS     RO   Coherence mirror state (8×2-bit = 16 bits in 32-bit word)
 *   0x04  INV_COUNT      RO   Invalidation counter
 *   0x08  HIT_COUNT      RO   D-cache hit counter
 *   0x0C  MISS_COUNT     RO   D-cache miss counter
 *   0x10  DOORBELL       RW   Core-to-core doorbell value
 *   0x14  CONTROL        RW   Control bits: bit0=coh_enable, bit1=cnt_clear, bit2=err_clear
 *         ERR_STICKY     RO   Sticky error bit (can use top bit of COH_STATUS or separate)
 *
 * Counters: Increment on: hit0|hit1, miss0|miss1, inv_fire
 * cnt_clear pulse: Sets all counters to 0 (takes priority)
 * coh_enable: Default 1; controls whether coherence dispatch is active
 */

module mmio_regs (
    input  logic        clk,
    input  logic        rst_n,
    
    // AXI4-Lite Slave Interface
    input  logic        awvalid,
    input  logic [31:0] awaddr,
    output logic        awready,
    input  logic        wvalid,
    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,
    output logic        wready,
    output logic        bvalid,
    output logic [1:0]  bresp,
    input  logic        bready,
    input  logic        arvalid,
    input  logic [31:0] araddr,
    output logic        arready,
    output logic        rvalid,
    output logic [31:0] rdata,
    output logic [1:0]  rresp,
    input  logic        rready,
    
    // Event inputs (from cache/coherence)
    input  logic        hit0,
    input  logic        hit1,
    input  logic        miss0,
    input  logic        miss1,
    input  logic        err0,
    input  logic        err1,
    input  logic        inv_fire,
    
    // Coherence status input
    input  logic [15:0] coh_status,
    
    // Control outputs
    output logic        coh_enable,
    output logic        err_sticky,
    
    // Doorbell register (readable by both cores)
    output logic [31:0] doorbell
);

    // Register offsets (from doc 09 §9.1)
    localparam OFFSET_COH_STATUS = 8'h00;
    localparam OFFSET_INV_COUNT  = 8'h04;
    localparam OFFSET_HIT_COUNT  = 8'h08;
    localparam OFFSET_MISS_COUNT = 8'h0C;
    localparam OFFSET_DOORBELL   = 8'h10;
    localparam OFFSET_CONTROL    = 8'h14;
    
    // Internal registers
    logic [31:0] inv_count_d, inv_count_q;
    logic [31:0] hit_count_d, hit_count_q;
    logic [31:0] miss_count_d, miss_count_q;
    logic [31:0] doorbell_d, doorbell_q;
    logic coh_enable_d, coh_enable_q;
    logic err_sticky_d, err_sticky_q;
    
    // Capture control signals for next cycle (from CONTROL register writes)
    logic cnt_clear;
    logic err_clear;
    
    // Extract register offset from address
    logic [7:0] offset_aw, offset_ar;
    assign offset_aw = awaddr[7:0];
    assign offset_ar = araddr[7:0];
    
    // =====================================================================
    // AXI4-Lite WRITE PATH (always ready per template, doc 07 §7.5)
    // =====================================================================
    
    assign awready = 1'b1;
    assign wready  = 1'b1;
    
    // Write response: always ready, issue B next cycle if both AW+W accepted
    logic write_txn;
    logic bresp_valid_d, bresp_valid_q;
    
    assign write_txn = awvalid && awready && wvalid && wready;
    
    // Mux control signals from CONTROL register write
    always_comb begin
        cnt_clear = 1'b0;
        err_clear = 1'b0;
        
        if (write_txn && (offset_aw[7:0] == OFFSET_CONTROL)) begin
            cnt_clear = wdata[1];  // bit1 write-1-pulse
            err_clear = wdata[2];  // bit2 write-1-pulse
        end
    end
    
    // =====================================================================
    // COUNTER UPDATE LOGIC (Synchronous, doc 09 §9.1)
    // =====================================================================
    // Counters increment on event OR when write_txn to their register.
    // cnt_clear takes priority.
    
    always_comb begin
        // INV_COUNT: increment on inv_fire pulse
        if (cnt_clear)
            inv_count_d = 32'h0;
        else if (inv_fire)
            inv_count_d = inv_count_q + 32'h1;
        else
            inv_count_d = inv_count_q;
        
        // HIT_COUNT: increment on hit0 | hit1
        if (cnt_clear)
            hit_count_d = 32'h0;
        else if (hit0 | hit1)
            hit_count_d = hit_count_q + 32'h1;
        else
            hit_count_d = hit_count_q;
        
        // MISS_COUNT: increment on miss0 | miss1
        if (cnt_clear)
            miss_count_d = 32'h0;
        else if (miss0 | miss1)
            miss_count_d = miss_count_q + 32'h1;
        else
            miss_count_d = miss_count_q;
    end
    
    // =====================================================================
    // CONTROL REGISTER UPDATE (coh_enable, bit0)
    // =====================================================================
    // coh_enable resets to 1; a write of CONTROL replaces bit0.
    
    always_comb begin
        if (write_txn && (offset_aw[7:0] == OFFSET_CONTROL)) begin
            coh_enable_d = wdata[0];
        end else begin
            coh_enable_d = coh_enable_q;
        end
    end
    
    // =====================================================================
    // ERROR STICKY REGISTER UPDATE (R5/O3)
    // =====================================================================
    // Set by err0|err1, cleared by err_clear pulse.
    
    always_comb begin
        if (err_clear)
            err_sticky_d = 1'b0;
        else if (err0 | err1)
            err_sticky_d = 1'b1;
        else
            err_sticky_d = err_sticky_q;
    end
    
    // =====================================================================
    // DOORBELL REGISTER UPDATE (RW, Software Protocol)
    // =====================================================================
    // Plain RW: core 0 writes nonzero token, core 1 reads and acknowledges with 0.
    
    always_comb begin
        if (write_txn && (offset_aw[7:0] == OFFSET_DOORBELL)) begin
            doorbell_d = wdata;
        end else begin
            doorbell_d = doorbell_q;
        end
    end
    
    // =====================================================================
    // AXI4-Lite READ PATH (doc 07 §7.5 template)
    // =====================================================================
    // All reads are combinational mux → rdata registered next cycle.
    // arready=1 always; next cycle rvalid=1 for 1 cycle.
    
    assign arready = 1'b1;
    
    logic [31:0] rdata_comb;
    
    always_comb begin
        // Mux based on offset
        unique case (offset_ar[7:0])
            OFFSET_COH_STATUS: rdata_comb = {16'b0, coh_status};
            OFFSET_INV_COUNT:  rdata_comb = inv_count_q;
            OFFSET_HIT_COUNT:  rdata_comb = hit_count_q;
            OFFSET_MISS_COUNT: rdata_comb = miss_count_q;
            OFFSET_DOORBELL:   rdata_comb = doorbell_q;
            OFFSET_CONTROL:    rdata_comb = {29'b0, err_sticky_q, coh_enable_q, 1'b0};
            default:           rdata_comb = 32'h0;
        endcase
    end
    
    // Register read response (template: 1-cycle latency)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid <= 1'b0;
            rdata  <= 32'h0;
        end else begin
            if (arvalid && arready) begin
                rvalid <= 1'b1;
                rdata  <= rdata_comb;
            end else if (rvalid && rready) begin
                rvalid <= 1'b0;
            end
        end
    end
    
    assign rresp = 2'b00;  // OKAY
    
    // =====================================================================
    // WRITE RESPONSE (B channel, doc 07 §7.5 template)
    // =====================================================================
    // Issue bvalid next cycle after write_txn; hold until bready.
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bresp_valid_q <= 1'b0;
        end else begin
            if (bresp_valid_q && bready) begin
                bresp_valid_q <= 1'b0;
            end else if (write_txn && !bresp_valid_q) begin
                bresp_valid_q <= 1'b1;
            end
        end
    end
    
    assign bvalid = bresp_valid_q;
    assign bresp  = 2'b00;  // OKAY
    
    // =====================================================================
    // SEQUENTIAL LOGIC (All registers)
    // =====================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inv_count_q   <= 32'h0;
            hit_count_q   <= 32'h0;
            miss_count_q  <= 32'h0;
            doorbell_q    <= 32'h0;
            coh_enable_q  <= 1'b1;      // Reset to 1 (doc 09 §9.5)
            err_sticky_q  <= 1'b0;
        end else begin
            inv_count_q   <= inv_count_d;
            hit_count_q   <= hit_count_d;
            miss_count_q  <= miss_count_d;
            doorbell_q    <= doorbell_d;
            coh_enable_q  <= coh_enable_d;
            err_sticky_q  <= err_sticky_d;
        end
    end
    
    // =====================================================================
    // OUTPUT ASSIGNMENTS
    // =====================================================================
    
    assign coh_enable  = coh_enable_q;
    assign err_sticky  = err_sticky_q;
    assign doorbell    = doorbell_q;

endmodule : mmio_regs
