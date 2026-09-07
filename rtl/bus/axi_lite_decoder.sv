/**
 * @module axi_lite_decoder.sv
 * @brief Address Decoder and DECERR Slave (T2.10)
 *
 * Source: logic_design/07_decoder_and_bus_fabric.md
 *
 * FIXES APPLIED (Second Draft):
 *  BUG-007: Replaced single shared sel_* decode (which OR'd awaddr_m and araddr_m
 *           together) with separate per-channel decode sets:
 *             wr_sel_* — decoded from awaddr_m only, used for all write-channel muxes
 *             rd_sel_* — decoded from araddr_m only, used for all read-channel muxes
 *           This ensures a simultaneous write to slave A and read from slave B cannot
 *           corrupt each other's ready/valid/data routing.
 *           External sel_* outputs now reflect the write-channel decode (wr_sel_*),
 *           preserving backward-compatibility with any integrator that monitors them.
 *           The DECERR FSM now uses wr_sel_decerr for the write path and
 *           rd_sel_decerr for the AR-capture read path.
 *
 * Purpose: Decode master address and route to one of four slaves (SRAM, MMIO, UART,
 *          GPIO) or DECERR slave for unmapped addresses.
 *
 * Address Map (from doc 07 §7.1–7.2):
 *   0x0000_0000–0x0000_0FFF (4 KB)   → Shared Data SRAM
 *   0x0001_0000–0x0001_00FF (256 B)  → MMIO Registers
 *   0x0001_0100–0x0001_01FF (256 B)  → UART Core
 *   0x0001_0200–0x0001_02FF (256 B)  → GPIO/LED
 *   Anything else                     → DECERR
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
    // BUG-007 FIX: SEPARATE WRITE-CHANNEL AND READ-CHANNEL ADDRESS DECODE
    // Previously a single set of sel_* signals OR'd awaddr_m and araddr_m,
    // causing cross-channel contamination on simultaneous transactions.
    // Now: wr_sel_* decoded from awaddr_m only; rd_sel_* from araddr_m only.
    // =====================================================================

    // --- Write-channel decode (awaddr_m only) ---
    logic wr_sel_sram, wr_sel_mmio, wr_sel_uart, wr_sel_gpio, wr_sel_decerr;

    always_comb begin
        wr_sel_sram  =  (awaddr_m[31:12] == 20'h00000);
        wr_sel_mmio  =  (awaddr_m[31:16] == 16'h0001) && (awaddr_m[15:8] == 8'h00);
        wr_sel_uart  =  (awaddr_m[31:16] == 16'h0001) && (awaddr_m[15:8] == 8'h01);
        wr_sel_gpio  =  (awaddr_m[31:16] == 16'h0001) && (awaddr_m[15:8] == 8'h02);
        wr_sel_decerr = !(wr_sel_sram | wr_sel_mmio | wr_sel_uart | wr_sel_gpio);
    end

    // --- Read-channel decode (araddr_m only) ---
    logic rd_sel_sram, rd_sel_mmio, rd_sel_uart, rd_sel_gpio, rd_sel_decerr;

    always_comb begin
        rd_sel_sram  =  (araddr_m[31:12] == 20'h00000);
        rd_sel_mmio  =  (araddr_m[31:16] == 16'h0001) && (araddr_m[15:8] == 8'h00);
        rd_sel_uart  =  (araddr_m[31:16] == 16'h0001) && (araddr_m[15:8] == 8'h01);
        rd_sel_gpio  =  (araddr_m[31:16] == 16'h0001) && (araddr_m[15:8] == 8'h02);
        rd_sel_decerr = !(rd_sel_sram | rd_sel_mmio | rd_sel_uart | rd_sel_gpio);
    end

    // --- External sel_* outputs reflect write-channel decode ---
    // (backward-compatible for integrators that monitor these ports)
    assign sel_sram = wr_sel_sram;
    assign sel_mmio = wr_sel_mmio;
    assign sel_uart = wr_sel_uart;
    assign sel_gpio = wr_sel_gpio;

    // =====================================================================
    // BROADCAST WRITE ADDRESS & DATA (all slaves receive address/data)
    // Valid/ready handshake per-slave below ensures only selected slave acts.
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
    // WRITE CHANNEL MUXES — all use wr_sel_* (BUG-007 fix)
    // =====================================================================

    // AW/W ready back to master — from selected write slave
    assign awready_m = wr_sel_sram  ? awready_sram  :
                       wr_sel_mmio  ? awready_mmio  :
                       wr_sel_uart  ? awready_uart  :
                       wr_sel_gpio  ? awready_gpio  :
                       1'b1;    // DECERR always ready

    assign wready_m  = wr_sel_sram  ? wready_sram   :
                       wr_sel_mmio  ? wready_mmio   :
                       wr_sel_uart  ? wready_uart   :
                       wr_sel_gpio  ? wready_gpio   :
                       1'b1;

    // B channel — write response from selected write slave
    logic bvalid_decerr;   // driven by DECERR FSM below

    assign bvalid_m  = wr_sel_sram  ? bvalid_sram   :
                       wr_sel_mmio  ? bvalid_mmio   :
                       wr_sel_uart  ? bvalid_uart   :
                       wr_sel_gpio  ? bvalid_gpio   :
                       bvalid_decerr;

    assign bresp_m   = wr_sel_sram  ? bresp_sram    :
                       wr_sel_mmio  ? bresp_mmio    :
                       wr_sel_uart  ? bresp_uart    :
                       wr_sel_gpio  ? bresp_gpio    :
                       2'b11;   // DECERR response code

    // bready to each write slave — gated by wr_sel_* (BUG-007 fix)
    assign bready_sram = (wr_sel_sram && bready_m) || (!wr_sel_sram && !bvalid_sram);
    assign bready_mmio = (wr_sel_mmio && bready_m) || (!wr_sel_mmio && !bvalid_mmio);
    assign bready_uart = (wr_sel_uart && bready_m) || (!wr_sel_uart && !bvalid_uart);
    assign bready_gpio = (wr_sel_gpio && bready_m) || (!wr_sel_gpio && !bvalid_gpio);

    // =====================================================================
    // BROADCAST READ ADDRESS (all slaves receive it)
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
    // READ CHANNEL MUXES — all use rd_sel_* (BUG-007 fix)
    // =====================================================================

    logic rvalid_decerr;   // driven by read DECERR path below

    // AR ready back to master — from selected read slave
    assign arready_m = rd_sel_sram  ? arready_sram  :
                       rd_sel_mmio  ? arready_mmio  :
                       rd_sel_uart  ? arready_uart  :
                       rd_sel_gpio  ? arready_gpio  :
                       1'b1;    // DECERR always ready

    // R channel — read data/response from selected read slave
    assign rvalid_m  = rd_sel_sram  ? rvalid_sram   :
                       rd_sel_mmio  ? rvalid_mmio   :
                       rd_sel_uart  ? rvalid_uart   :
                       rd_sel_gpio  ? rvalid_gpio   :
                       rvalid_decerr;

    assign rdata_m   = rd_sel_sram  ? rdata_sram    :
                       rd_sel_mmio  ? rdata_mmio    :
                       rd_sel_uart  ? rdata_uart    :
                       rd_sel_gpio  ? rdata_gpio    :
                       32'h0;   // DECERR returns zeros

    assign rresp_m   = rd_sel_sram  ? rresp_sram    :
                       rd_sel_mmio  ? rresp_mmio    :
                       rd_sel_uart  ? rresp_uart    :
                       rd_sel_gpio  ? rresp_gpio    :
                       2'b11;   // DECERR response code

    // rready to each read slave — gated by rd_sel_* (BUG-007 fix)
    assign rready_sram = (rd_sel_sram && rready_m) || (!rd_sel_sram && !rvalid_sram);
    assign rready_mmio = (rd_sel_mmio && rready_m) || (!rd_sel_mmio && !rvalid_mmio);
    assign rready_uart = (rd_sel_uart && rready_m) || (!rd_sel_uart && !rvalid_uart);
    assign rready_gpio = (rd_sel_gpio && rready_m) || (!rd_sel_gpio && !rvalid_gpio);

    // =====================================================================
    // DECERR SLAVE FSM (doc 07 §7.3)
    // Handles unmapped AW/W transactions with a proper AXI B response.
    // BUG-007 fix: uses wr_sel_decerr (not the old shared sel_decerr).
    // =====================================================================

    typedef enum logic [1:0] {
        DEC_IDLE    = 2'b00,
        DEC_W_GOTAW = 2'b01,
        DEC_W_GOTW  = 2'b10,
        DEC_B_RESP  = 2'b11
    } dec_state_e;

    dec_state_e dec_state_d, dec_state_q;

    // Write-path DECERR FSM — uses wr_sel_decerr (BUG-007 fix)
    always_comb begin
        dec_state_d  = dec_state_q;
        bvalid_decerr = 1'b0;

        if (wr_sel_decerr) begin
            unique case (dec_state_q)
                DEC_IDLE: begin
                    if (awvalid_m && !wvalid_m) begin
                        dec_state_d = DEC_W_GOTAW;
                    end else if (!awvalid_m && wvalid_m) begin
                        dec_state_d = DEC_W_GOTW;
                    end else if (awvalid_m && wvalid_m) begin
                        dec_state_d = DEC_B_RESP;
                    end
                end

                DEC_W_GOTAW: begin
                    if (wvalid_m) begin
                        dec_state_d = DEC_B_RESP;
                    end
                end

                DEC_W_GOTW: begin
                    if (awvalid_m) begin
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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dec_state_q <= DEC_IDLE;
        end else begin
            dec_state_q <= dec_state_d;
        end
    end

    // =====================================================================
    // DECERR READ PATH
    // On AR from an unmapped address, respond with DECERR on the next cycle.
    // BUG-007 fix: uses rd_sel_decerr (not the old shared sel_decerr).
    // =====================================================================

    logic ar_capture;
    assign ar_capture = arvalid_m && rd_sel_decerr;   // BUG-007 fix

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

endmodule : axi_lite_decoder
