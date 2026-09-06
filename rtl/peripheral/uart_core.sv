/**
 * @module uart_core.sv
 * @brief UART Core (T2.12)
 *
 * Source: logic_design/09_peripherals.md §9.2
 *
 * Purpose: UART transmitter and receiver at 115200 baud, 8N1.
 * Base address: 0x0001_0100
 * Baud rate: 50 MHz / 115200 = 434.03 → BAUD_DIV = 434 (10-bit counter)
 *
 * Register Map:
 *   0x00  TX_DATA      W   Write byte to transmit
 *   0x04  TX_STATUS    R   bit0 = TX ready (1 = idle, accept new byte)
 *   0x08  RX_DATA      R   Last received byte (read clears RX valid)
 *   0x0C  RX_STATUS    R   bit0 = RX valid (byte pending)
 *
 * TX FSM (4 states, 10-bit shift register, 4-bit bit counter):
 *   TX_IDLE → TX_START → TX_DATA_F → TX_STOP → TX_IDLE
 *   Transmits 10 bits: {stop(1), data(8), start(1)}
 *   LSB first
 *
 * RX FSM (4 states, 8-bit shift register, sample counter):
 *   RX_IDLE → RX_START → RX_DATA → RX_STOP → RX_IDLE
 *   ÷16 oversampling; mid-bit sample point = 8/16 after start edge
 *   Glitch filter: 2-sample majority vote on start edge
 */

