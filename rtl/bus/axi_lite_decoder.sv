/**
 * @module axi_lite_decoder.sv
 * @brief Address Decoder and DECERR Slave (T2.10)
 *
 * Source: logic_design/07_decoder_and_bus_fabric.md
 *
 * Purpose: Decode master address and route to one of four slaves (SRAM, MMIO, UART, GPIO)
 * or DECERR slave for unmapped addresses. Implements AXI4-Lite fabric contract.
 *
 * Address Map (from doc 07 §7.1–7.2):
 *   0x0000_0000–0x0000_0FFF (4 KB)   → Shared Data SRAM
 *   0x0001_0000–0x0001_00FF (256 B)  → MMIO Registers
 *   0x0001_0100–0x0001_01FF (256 B)  → UART Core
 *   0x0001_0200–0x0001_02FF (256 B)  → GPIO/LED
 *   Anything else                     → DECERR
 *
 * Decode truth table (from doc 07 §7.2):
 *   sel_sram  = (addr[31:12] == 20'h00000)
 *   sel_mmio  = (addr[31:16] == 16'h0001) && (addr[15:8] == 8'h00)
 *   sel_uart  = (addr[31:16] == 16'h0001) && (addr[15:8] == 8'h01)
 *   sel_gpio  = (addr[31:16] == 16'h0001) && (addr[15:8] == 8'h02)
 *   sel_decerr = !(sel_sram | sel_mmio | sel_uart | sel_gpio)
 *
 * DECERR FSM (from doc 07 §7.3): Handles unmapped addresses gracefully.
 */

