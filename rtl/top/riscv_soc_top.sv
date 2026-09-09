/**
 * @module riscv_soc_top.sv
 * @brief Top-Level RISC-V Dual-Core SoC Integration (T3.1)
 *
 * Source: logic_design/12_integration_logic.md
 *
 * Purpose: Instantiate all 16 RTL modules and wire 97 inter-module signals.
 * Complete system integration: cores, caches, coherence, arbiter, decoder, peripherals.
 *
 * Architecture:
 *   - 2 RV32I cores (core0, core1) with async I-SRAM instruction fetch
 *   - 2 L1 data caches (4-line direct-mapped) with 13-state managers
 *   - 1 coherence controller (4-state FSM, I/S/M protocol, 8-entry mirror)
 *   - 1 AXI4-Lite arbiter (2-master round-robin, core 0 priority at reset)
 *   - 1 AXI4-Lite decoder (4 slaves + DECERR for unmapped addresses)
 *   - 4 AXI4-Lite slaves:
 *     • shared_sram (4 KB data memory)
 *     • mmio_regs (counters, status, control, doorbell)
 *     • uart_core (115200 8N1 TX/RX)
 *     • gpio_led (8 LED outputs with event stretchers)
 *
 * Clock & Reset:
 *   - Single clock domain (50 MHz nominal, 20 MHz ASIC, configurable)
 *   - Raw async active-low rst_n → 2-FF synchronizer → rst_sync_n (distributed)
 *   - All sequential logic: always_ff @(posedge clk or negedge rst_sync_n)
 *
 * Integration Checklist: 97 signals from doc 12 §12.2
 *   - Core domain (×2): 16 signals each = 32 total
 *   - AXI fabric: 17 signals per port × 3 ports = 51 total
 *   - Coherence sideband (×2): 8 signals each = 16 total
 *   - Events: 8 signals
 *   - Peripheral I/O: UART + GPIO (external pins)
 */