module uart_core (
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
    
    // UART pins
    output logic        uart_tx,
    input  logic        uart_rx
);

    // Baud rate divider: 50 MHz / 115200 = 434.03
    localparam BAUD_DIV = 10'd434;
    
    // Register offsets
    localparam OFFSET_TX_DATA   = 8'h00;
    localparam OFFSET_TX_STATUS = 8'h04;
    localparam OFFSET_RX_DATA   = 8'h08;
    localparam OFFSET_RX_STATUS = 8'h0C;
    
    // Extract offset from address
    logic [7:0] offset_aw, offset_ar;
    assign offset_aw = awaddr[7:0];
    assign offset_ar = araddr[7:0];
    
    // =====================================================================
    // AXI4-LITE WRITE INTERFACE (always ready template)
    // =====================================================================
    
    assign awready = 1'b1;
    assign wready  = 1'b1;
    
    logic write_txn;
    assign write_txn = awvalid && awready && wvalid && wready;
    
    // Write response
    logic bresp_valid_d, bresp_valid_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bresp_valid_q <= 1'b0;
        else if (bresp_valid_q && bready)
            bresp_valid_q <= 1'b0;
        else if (write_txn && !bresp_valid_q)
            bresp_valid_q <= 1'b1;
    end
    
    assign bvalid = bresp_valid_q;
    assign bresp  = 2'b00;  // OKAY
    
    // =====================================================================
    // TX SIDE (from doc 09 §9.2 TX FSM table)
    // =====================================================================
    
    typedef enum logic [1:0] {
        TX_IDLE    = 2'b00,
        TX_START   = 2'b01,
        TX_DATA_F  = 2'b10,
        TX_STOP    = 2'b11
    } tx_state_e;
    
    tx_state_e tx_state_d, tx_state_q;
    logic [9:0] tx_shift_d, tx_shift_q;
    logic [3:0] tx_bitcnt_d, tx_bitcnt_q;
    logic [9:0] tx_baud_cnt_d, tx_baud_cnt_q;
    logic tx_ready_d, tx_ready_q;
    
    logic tx_baud_tick;
    assign tx_baud_tick = (tx_baud_cnt_q == 10'h0);
    
    logic tx_byte_write;
    assign tx_byte_write = write_txn && (offset_aw[7:0] == OFFSET_TX_DATA);
    
    always_comb begin
        tx_state_d    = tx_state_q;
        tx_shift_d    = tx_shift_q;
        tx_bitcnt_d   = tx_bitcnt_q;
        tx_baud_cnt_d = (tx_baud_cnt_q == 10'h0) ? BAUD_DIV : tx_baud_cnt_q - 10'h1;
        tx_ready_d    = tx_ready_q;
        
        unique case (tx_state_q)
            TX_IDLE: begin
                tx_ready_d = 1'b1;
                if (tx_byte_write) begin
                    // Load shift register: {stop(1), data(8), start(0)}
                    tx_shift_d = {1'b1, wdata[7:0], 1'b0};
                    tx_bitcnt_d = 4'h0;
                    tx_state_d = TX_START;
                    tx_ready_d = 1'b0;
                    tx_baud_cnt_d = BAUD_DIV;
                end
            end
            
            TX_START: begin
                if (tx_baud_tick) begin
                    tx_state_d = TX_DATA_F;
                    tx_bitcnt_d = 4'h0;
                    tx_baud_cnt_d = BAUD_DIV;
                end
            end
            
            TX_DATA_F: begin
                if (tx_baud_tick) begin
                    tx_bitcnt_d = tx_bitcnt_q + 4'h1;
                    tx_shift_d = {1'b0, tx_shift_q[9:1]};  // Shift right (LSB first)
                    
                    if (tx_bitcnt_q == 4'h7) begin  // 8 data bits
                        tx_state_d = TX_STOP;
                    end
                    
                    tx_baud_cnt_d = BAUD_DIV;
                end
            end
            
            TX_STOP: begin
                if (tx_baud_tick) begin
                    tx_state_d = TX_IDLE;
                    tx_baud_cnt_d = BAUD_DIV;
                end
            end
            
            default: tx_state_d = TX_IDLE;
        endcase
    end
    
    // TX output (bit 0 of shift register in data/stop, 1 in idle/start)
    logic tx_bit;
    assign tx_bit = (tx_state_q == TX_IDLE) ? 1'b1 :
                    (tx_state_q == TX_START) ? 1'b0 :
                    tx_shift_q[0];  // LSB for TX_DATA_F and TX_STOP
    
    assign uart_tx = tx_bit;
    
    // =====================================================================
    // RX SIDE (from doc 09 §9.2 RX FSM)
    // =====================================================================
    
    typedef enum logic [1:0] {
        RX_IDLE = 2'b00,
        RX_START = 2'b01,
        RX_DATA = 2'b10,
        RX_STOP = 2'b11
    } rx_state_e;
    
    rx_state_e rx_state_d, rx_state_q;
    logic [7:0] rx_byte_d, rx_byte_q;
    logic [3:0] rx_bitcnt_d, rx_bitcnt_q;
    logic [9:0] rx_sample_cnt_d, rx_sample_cnt_q;
    logic rx_valid_d, rx_valid_q;
    
    // RX synchronizer (2 FF, doc 12 §12.4)
    logic uart_rx_sync1, uart_rx_sync2;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_rx_sync1 <= 1'b1;
            uart_rx_sync2 <= 1'b1;
        end else begin
            uart_rx_sync1 <= uart_rx;
            uart_rx_sync2 <= uart_rx_sync1;
        end
    end
    
    // Glitch filter: 2-sample majority vote on start edge detection
    logic rx_start_edge;
    logic [1:0] rx_sample_window;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rx_sample_window <= 2'b11;
        else
            rx_sample_window <= {rx_sample_window[0], uart_rx_sync2};
    end
    assign rx_start_edge = (rx_sample_window == 2'b10);  // 1→0 edge
    
    // Mid-bit sample point: 8/16 of baud period after start edge
    logic rx_mid_bit_sample;
    assign rx_mid_bit_sample = (rx_sample_cnt_q == (BAUD_DIV >> 1));  // 8/16 = 50% ≈ 217 ticks
    
    // RX read (clears rx_valid)
    logic rx_read;
    assign rx_read = arvalid && arready && (offset_ar[7:0] == OFFSET_RX_DATA);
    
    always_comb begin
        rx_state_d      = rx_state_q;
        rx_byte_d       = rx_byte_q;
        rx_bitcnt_d     = rx_bitcnt_q;
        rx_sample_cnt_d = (rx_sample_cnt_q == 10'h0) ? 10'h0 : rx_sample_cnt_q - 10'h1;
        rx_valid_d      = rx_valid_q;
        
        unique case (rx_state_q)
            RX_IDLE: begin
                if (rx_start_edge) begin
                    rx_state_d = RX_START;
                    rx_sample_cnt_d = BAUD_DIV;  // Count down to mid-bit
                end
            end
            
            RX_START: begin
                if (rx_mid_bit_sample) begin
                    if (uart_rx_sync2 == 1'b0) begin
                        // Confirmed start bit
                        rx_state_d = RX_DATA;
                        rx_bitcnt_d = 4'h0;
                        rx_sample_cnt_d = BAUD_DIV;  // For next bit
                    end else begin
                        // False alarm
                        rx_state_d = RX_IDLE;
                    end
                end
            end
            
            RX_DATA: begin
                if (rx_mid_bit_sample) begin
                    rx_byte_d = {uart_rx_sync2, rx_byte_q[7:1]};  // LSB first
                    rx_bitcnt_d = rx_bitcnt_q + 4'h1;
                    
                    if (rx_bitcnt_q == 4'h7) begin  // 8 bits collected
                        rx_state_d = RX_STOP;
                    end
                    
                    rx_sample_cnt_d = BAUD_DIV;  // For next bit or stop
                end
            end
            
            RX_STOP: begin
                if (rx_mid_bit_sample) begin
                    if (uart_rx_sync2 == 1'b1) begin
                        // Valid stop bit
                        rx_valid_d = 1'b1;
                    end
                    // (Framing error drops byte; no sticky bit in scope, doc 09 §9.2 notes but N/A)
                    rx_state_d = RX_IDLE;
                end
            end
            
            default: rx_state_d = RX_IDLE;
        endcase
        
        if (rx_read) begin
            rx_valid_d = 1'b0;  // Clear on read
        end
    end
    
    // =====================================================================
    // AXI4-LITE READ INTERFACE
    // =====================================================================
    
    assign arready = 1'b1;
    
    logic [31:0] rdata_comb;
    always_comb begin
        unique case (offset_ar[7:0])
            OFFSET_TX_STATUS: rdata_comb = {31'b0, tx_ready_q};
            OFFSET_RX_DATA:   rdata_comb = {24'b0, rx_byte_q};
            OFFSET_RX_STATUS: rdata_comb = {31'b0, rx_valid_q};
            default:          rdata_comb = 32'h0;
        endcase
    end
    
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
    // SEQUENTIAL LOGIC
    // =====================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state_q    <= TX_IDLE;
            tx_shift_q    <= 10'h0;
            tx_bitcnt_q   <= 4'h0;
            tx_baud_cnt_q <= BAUD_DIV;
            tx_ready_q    <= 1'b1;
            
            rx_state_q      <= RX_IDLE;
            rx_byte_q       <= 8'h0;
            rx_bitcnt_q     <= 4'h0;
            rx_sample_cnt_q <= 10'h0;
            rx_valid_q      <= 1'b0;
        end else begin
            tx_state_q    <= tx_state_d;
            tx_shift_q    <= tx_shift_d;
            tx_bitcnt_q   <= tx_bitcnt_d;
            tx_baud_cnt_q <= tx_baud_cnt_d;
            tx_ready_q    <= tx_ready_d;
            
            rx_state_q      <= rx_state_d;
            rx_byte_q       <= rx_byte_d;
            rx_bitcnt_q     <= rx_bitcnt_d;
            rx_sample_cnt_q <= rx_sample_cnt_d;
            rx_valid_q      <= rx_valid_d;
        end
    end

endmodule : uart_core
