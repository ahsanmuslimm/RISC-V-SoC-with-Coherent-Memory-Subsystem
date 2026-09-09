/**
 * @module gpio_led.sv
 * @brief GPIO/LED Module (T2.13)
 *
 * Source: logic_design/09_peripherals.md §9.3–9.4
 *
 * Purpose: Drive 8 LED outputs. Top 2 bits (LED7–LED6) are software-controlled via LED_REG.
 * Bottom 6 bits are event-driven with pulse stretchers (R8):
 *   LED0: core0 heartbeat (dmem_ack0 stretched)
 *   LED1: core1 heartbeat (dmem_ack1 stretched)
 *   LED2: coherence event (inv_fire stretched)
 *   LED3: cache hit (hit0|hit1 stretched)
 *   LED4: cache miss (miss0|miss1 stretched)
 *   LED5: error (err_sticky level)
 *   LED6–7: software (LED_REG[7:6])
 *
 * Stretcher (for R8): On event pulse → load counter 2²²−1 → countdown → LED high while counter ≠ 0
 * At 50 MHz, 2²² = 4194304 cycles ≈ 84 ms → human-visible blink
 *
 * Base address: 0x0001_0200
 * Register: LED_REG (RW, bits[7:6] → LED7–6, bits[5:0] unused)
 */

module gpio_led (
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
    
    // Event inputs
    input  logic        dmem_ack0,
    input  logic        dmem_ack1,
    input  logic        inv_fire,
    input  logic        hit0,
    input  logic        hit1,
    input  logic        miss0,
    input  logic        miss1,
    input  logic        err_sticky,
    
    // LED outputs
    output logic [7:0]  led
);

    // Register offset
    localparam OFFSET_LED_REG = 8'h00;
    
    // Extract offset from address
    logic [7:0] offset_aw, offset_ar;
    assign offset_aw = awaddr[7:0];
    assign offset_ar = araddr[7:0];
    
    // Stretcher constant: 2²²-1 cycles ≈ 84 ms @ 50 MHz
    // Note: write 4194303 directly — 22'd4194304 would overflow a 22-bit literal
    localparam STRETCH_CNT = 22'd4194303;
    
    // =====================================================================
    // AXI4-LITE WRITE INTERFACE
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
    // SOFTWARE-CONTROLLED REGISTER (LED7–6)
    // =====================================================================
    
    logic [7:6] sw_led_d, sw_led_q;
    
    always_comb begin
        if (write_txn && (offset_aw[7:0] == OFFSET_LED_REG)) begin
            sw_led_d = wdata[7:6];
        end else begin
            sw_led_d = sw_led_q;
        end
    end
    
    // =====================================================================
    // PULSE STRETCHERS (LED0–5, from R8)
    // =====================================================================
    // Pattern: on event → load counter STRETCH_CNT → countdown → LED high
    
    // LED0: dmem_ack0 heartbeat
    logic [21:0] led0_cnt_d, led0_cnt_q;
    logic led0_active;
    
    assign led0_active = (led0_cnt_q != 22'h0);
    
    always_comb begin
        if (dmem_ack0) begin
            led0_cnt_d = STRETCH_CNT;  // Reload on event
        end else if (led0_cnt_q > 22'h0) begin
            led0_cnt_d = led0_cnt_q - 22'h1;
        end else begin
            led0_cnt_d = 22'h0;
        end
    end
    
    // LED1: dmem_ack1 heartbeat
    logic [21:0] led1_cnt_d, led1_cnt_q;
    logic led1_active;
    
    assign led1_active = (led1_cnt_q != 22'h0);
    
    always_comb begin
        if (dmem_ack1) begin
            led1_cnt_d = STRETCH_CNT;
        end else if (led1_cnt_q > 22'h0) begin
            led1_cnt_d = led1_cnt_q - 22'h1;
        end else begin
            led1_cnt_d = 22'h0;
        end
    end
    
    // LED2: coherence event (inv_fire)
    logic [21:0] led2_cnt_d, led2_cnt_q;
    logic led2_active;
    
    assign led2_active = (led2_cnt_q != 22'h0);
    
    always_comb begin
        if (inv_fire) begin
            led2_cnt_d = STRETCH_CNT;
        end else if (led2_cnt_q > 22'h0) begin
            led2_cnt_d = led2_cnt_q - 22'h1;
        end else begin
            led2_cnt_d = 22'h0;
        end
    end
    
    // LED3: cache hit (hit0 | hit1)
    logic [21:0] led3_cnt_d, led3_cnt_q;
    logic led3_active;
    logic hit_event = hit0 | hit1;
    
    assign led3_active = (led3_cnt_q != 22'h0);
    
    always_comb begin
        if (hit_event) begin
            led3_cnt_d = STRETCH_CNT;
        end else if (led3_cnt_q > 22'h0) begin
            led3_cnt_d = led3_cnt_q - 22'h1;
        end else begin
            led3_cnt_d = 22'h0;
        end
    end
    
    // LED4: cache miss (miss0 | miss1)
    logic [21:0] led4_cnt_d, led4_cnt_q;
    logic led4_active;
    logic miss_event = miss0 | miss1;
    
    assign led4_active = (led4_cnt_q != 22'h0);
    
    always_comb begin
        if (miss_event) begin
            led4_cnt_d = STRETCH_CNT;
        end else if (led4_cnt_q > 22'h0) begin
            led4_cnt_d = led4_cnt_q - 22'h1;
        end else begin
            led4_cnt_d = 22'h0;
        end
    end
    
    // LED5: error (sticky level signal, not stretched)
    // This is a direct level (on when err_sticky=1), not a pulse-stretched event
    logic led5_active;
    assign led5_active = err_sticky;
    
    // =====================================================================
    // AXI4-LITE READ INTERFACE
    // =====================================================================
    
    assign arready = 1'b1;
    
    logic [31:0] rdata_comb;
    always_comb begin
        if (offset_ar[7:0] == OFFSET_LED_REG) begin
            rdata_comb = {sw_led_q, 6'b0};  // LED7–6 readable, bits[5:0] = 0
        end else begin
            rdata_comb = 32'h0;
        end
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
    // LED OUTPUT ASSIGNMENT (merge software + event-stretched)
    // =====================================================================
    
    assign led[0] = led0_active;
    assign led[1] = led1_active;
    assign led[2] = led2_active;
    assign led[3] = led3_active;
    assign led[4] = led4_active;
    assign led[5] = led5_active;
    assign led[7:6] = sw_led_q;
    
    // =====================================================================
    // SEQUENTIAL LOGIC
    // =====================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sw_led_q    <= 2'b0;
            
            led0_cnt_q  <= 22'h0;
            led1_cnt_q  <= 22'h0;
            led2_cnt_q  <= 22'h0;
            led3_cnt_q  <= 22'h0;
            led4_cnt_q  <= 22'h0;
        end else begin
            sw_led_q    <= sw_led_d;
            
            led0_cnt_q  <= led0_cnt_d;
            led1_cnt_q  <= led1_cnt_d;
            led2_cnt_q  <= led2_cnt_d;
            led3_cnt_q  <= led3_cnt_d;
            led4_cnt_q  <= led4_cnt_d;
        end
    end

endmodule : gpio_led