module riscv_soc_top (
    input  logic        clk,
    input  logic        rst_n,
    
    // UART interface (external)
    output logic        uart_tx,
    input  logic        uart_rx,
    
    // GPIO/LED interface (external)
    output logic [7:0]  led
);

    // =====================================================================
    // RESET SYNCHRONIZER (doc 12 §12.3)
    // =====================================================================
    // 2-FF async-clear synchronizer: raw rst_n → rst_sync_n (distributed)
    
    logic rst_sync_n_1, rst_sync_n;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rst_sync_n_1 <= 1'b0;
            rst_sync_n   <= 1'b0;
        end else begin
            rst_sync_n_1 <= 1'b1;
            rst_sync_n   <= rst_sync_n_1;
        end
    end
    
    // =====================================================================
    // CORE DOMAIN SIGNALS (PER-CORE LOOP)
    // =====================================================================
    // Generate block for core0 + core1 to avoid duplication
    // Each core gets: i_sram, d_cache, d_cache_mgr, coherence sideband
    
    // Per-core signal declarations
    logic [31:0] c_imem_addr   [0:1];
    logic [31:0] c_imem_rdata  [0:1];
    logic        c_dmem_req    [0:1];
    logic        c_dmem_we     [0:1];
    logic [31:0] c_dmem_addr   [0:1];
    logic [31:0] c_dmem_wdata  [0:1];
    logic [3:0]  c_dmem_wmask  [0:1];
    logic [31:0] c_dmem_rdata  [0:1];
    logic        c_dmem_ack    [0:1];
    logic        c_dmem_err    [0:1];
    
    // =====================================================================
    // AXI FABRIC SIGNALS (CACHE MANAGERS → ARBITER → DECODER → SLAVES)
    // =====================================================================
    
    // Master ports (from cache managers)
    logic        m_awvalid [0:1];
    logic [31:0] m_awaddr  [0:1];
    logic        m_awready [0:1];
    logic        m_wvalid  [0:1];
    logic [31:0] m_wdata   [0:1];
    logic [3:0]  m_wstrb   [0:1];
    logic        m_wready  [0:1];
    logic        m_bvalid  [0:1];
    logic [1:0]  m_bresp   [0:1];
    logic        m_bready  [0:1];
    logic        m_arvalid [0:1];
    logic [31:0] m_araddr  [0:1];
    logic        m_arready [0:1];
    logic        m_rvalid  [0:1];
    logic [31:0] m_rdata   [0:1];
    logic [1:0]  m_rresp   [0:1];
    logic        m_rready  [0:1];
    
    // Arbitration requests
    logic        m_bus_req [0:1];
    
    // Shared slave port (arbiter output → decoder input)
    logic        s_awvalid;
    logic [31:0] s_awaddr;
    logic        s_awready;
    logic        s_wvalid;
    logic [31:0] s_wdata;
    logic [3:0]  s_wstrb;
    logic        s_wready;
    logic        s_bvalid;
    logic [1:0]  s_bresp;
    logic        s_bready;
    logic        s_arvalid;
    logic [31:0] s_araddr;
    logic        s_arready;
    logic        s_rvalid;
    logic [31:0] s_rdata;
    logic [1:0]  s_rresp;
    logic        s_rready;
    
    // Slave select signals (from decoder)
    logic        sel_sram, sel_mmio, sel_uart, sel_gpio;
    
    // SRAM slave port
    logic        sram_awvalid, sram_wvalid, sram_bvalid, sram_arvalid, sram_rvalid;
    logic [31:0] sram_awaddr, sram_wdata, sram_rdata, sram_araddr;
    logic [3:0]  sram_wstrb;
    logic [1:0]  sram_bresp, sram_rresp;
    logic        sram_awready, sram_wready, sram_arready, sram_rready, sram_bready;
    
    // MMIO slave port
    logic        mmio_awvalid, mmio_wvalid, mmio_bvalid, mmio_arvalid, mmio_rvalid;
    logic [31:0] mmio_awaddr, mmio_wdata, mmio_rdata, mmio_araddr;
    logic [3:0]  mmio_wstrb;
    logic [1:0]  mmio_bresp, mmio_rresp;
    logic        mmio_awready, mmio_wready, mmio_arready, mmio_rready, mmio_bready;
    
    // UART slave port
    logic        uart_awvalid, uart_wvalid, uart_bvalid, uart_arvalid, uart_rvalid;
    logic [31:0] uart_awaddr, uart_wdata, uart_rdata, uart_araddr;
    logic [3:0]  uart_wstrb;
    logic [1:0]  uart_bresp, uart_rresp;
    logic        uart_awready, uart_wready, uart_arready, uart_rready, uart_bready;
    
    // GPIO slave port
    logic        gpio_awvalid, gpio_wvalid, gpio_bvalid, gpio_arvalid, gpio_rvalid;
    logic [31:0] gpio_awaddr, gpio_wdata, gpio_rdata, gpio_araddr;
    logic [3:0]  gpio_wstrb;
    logic [1:0]  gpio_bresp, gpio_rresp;
    logic        gpio_awready, gpio_wready, gpio_arready, gpio_rready, gpio_bready;
    
    // =====================================================================
    // COHERENCE SIDEBAND SIGNALS (PER-CORE)
    // =====================================================================
    
    logic        coh_write_notify [0:1];
    logic [31:0] coh_write_addr   [0:1];
    logic        coh_accept       [0:1];
    logic        coh_fill_notify  [0:1];
    logic [1:0]  coh_fill_idx     [0:1];
    logic        coh_inv_valid    [0:1];
    logic [1:0]  coh_inv_idx      [0:1];
    logic        coh_inv_ack      [0:1];
    
    // Line state export — intermediate packed signals from d_cache
    logic [3:0]   dcache_line_valid_packed [0:1];        // [core] packed 4-bit valid
    logic [7:0]   dcache_coh_state_packed [0:1];        // [core] packed 8-bit state (2-bit per line)
    
    // Packed signals for coherence_ctrl (convert unpacked to packed)
    logic [7:0]   coh_state0_packed, coh_state1_packed;
    logic [3:0]   coh_valid0_packed, coh_valid1_packed;
    
    // Unpacked arrays for coherence_ctrl and internal use
    logic [1:0]  dcache_coh_state [0:1][3:0];           // [core][line] = 2-bit I/S/M
    logic        dcache_line_valid [0:1][3:0];          // [core][line] = 1-bit valid
    
    // Pack/unpack conversion - flatten intermediate packed signals
    generate
      for (genvar i = 0; i < 4; i++) begin : unpack_state_core0
        assign dcache_coh_state[0][i] = dcache_coh_state_packed[0][i*2 +: 2];
        assign dcache_line_valid[0][i] = dcache_line_valid_packed[0][i];
      end
      for (genvar i = 0; i < 4; i++) begin : unpack_state_core1
        assign dcache_coh_state[1][i] = dcache_coh_state_packed[1][i*2 +: 2];
        assign dcache_line_valid[1][i] = dcache_line_valid_packed[1][i];
      end
      // Pack for coherence_ctrl
      for (genvar i = 0; i < 4; i++) begin : pack_for_coh
        assign coh_state0_packed[i*2 +: 2] = dcache_coh_state[0][i];
        assign coh_valid0_packed[i]         = dcache_line_valid[0][i];
        assign coh_state1_packed[i*2 +: 2] = dcache_coh_state[1][i];
        assign coh_valid1_packed[i]         = dcache_line_valid[1][i];
      end
    endgenerate
    
    // =====================================================================
    // EVENT SIGNALS
    // =====================================================================
    
    logic        inv_fire;
    logic [15:0] coh_status;
    logic        coh_enable, err_sticky;
    
    // Per-core d_cache ↔ d_cache_mgr interconnect
    // Cache hit/miss/data outputs (from d_cache, inputs to d_cache_mgr)
    logic        dc_hit       [0:1];
    logic        dc_miss      [0:1];
    logic [1:0]  dc_hit_idx   [0:1];
    logic [31:0] dc_hit_data  [0:1];
    // Cache write-back outputs (from d_cache_mgr, inputs to d_cache)
    logic [1:0]  dc_wr_idx    [0:1];
    logic [31:0] dc_wr_data   [0:1];
    logic [27:0] dc_wr_tag    [0:1];
    logic [1:0]  dc_wr_state  [0:1];
    logic        dc_wr_valid  [0:1];
    logic [3:0]  dc_wr_we     [0:1];  // 1-hot, matches wr_we[LINES-1:0]
    // Event outputs from d_cache_mgr
    logic        dc_hit_event  [0:1];
    logic        dc_miss_event [0:1];
    logic        dc_err_event  [0:1];
    
    // =====================================================================
    // INSTANTIATE CORES + I-SRAM + D-CACHE + PERIPHERALS (GENERATE LOOP)
    // =====================================================================
    
    generate
        for (genvar c = 0; c < 2; c++) begin : per_core
            
            // -----------------------------------------------------------
            // RV32I Core
            // -----------------------------------------------------------
            rv32i_core #(
                .RESET_PC(32'h0)
            ) u_core (
                .clk(clk),
                .rst_n(rst_sync_n),
                
                // Instruction memory
                .imem_addr(c_imem_addr[c]),
                .imem_rdata(c_imem_rdata[c]),
                
                // Data memory
                .dmem_req(c_dmem_req[c]),
                .dmem_we(c_dmem_we[c]),
                .dmem_addr(c_dmem_addr[c]),
                .dmem_wdata(c_dmem_wdata[c]),
                .dmem_wmask(c_dmem_wmask[c]),
                .dmem_rdata(c_dmem_rdata[c]),
                .dmem_ack(c_dmem_ack[c]),
                .dmem_err(c_dmem_err[c])
            );
            
            // -----------------------------------------------------------
            // Instruction SRAM (async read, 256 × 32, 1 KB per core)
            // -----------------------------------------------------------
            i_sram #(
                .DEPTH(256)
                // No ASYNC_READ parameter — i_sram is always async-read
            ) u_isram (
                .clk(clk),
                .rst_n(rst_sync_n),
                
                // Read port (async, combinational)
                .raddr(c_imem_addr[c][7:0]),  // addr[7:0] selects word (DEPTH=256)
                .rdata(c_imem_rdata[c]),
                
                // Write port tied off (initialization only, not used at runtime)
                .waddr(8'h0),
                .wdata(32'h0),
                .we(1'b0)
            );
            
            // -----------------------------------------------------------
            // Data Cache (4-line direct-mapped)
            // -----------------------------------------------------------
            d_cache #(
                .LINES(4)
                // No CORE_ID parameter on d_cache
            ) u_dcache (
                .clk(clk),
                .rst_n(rst_sync_n),
                
                // Request side
                .req_addr(c_dmem_addr[c]),
                .hit(dc_hit[c]),
                .miss(dc_miss[c]),
                .hit_idx(dc_hit_idx[c]),
                .hit_data(dc_hit_data[c]),
                
                // Line state export (packed from d_cache)
                .line_valid(dcache_line_valid_packed[c]),
                .line_coh_state(dcache_coh_state_packed[c]),
                .line_req_idx(),           // not used at top level
                .line_out(),               // debug port, not needed at top level
                
                // Write side (from cache manager)
                .wr_idx(dc_wr_idx[c]),
                .wr_data(dc_wr_data[c]),
                .wr_tag(dc_wr_tag[c]),
                .wr_state(dc_wr_state[c]),
                .wr_valid(dc_wr_valid[c]),
                .wr_we(dc_wr_we[c]),
                
                // Invalidation from coherence controller
                .inv_idx(coh_inv_idx[c]),
                .inv_we(coh_inv_valid[c])
            );
            
            // -----------------------------------------------------------
            // Data Cache Manager (13-state FSM)
            // -----------------------------------------------------------
            d_cache_mgr #(
                .CORE_ID(c)
                // No LINES parameter on d_cache_mgr
            ) u_dcmgr (
                .clk(clk),
                .rst_n(rst_sync_n),
                
                // Core-side
                .dmem_req(c_dmem_req[c]),
                .dmem_we(c_dmem_we[c]),
                .dmem_addr(c_dmem_addr[c]),
                .dmem_wdata(c_dmem_wdata[c]),
                .dmem_wmask(c_dmem_wmask[c]),
                .dmem_rdata(c_dmem_rdata[c]),
                .dmem_ack(c_dmem_ack[c]),
                .dmem_err(c_dmem_err[c]),
                
                // Cache storage interface (d_cache outputs → d_cache_mgr inputs)
                .cache_hit(dc_hit[c]),
                .cache_miss(dc_miss[c]),
                .cache_hit_idx(dc_hit_idx[c]),
                .cache_hit_data(dc_hit_data[c]),
                
                // Cache write-back (d_cache_mgr outputs → d_cache inputs)
                .cache_wr_idx(dc_wr_idx[c]),
                .cache_wr_data(dc_wr_data[c]),
                .cache_wr_tag(dc_wr_tag[c]),
                .cache_wr_state(dc_wr_state[c]),
                .cache_wr_valid(dc_wr_valid[c]),
                .cache_wr_we(dc_wr_we[c]),
                
                // AXI4-Lite master port
                .m_awvalid(m_awvalid[c]),
                .m_awaddr(m_awaddr[c]),
                .m_awready(m_awready[c]),
                .m_wvalid(m_wvalid[c]),
                .m_wdata(m_wdata[c]),
                .m_wstrb(m_wstrb[c]),
                .m_wready(m_wready[c]),
                .m_bvalid(m_bvalid[c]),
                .m_bresp(m_bresp[c]),
                .m_bready(m_bready[c]),
                .m_arvalid(m_arvalid[c]),
                .m_araddr(m_araddr[c]),
                .m_arready(m_arready[c]),
                .m_rvalid(m_rvalid[c]),
                .m_rdata(m_rdata[c]),
                .m_rresp(m_rresp[c]),
                .m_rready(m_rready[c]),
                
                // Arbitration
                .bus_req(m_bus_req[c]),
                
                // Coherence sideband
                .coh_write_notify(coh_write_notify[c]),
                .coh_write_addr(coh_write_addr[c]),
                .coh_accept(coh_accept[c]),
                .coh_fill_notify(coh_fill_notify[c]),
                .coh_fill_idx(coh_fill_idx[c]),
                .coh_inv_valid(coh_inv_valid[c]),
                .coh_inv_idx(coh_inv_idx[c]),
                .coh_inv_ack(coh_inv_ack[c]),
                
                // Event outputs
                .hit_event(dc_hit_event[c]),
                .miss_event(dc_miss_event[c]),
                .err_event(dc_err_event[c])
            );
            
        end : per_core
    endgenerate
    
    // =====================================================================
    // COHERENCE CONTROLLER (1 instance, services both cores)
    // =====================================================================
    // coherence_ctrl has NO parameters. All ports are individual per-core
    // signals — NOT packed vectors. Map arrays [0] and [1] explicitly.
    
    coherence_ctrl u_coh (
        .clk(clk),
        .rst_n(rst_sync_n),
        
        // Write notifications (per core, individual ports)
        .write_notify0(coh_write_notify[0]),
        .write_addr0(coh_write_addr[0]),
        .write_notify1(coh_write_notify[1]),
        .write_addr1(coh_write_addr[1]),
        .coh_accept0(coh_accept[0]),
        .coh_accept1(coh_accept[1]),
        
        // Fill notifications (per core, individual ports)
        .fill_notify0(coh_fill_notify[0]),
        .fill_idx0(coh_fill_idx[0]),
        .fill_notify1(coh_fill_notify[1]),
        .fill_idx1(coh_fill_idx[1]),
        
        // Invalidation dispatch (per core, individual ports)
        .inv_valid0(coh_inv_valid[0]),
        .inv_idx0(coh_inv_idx[0]),
        .inv_ack0(coh_inv_ack[0]),
        .inv_valid1(coh_inv_valid[1]),
        .inv_idx1(coh_inv_idx[1]),
        .inv_ack1(coh_inv_ack[1]),
        
        // Actual cache line states (packed for synthesis)
        .state0_i(coh_state0_packed),
        .valid0_i(coh_valid0_packed),
        .state1_i(coh_state1_packed),
        .valid1_i(coh_valid1_packed),
        
        // Control & status (no _i/_o suffixes in coherence_ctrl port list)
        .coh_enable(coh_enable),
        .inv_fire(inv_fire),
        .coh_status(coh_status)
    );
    
    // =====================================================================
    // AXI4-LITE ARBITER (2-master round-robin)
    // =====================================================================
    
    axi_lite_arbiter u_arb (
        .clk(clk),
        .rst_n(rst_sync_n),
        
        // Master 0
        .req0(m_bus_req[0]),
        .awvalid0(m_awvalid[0]),
        .awaddr0(m_awaddr[0]),
        .awready0(m_awready[0]),
        .wvalid0(m_wvalid[0]),
        .wdata0(m_wdata[0]),
        .wstrb0(m_wstrb[0]),
        .wready0(m_wready[0]),
        .bvalid0(m_bvalid[0]),
        .bresp0(m_bresp[0]),
        .bready0(m_bready[0]),
        .arvalid0(m_arvalid[0]),
        .araddr0(m_araddr[0]),
        .arready0(m_arready[0]),
        .rvalid0(m_rvalid[0]),
        .rdata0(m_rdata[0]),
        .rresp0(m_rresp[0]),
        .rready0(m_rready[0]),
        
        // Master 1
        .req1(m_bus_req[1]),
        .awvalid1(m_awvalid[1]),
        .awaddr1(m_awaddr[1]),
        .awready1(m_awready[1]),
        .wvalid1(m_wvalid[1]),
        .wdata1(m_wdata[1]),
        .wstrb1(m_wstrb[1]),
        .wready1(m_wready[1]),
        .bvalid1(m_bvalid[1]),
        .bresp1(m_bresp[1]),
        .bready1(m_bready[1]),
        .arvalid1(m_arvalid[1]),
        .araddr1(m_araddr[1]),
        .arready1(m_arready[1]),
        .rvalid1(m_rvalid[1]),
        .rdata1(m_rdata[1]),
        .rresp1(m_rresp[1]),
        .rready1(m_rready[1]),
        
        // Shared slave port
        .awvalid_s(s_awvalid),
        .awaddr_s(s_awaddr),
        .awready_s(s_awready),
        .wvalid_s(s_wvalid),
        .wdata_s(s_wdata),
        .wstrb_s(s_wstrb),
        .wready_s(s_wready),
        .bvalid_s(s_bvalid),
        .bresp_s(s_bresp),
        .bready_s(s_bready),
        .arvalid_s(s_arvalid),
        .araddr_s(s_araddr),
        .arready_s(s_arready),
        .rvalid_s(s_rvalid),
        .rdata_s(s_rdata),
        .rresp_s(s_rresp),
        .rready_s(s_rready)
    );
    
    // =====================================================================
    // AXI4-LITE DECODER (Address routing + DECERR)
    // =====================================================================
    
    axi_lite_decoder u_dec (
        .clk(clk),
        .rst_n(rst_sync_n),
        
        // Master side (from arbiter)
        .awvalid_m(s_awvalid),
        .awaddr_m(s_awaddr),
        .awready_m(s_awready),
        .wvalid_m(s_wvalid),
        .wdata_m(s_wdata),
        .wstrb_m(s_wstrb),
        .wready_m(s_wready),
        .bvalid_m(s_bvalid),
        .bresp_m(s_bresp),
        .bready_m(s_bready),
        .arvalid_m(s_arvalid),
        .araddr_m(s_araddr),
        .arready_m(s_arready),
        .rvalid_m(s_rvalid),
        .rdata_m(s_rdata),
        .rresp_m(s_rresp),
        .rready_m(s_rready),
        
        // SRAM slave
        .sel_sram(sel_sram),
        .awvalid_sram(sram_awvalid),
        .awaddr_sram(sram_awaddr),
        .awready_sram(sram_awready),
        .wvalid_sram(sram_wvalid),
        .wdata_sram(sram_wdata),
        .wstrb_sram(sram_wstrb),
        .wready_sram(sram_wready),
        .bvalid_sram(sram_bvalid),
        .bresp_sram(sram_bresp),
        .bready_sram(sram_bready),
        .arvalid_sram(sram_arvalid),
        .araddr_sram(sram_araddr),
        .arready_sram(sram_arready),
        .rvalid_sram(sram_rvalid),
        .rdata_sram(sram_rdata),
        .rresp_sram(sram_rresp),
        .rready_sram(sram_rready),
        
        // MMIO slave
        .sel_mmio(sel_mmio),
        .awvalid_mmio(mmio_awvalid),
        .awaddr_mmio(mmio_awaddr),
        .awready_mmio(mmio_awready),
        .wvalid_mmio(mmio_wvalid),
        .wdata_mmio(mmio_wdata),
        .wstrb_mmio(mmio_wstrb),
        .wready_mmio(mmio_wready),
        .bvalid_mmio(mmio_bvalid),
        .bresp_mmio(mmio_bresp),
        .bready_mmio(mmio_bready),
        .arvalid_mmio(mmio_arvalid),
        .araddr_mmio(mmio_araddr),
        .arready_mmio(mmio_arready),
        .rvalid_mmio(mmio_rvalid),
        .rdata_mmio(mmio_rdata),
        .rresp_mmio(mmio_rresp),
        .rready_mmio(mmio_rready),
        
        // UART slave
        .sel_uart(sel_uart),
        .awvalid_uart(uart_awvalid),
        .awaddr_uart(uart_awaddr),
        .awready_uart(uart_awready),
        .wvalid_uart(uart_wvalid),
        .wdata_uart(uart_wdata),
        .wstrb_uart(uart_wstrb),
        .wready_uart(uart_wready),
        .bvalid_uart(uart_bvalid),
        .bresp_uart(uart_bresp),
        .bready_uart(uart_bready),
        .arvalid_uart(uart_arvalid),
        .araddr_uart(uart_araddr),
        .arready_uart(uart_arready),
        .rvalid_uart(uart_rvalid),
        .rdata_uart(uart_rdata),
        .rresp_uart(uart_rresp),
        .rready_uart(uart_rready),
        
        // GPIO slave
        .sel_gpio(sel_gpio),
        .awvalid_gpio(gpio_awvalid),
        .awaddr_gpio(gpio_awaddr),
        .awready_gpio(gpio_awready),
        .wvalid_gpio(gpio_wvalid),
        .wdata_gpio(gpio_wdata),
        .wstrb_gpio(gpio_wstrb),
        .wready_gpio(gpio_wready),
        .bvalid_gpio(gpio_bvalid),
        .bresp_gpio(gpio_bresp),
        .bready_gpio(gpio_bready),
        .arvalid_gpio(gpio_arvalid),
        .araddr_gpio(gpio_araddr),
        .arready_gpio(gpio_arready),
        .rvalid_gpio(gpio_rvalid),
        .rdata_gpio(gpio_rdata),
        .rresp_gpio(gpio_rresp),
        .rready_gpio(gpio_rready)
    );
    
    // =====================================================================
    // AXI4-LITE SLAVES (4 instances)
    // =====================================================================
    
    // Shared Data SRAM (4 KB, 1024 × 32)
    shared_sram u_sram (
        .clk(clk),
        .rst_n(rst_sync_n),
        
        .awvalid(sram_awvalid),
        .awaddr(sram_awaddr),
        .awready(sram_awready),
        .wvalid(sram_wvalid),
        .wdata(sram_wdata),
        .wstrb(sram_wstrb),
        .wready(sram_wready),
        .bvalid(sram_bvalid),
        .bresp(sram_bresp),
        .bready(sram_bready),
        .arvalid(sram_arvalid),
        .araddr(sram_araddr),
        .arready(sram_arready),
        .rvalid(sram_rvalid),
        .rdata(sram_rdata),
        .rresp(sram_rresp),
        .rready(sram_rready)
    );
    
    // MMIO Registers
    mmio_regs u_mmio (
        .clk(clk),
        .rst_n(rst_sync_n),
        
        // AXI slave
        .awvalid(mmio_awvalid),
        .awaddr(mmio_awaddr),
        .awready(mmio_awready),
        .wvalid(mmio_wvalid),
        .wdata(mmio_wdata),
        .wstrb(mmio_wstrb),
        .wready(mmio_wready),
        .bvalid(mmio_bvalid),
        .bresp(mmio_bresp),
        .bready(mmio_bready),
        .arvalid(mmio_arvalid),
        .araddr(mmio_araddr),
        .arready(mmio_arready),
        .rvalid(mmio_rvalid),
        .rdata(mmio_rdata),
        .rresp(mmio_rresp),
        .rready(mmio_rready),
        
        // Event inputs — use dc_hit_event/miss_event/err_event from managers
        .hit0(dc_hit_event[0]),
        .hit1(dc_hit_event[1]),
        .miss0(dc_miss_event[0]),
        .miss1(dc_miss_event[1]),
        .err0(dc_err_event[0]),
        .err1(dc_err_event[1]),
        .inv_fire(inv_fire),
        .coh_status(coh_status),
        
        // Control outputs
        .coh_enable(coh_enable),
        .err_sticky(err_sticky),
        
        // Doorbell output (missing in original instantiation)
        .doorbell()             // not consumed at top level; left unconnected
    );
    
    // UART Core (115200 8N1)
    uart_core u_uart (
        .clk(clk),
        .rst_n(rst_sync_n),
        
        // AXI slave
        .awvalid(uart_awvalid),
        .awaddr(uart_awaddr),
        .awready(uart_awready),
        .wvalid(uart_wvalid),
        .wdata(uart_wdata),
        .wstrb(uart_wstrb),
        .wready(uart_wready),
        .bvalid(uart_bvalid),
        .bresp(uart_bresp),
        .bready(uart_bready),
        .arvalid(uart_arvalid),
        .araddr(uart_araddr),
        .arready(uart_arready),
        .rvalid(uart_rvalid),
        .rdata(uart_rdata),
        .rresp(uart_rresp),
        .rready(uart_rready),
        
        // UART pins
        .uart_tx(uart_tx),
        .uart_rx(uart_rx)
    );
    
    // GPIO / LED Controller
    gpio_led u_gpio (
        .clk(clk),
        .rst_n(rst_sync_n),
        
        // AXI slave
        .awvalid(gpio_awvalid),
        .awaddr(gpio_awaddr),
        .awready(gpio_awready),
        .wvalid(gpio_wvalid),
        .wdata(gpio_wdata),
        .wstrb(gpio_wstrb),
        .wready(gpio_wready),
        .bvalid(gpio_bvalid),
        .bresp(gpio_bresp),
        .bready(gpio_bready),
        .arvalid(gpio_arvalid),
        .araddr(gpio_araddr),
        .arready(gpio_arready),
        .rvalid(gpio_rvalid),
        .rdata(gpio_rdata),
        .rresp(gpio_rresp),
        .rready(gpio_rready),
        
        // Event inputs — use dc_hit_event/miss_event from cache managers
        .dmem_ack0(c_dmem_ack[0]),
        .dmem_ack1(c_dmem_ack[1]),
        .inv_fire(inv_fire),
        .hit0(dc_hit_event[0]),
        .hit1(dc_hit_event[1]),
        .miss0(dc_miss_event[0]),
        .miss1(dc_miss_event[1]),
        .err_sticky(err_sticky),
        
        // LED output
        .led(led)
    );

endmodule : riscv_soc_top
