/**
 * @module axi_lite_arbiter.sv
 * @brief 2-Master Round-Robin AXI4-Lite Arbiter (T2.9)
 *
 * Source: logic_design/06_arbiter_logic.md
 * 
 * Purpose: Arbitrate between two D-Cache managers for access to shared AXI4-Lite bus.
 * Implements round-robin fairness with core 0 priority at reset.
 * 
 * Arbitration Rules:
 * - req0/req1: level signals held until transaction completes
 * - grant held until (bvalid && bready) || (rvalid && rready) — end of transaction
 * - pref pointer: flips on completion, reset to 0 (core 0 wins simultaneous requests)
 *
 * Truth Table (from doc 06 §6.2):
 *   req1 req0 pref | grant1 grant0
 *   0    0    x    | 0      0      (idle)
 *   0    1    x    | 0      1      (only core 0)
 *   1    0    x    | 1      0      (only core 1)
 *   1    1    0    | 0      1      (simultaneous, pref=0 → core 0)
 *   1    1    1    | 1      0      (simultaneous, pref=1 → core 1)
 *
 * Grant equations:
 *   grant0 = req0 && (!req1 || (pref == 0))
 *   grant1 = req1 && (!req0 || (pref == 1))
 */

module axi_lite_arbiter (
    input  logic        clk,
    input  logic        rst_n,
    
    // Master 0 request and AXI signals
    input  logic        req0,
    input  logic        awvalid0,
    input  logic [31:0] awaddr0,
    output logic        awready0,
    input  logic        wvalid0,
    input  logic [31:0] wdata0,
    input  logic [3:0]  wstrb0,
    output logic        wready0,
    output logic        bvalid0,
    output logic [1:0]  bresp0,
    input  logic        bready0,
    input  logic        arvalid0,
    input  logic [31:0] araddr0,
    output logic        arready0,
    output logic        rvalid0,
    output logic [31:0] rdata0,
    output logic [1:0]  rresp0,
    input  logic        rready0,
    
    // Master 1 request and AXI signals
    input  logic        req1,
    input  logic        awvalid1,
    input  logic [31:0] awaddr1,
    output logic        awready1,
    input  logic        wvalid1,
    input  logic [31:0] wdata1,
    input  logic [3:0]  wstrb1,
    output logic        wready1,
    output logic        bvalid1,
    output logic [1:0]  bresp1,
    input  logic        bready1,
    input  logic        arvalid1,
    input  logic [31:0] araddr1,
    output logic        arready1,
    output logic        rvalid1,
    output logic [31:0] rdata1,
    output logic [1:0]  rresp1,
    input  logic        rready1,
    
    // Shared slave port (to decoder)
    output logic        awvalid_s,
    output logic [31:0] awaddr_s,
    input  logic        awready_s,
    output logic        wvalid_s,
    output logic [31:0] wdata_s,
    output logic [3:0]  wstrb_s,
    input  logic        wready_s,
    input  logic        bvalid_s,
    input  logic [1:0]  bresp_s,
    output logic        bready_s,
    output logic        arvalid_s,
    output logic [31:0] araddr_s,
    input  logic        arready_s,
    input  logic        rvalid_s,
    input  logic [31:0] rdata_s,
    input  logic [1:0]  rresp_s,
    output logic        rready_s
);

    // FSM states (doc 06 §6.3)
    typedef enum logic [1:0] {
        ARB_IDLE = 2'b00,
        ARB_G0   = 2'b01,
        ARB_G1   = 2'b10
    } arb_state_e;
    
    arb_state_e state_d, state_q;
    logic pref_d, pref_q;
    
    // Grant signals (combinational from truth table)
    logic grant0, grant1;
    
    // Completion detection
    logic done0, done1;
    
    // =====================================================================
    // ARBITRATION GRANT LOGIC (Combinational)
    // =====================================================================
    // Truth table (doc 06 §6.2):
    //   grant0 = req0 && (!req1 || (pref == 0))
    //   grant1 = req1 && (!req0 || (pref == 1))
    
    assign grant0 = req0 && (!req1 || (pref_q == 1'b0));
    assign grant1 = req1 && (!req0 || (pref_q == 1'b1));
    
    // =====================================================================
    // COMPLETION DETECTION
    // =====================================================================
    // Done on final handshake of the granted master's transaction
    // (B ends write, R ends read; exactly one per transaction, both held until ready)
    
    assign done0 = (bvalid0 && bready0) || (rvalid0 && rready0);
    assign done1 = (bvalid1 && bready1) || (rvalid1 && rready1);
    
    // =====================================================================
    // FSM STATE MACHINE (doc 06 §6.3)
    // =====================================================================
    
    always_comb begin
        // Default values
        state_d = state_q;
        pref_d = pref_q;
        
        unique case (state_q)
            ARB_IDLE: begin
                if (grant0)
                    state_d = ARB_G0;
                else if (grant1)
                    state_d = ARB_G1;
                // else: stay idle
            end
            
            ARB_G0: begin
                if (done0) begin
                    state_d = ARB_IDLE;
                    pref_d = 1'b0;  // Flip preference to other master
                end
            end
            
            ARB_G1: begin
                if (done1) begin
                    state_d = ARB_IDLE;
                    pref_d = 1'b1;  // Flip preference to other master
                end
            end
            
            default: state_d = ARB_IDLE;
        endcase
    end
    
    // =====================================================================
    // OUTPUT MUX (Request path: granted master → shared slave)
    // =====================================================================
    // From doc 06 §6.4 mux wiring
    
    assign awvalid_s = (grant0) ? awvalid0 : awvalid1;
    assign awaddr_s  = (grant0) ? awaddr0  : awaddr1;
    assign wvalid_s  = (grant0) ? wvalid0  : wvalid1;
    assign wdata_s   = (grant0) ? wdata0   : wdata1;
    assign wstrb_s   = (grant0) ? wstrb0   : wstrb1;
    assign arvalid_s = (grant0) ? arvalid0 : arvalid1;
    assign araddr_s  = (grant0) ? araddr0  : araddr1;
    
    // =====================================================================
    // INPUT MUX (Response path: shared slave → granted master only)
    // =====================================================================
    // From doc 06 §6.4 mux wiring
    
    // Write channel responses
    assign awready0 = (grant0) && awready_s;
    assign awready1 = (grant1) && awready_s;
    assign wready0  = (grant0) && wready_s;
    assign wready1  = (grant1) && wready_s;
    assign bvalid0  = (grant0) && bvalid_s;
    assign bvalid1  = (grant1) && bvalid_s;
    assign bresp0   = bresp_s;
    assign bresp1   = bresp_s;
    
    // Read channel responses
    assign arready0 = (grant0) && arready_s;
    assign arready1 = (grant1) && arready_s;
    assign rvalid0  = (grant0) && rvalid_s;
    assign rvalid1  = (grant1) && rvalid_s;
    assign rdata0   = rdata_s;
    assign rdata1   = rdata_s;
    assign rresp0   = rresp_s;
    assign rresp1   = rresp_s;
    
    // Ready mux (granted master's ready → shared slave)
    assign bready_s = (grant0) ? bready0 : bready1;
    assign rready_s = (grant0) ? rready0 : rready1;
    
    // =====================================================================
    // SEQUENTIAL LOGIC (State & preference updates)
    // =====================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= ARB_IDLE;
            pref_q  <= 1'b0;        // Core 0 priority at reset (TRD Scenario B)
        end else begin
            state_q <= state_d;
            pref_q  <= pref_d;
        end
    end

endmodule : axi_lite_arbiter