module axi_lite_decoder (
    input  logic        clk,
    input  logic        rst_n,
    
    // Master side (from arbiter)
    input  logic        awvalid_m,
    input  logic [31:0] awaddr_m,
    output logic        awready_m,
    input  logic        wvalid_m,
    input  logic [31:0] wdata_m,
    input  logic [3:0]  wstrb_m,
    output logic        wready_m,
    output logic        bvalid_m,
    output logic [1:0]  bresp_m,
    input  logic        bready_m,
    input  logic        arvalid_m,
    input  logic [31:0] araddr_m,
    output logic        arready_m,
    output logic        rvalid_m,
    output logic [31:0] rdata_m,
    output logic [1:0]  rresp_m,
    input  logic        rready_m,
    
    // Slave: Shared Data SRAM
    output logic        sel_sram,
    output logic        awvalid_sram,
    output logic [31:0] awaddr_sram,
    input  logic        awready_sram,
    output logic        wvalid_sram,
    output logic [31:0] wdata_sram,
    output logic [3:0]  wstrb_sram,
    input  logic        wready_sram,
    input  logic        bvalid_sram,
    input  logic [1:0]  bresp_sram,
    output logic        bready_sram,
    output logic        arvalid_sram,
    output logic [31:0] araddr_sram,
    input  logic        arready_sram,
    input  logic        rvalid_sram,
    input  logic [31:0] rdata_sram,
    input  logic [1:0]  rresp_sram,
    output logic        rready_sram,
    
    // Slave: MMIO Registers
    output logic        sel_mmio,
    output logic        awvalid_mmio,
    output logic [31:0] awaddr_mmio,
    input  logic        awready_mmio,
    output logic        wvalid_mmio,
    output logic [31:0] wdata_mmio,
    output logic [3:0]  wstrb_mmio,
    input  logic        wready_mmio,
    input  logic        bvalid_mmio,
    input  logic [1:0]  bresp_mmio,
    output logic        bready_mmio,
    output logic        arvalid_mmio,
    output logic [31:0] araddr_mmio,
    input  logic        arready_mmio,
    input  logic        rvalid_mmio,
    input  logic [31:0] rdata_mmio,
    input  logic [1:0]  rresp_mmio,
    output logic        rready_mmio,
    
    // Slave: UART Core
    output logic        sel_uart,
    output logic        awvalid_uart,
    output logic [31:0] awaddr_uart,
    input  logic        awready_uart,
    output logic        wvalid_uart,
    output logic [31:0] wdata_uart,
    output logic [3:0]  wstrb_uart,
    input  logic        wready_uart,
    input  logic        bvalid_uart,
    input  logic [1:0]  bresp_uart,
    output logic        bready_uart,
    output logic        arvalid_uart,
    output logic [31:0] araddr_uart,
    input  logic        arready_uart,
    input  logic        rvalid_uart,
    input  logic [31:0] rdata_uart,
    input  logic [1:0]  rresp_uart,
    output logic        rready_uart,
    
    // Slave: GPIO/LED
    output logic        sel_gpio,
    output logic        awvalid_gpio,
    output logic [31:0] awaddr_gpio,
    input  logic        awready_gpio,
    output logic        wvalid_gpio,
    output logic [31:0] wdata_gpio,
    output logic [3:0]  wstrb_gpio,
    input  logic        wready_gpio,
    input  logic        bvalid_gpio,
    input  logic [1:0]  bresp_gpio,
    output logic        bready_gpio,
    output logic        arvalid_gpio,
    output logic [31:0] araddr_gpio,
    input  logic        arready_gpio,
    input  logic        rvalid_gpio,
    input  logic [31:0] rdata_gpio,
    input  logic [1:0]  rresp_gpio,
    output logic        rready_gpio
);

    // =====================================================================
    // ADDRESS DECODE (Combinational, doc 07 §7.1)
    // =====================================================================
    
    logic sel_decerr;
    
    assign sel_sram  = (awaddr_m[31:12] == 20'h00000) || (araddr_m[31:12] == 20'h00000);
    assign sel_mmio  = ((awaddr_m[31:16] == 16'h0001) && (awaddr_m[15:8] == 8'h00)) ||
                       ((araddr_m[31:16] == 16'h0001) && (araddr_m[15:8] == 8'h00));
    assign sel_uart  = ((awaddr_m[31:16] == 16'h0001) && (awaddr_m[15:8] == 8'h01)) ||
                       ((araddr_m[31:16] == 16'h0001) && (araddr_m[15:8] == 8'h01));
    assign sel_gpio  = ((awaddr_m[31:16] == 16'h0001) && (awaddr_m[15:8] == 8'h02)) ||
                       ((araddr_m[31:16] == 16'h0001) && (araddr_m[15:8] == 8'h02));
    assign sel_decerr = !(sel_sram | sel_mmio | sel_uart | sel_gpio);
    
    // =====================================================================
    // BROADCAST WRITE ADDRESS & WRITE DATA (all slaves get them)
    // Valid/ready handshake handled per-slave below
    // =====================================================================
    
    assign awvalid_sram = awvalid_m;
    assign awaddr_sram  = awaddr_m;
    assign wvalid_sram  = wvalid_m;
    assign wdata_sram   = wdata_m;
    assign wstrb_sram   = wstrb_m;
    
    assign awvalid_mmio = awvalid_m;
    assign awaddr_mmio  = awaddr_m;
    assign wvalid_mmio  = wvalid_m;
    assign wdata_mmio   = wdata_m;
    assign wstrb_mmio   = wstrb_m;
    
    assign awvalid_uart = awvalid_m;
    assign awaddr_uart  = awaddr_m;
    assign wvalid_uart  = wvalid_m;
    assign wdata_uart   = wdata_m;
    assign wstrb_uart   = wstrb_m;
    
    assign awvalid_gpio = awvalid_m;
    assign awaddr_gpio  = awaddr_m;
    assign wvalid_gpio  = wvalid_m;
    assign wdata_gpio   = wdata_m;
    assign wstrb_gpio   = wstrb_m;
    
    // =====================================================================
    // MUX READY SIGNALS FROM SELECTED SLAVE (Write channel)
    // =====================================================================
    
    logic awready_sel, wready_sel;
    
    assign awready_sel = sel_sram  ? awready_sram  :
                        sel_mmio  ? awready_mmio  :
                        sel_uart  ? awready_uart  :
                        sel_gpio  ? awready_gpio  :
                        1'b1;  // DECERR always ready
    
    assign wready_sel = sel_sram  ? wready_sram  :
                       sel_mmio  ? wready_mmio  :
                       sel_uart  ? wready_uart  :
                       sel_gpio  ? wready_gpio  :
                       1'b1;  // DECERR always ready
    
    assign awready_m = awready_sel;
    assign wready_m  = wready_sel;
    
    // =====================================================================
    // MUX WRITE RESPONSE FROM SELECTED SLAVE (or DECERR)
    // =====================================================================
    
    logic bvalid_sel;
    logic [1:0] bresp_sel;
    
    assign bvalid_sel = sel_sram  ? bvalid_sram  :
                       sel_mmio  ? bvalid_mmio  :
                       sel_uart  ? bvalid_uart  :
                       sel_gpio  ? bvalid_gpio  :
                       bvalid_decerr;
    
    assign bresp_sel = sel_sram  ? bresp_sram  :
                      sel_mmio  ? bresp_mmio  :
                      sel_uart  ? bresp_uart  :
                      sel_gpio  ? bresp_gpio  :
                      2'b11;  // DECERR code for DECERR (from doc 07 §7.3)
    
    assign bvalid_m = bvalid_sel;
    assign bresp_m  = bresp_sel;
    
    // =====================================================================
    // MUX READY FROM MASTER TO SELECTED SLAVE (Write response)
    // =====================================================================
    
    assign bready_sram = (sel_sram && bready_m) || (!sel_sram && !bvalid_sram);
    assign bready_mmio = (sel_mmio && bready_m) || (!sel_mmio && !bvalid_mmio);
    assign bready_uart = (sel_uart && bready_m) || (!sel_uart && !bvalid_uart);
    assign bready_gpio = (sel_gpio && bready_m) || (!sel_gpio && !bvalid_gpio);
    
    // =====================================================================
    // BROADCAST READ ADDRESS (all slaves get it)
    // =====================================================================
    
    assign arvalid_sram = arvalid_m;
    assign araddr_sram  = araddr_m;
    
    assign arvalid_mmio = arvalid_m;
    assign araddr_mmio  = araddr_m;
    
    assign arvalid_uart = arvalid_m;
    assign araddr_uart  = araddr_m;
    
    assign arvalid_gpio = arvalid_m;
    assign araddr_gpio  = araddr_m;
    
    // =====================================================================
    // MUX READ ADDRESS READY (Read channel)
    // =====================================================================
    
    logic arready_sel;
    
    assign arready_sel = sel_sram  ? arready_sram  :
                        sel_mmio  ? arready_mmio  :
                        sel_uart  ? arready_uart  :
                        sel_gpio  ? arready_gpio  :
                        1'b1;  // DECERR always ready
    
    assign arready_m = arready_sel;
    
    // =====================================================================
    // MUX READ DATA & RESPONSE FROM SELECTED SLAVE (or DECERR)
    // =====================================================================
    
    logic rvalid_sel;
    logic [31:0] rdata_sel;
    logic [1:0] rresp_sel;
    
    assign rvalid_sel = sel_sram  ? rvalid_sram  :
                       sel_mmio  ? rvalid_mmio  :
                       sel_uart  ? rvalid_uart  :
                       sel_gpio  ? rvalid_gpio  :
                       rvalid_decerr;
    
    assign rdata_sel = sel_sram  ? rdata_sram  :
                      sel_mmio  ? rdata_mmio  :
                      sel_uart  ? rdata_uart  :
                      sel_gpio  ? rdata_gpio  :
                      32'h0;  // DECERR returns zeros
    
    assign rresp_sel = sel_sram  ? rresp_sram  :
                      sel_mmio  ? rresp_mmio  :
                      sel_uart  ? rresp_uart  :
                      sel_gpio  ? rresp_gpio  :
                      2'b11;  // DECERR code
    
    assign rvalid_m = rvalid_sel;
    assign rdata_m  = rdata_sel;
    assign rresp_m  = rresp_sel;
    
    // =====================================================================
    // MUX READY FROM MASTER TO SELECTED SLAVE (Read response)
    // =====================================================================
    
    assign rready_sram = (sel_sram && rready_m) || (!sel_sram && !rvalid_sram);
    assign rready_mmio = (sel_mmio && rready_m) || (!sel_mmio && !rvalid_mmio);
    assign rready_uart = (sel_uart && rready_m) || (!sel_uart && !rvalid_uart);
    assign rready_gpio = (sel_gpio && rready_m) || (!sel_gpio && !rvalid_gpio);
    
    // =====================================================================
    // DECERR SLAVE FSM (doc 07 §7.3)
    // =====================================================================
    // Purpose: Give unmapped accesses proper AXI response instead of hang.
    // Handles simultaneous AW+W arriving in any order.
    
    typedef enum logic [1:0] {
        DEC_IDLE   = 2'b00,
        DEC_W_GOTAW = 2'b01,
        DEC_W_GOTW = 2'b10,
        DEC_B_RESP = 2'b11
    } dec_state_e;
    
    dec_state_e dec_state_d, dec_state_q;
    logic aw_got, w_got;
    logic bvalid_decerr, rvalid_decerr;
    
    // Write path FSM (handles AW+W arriving in any order)
    always_comb begin
        dec_state_d = dec_state_q;
        aw_got = 1'b0;
        w_got = 1'b0;
        bvalid_decerr = 1'b0;
        
        if (sel_decerr) begin
            unique case (dec_state_q)
                DEC_IDLE: begin
                    if (awvalid_m && !wvalid_m) begin
                        // Only AW arrived
                        dec_state_d = DEC_W_GOTAW;
                    end else if (!awvalid_m && wvalid_m) begin
                        // Only W arrived
                        dec_state_d = DEC_W_GOTW;
                    end else if (awvalid_m && wvalid_m) begin
                        // Both arrived together → go directly to B
                        dec_state_d = DEC_B_RESP;
                    end
                end
                
                DEC_W_GOTAW: begin
                    if (wvalid_m) begin
                        // W now arrived
                        dec_state_d = DEC_B_RESP;
                    end
                end
                
                DEC_W_GOTW: begin
                    if (awvalid_m) begin
                        // AW now arrived
                        dec_state_d = DEC_B_RESP;
                    end
                end
                
                DEC_B_RESP: begin
                    bvalid_decerr = 1'b1;
                    if (bready_m) begin
                        dec_state_d = DEC_IDLE;
                    end
                end
                
                default: dec_state_d = DEC_IDLE;
            endcase
        end
    end
    
    // Read path (independent, since one transaction at a time by arbiter)
    // On AR, next cycle return R with DECERR
    logic ar_capture;
    assign ar_capture = arvalid_m && sel_decerr;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid_decerr <= 1'b0;
        end else begin
            if (ar_capture) begin
                rvalid_decerr <= 1'b1;
            end else if (rvalid_decerr && rready_m) begin
                rvalid_decerr <= 1'b0;
            end
        end
    end
    
    // Write FSM state update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dec_state_q <= DEC_IDLE;
        end else begin
            dec_state_q <= dec_state_d;
        end
    end

endmodule : axi_lite_decoder
