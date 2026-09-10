/**
 * @module tb_directed.sv
 * @brief Directed Testbench for RISC-V SoC (T3.3–T3.6)
 *
 * Source: logic_design/13_working_logic_scenarios.md §13.1–13.9
 *
 * Purpose: 10 directed test scenarios covering:
 *   1. Reset verification (AC-9)
 *   2. Single-core load/store
 *   3. Cache hit detection
 *   4. Cache miss + AXI fill
 *   5. Cross-core coherence write-invalidate demo
 *   6. Simultaneous writes (arbiter fairness)
 *   7. Multiple cache lines (no spurious invalidation)
 *   8. Uncached MMIO access (R9 bypass)
 *   9. Unmapped address (DECERR error)
 *  10. Counter increments (HIT/MISS/INV)
 *
 * Verification Strategy:
 *   - Each test is atomic and independent
 *   - Register monitoring for key state machines
 *   - Assertion checklist per test
 */

`timescale 1ns/1ps

module tb_directed ();

    // =====================================================================
    // CLOCK & RESET GENERATION
    // =====================================================================
    
    logic        clk;
    logic        rst_n;
    logic        uart_tx, uart_rx;
    logic [7:0]  led;
    
    // Clock: 50 MHz (20 ns period)
    always begin
        clk = 1'b0;
        #10 ns;
        clk = 1'b1;
        #10 ns;
    end
    
    // Reset: async assert for 3 cycles, then release
    initial begin
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end
    
    // =====================================================================
    // INSTANTIATE SoC
    // =====================================================================
    
    riscv_soc_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .uart_tx(uart_tx),
        .uart_rx(uart_rx),
        .led(led)
    );
    
    // =====================================================================
    // TEST HELPER FUNCTIONS
    // =====================================================================
    
    // Wait for N clock cycles
    task wait_cycles(int n);
        repeat (n) @(posedge clk);
    endtask
    
    // Report test result
    task report_test(string name, bit pass);
        if (pass)
            $display("[PASS] Test %s", name);
        else begin
            $display("[FAIL] Test %s", name);
            $finish;
        end
    endtask
    
    // =====================================================================
    // TEST 1: RESET VERIFICATION (AC-9)
    // =====================================================================
    
    task test_1_reset();
        $display("\n=== TEST 1: Reset Verification (AC-9) ===");
        
        // Wait for reset to complete
        wait_cycles(10);
        
        // Verify FSM states
        bit core0_idle = (dut.per_core[0].u_core.state == 1'b0);  // RUN state
        bit core1_idle = (dut.per_core[1].u_core.state == 1'b0);
        bit mgr0_idle = (dut.per_core[0].u_dcmgr.state == 4'h0);  // IDLE
        bit mgr1_idle = (dut.per_core[1].u_dcmgr.state == 4'h0);
        
        // Verify reset values
        bit pc0_zero = (dut.per_core[0].u_core.PC == 32'h0);
        bit pc1_zero = (dut.per_core[1].u_core.PC == 32'h0);
        
        // Verify all counters at 0
        bit counters_zero = (dut.u_mmio.inv_count_q == 32'h0) &&
                           (dut.u_mmio.hit_count_q == 32'h0) &&
                           (dut.u_mmio.miss_count_q == 32'h0);
        
        // Verify coherence mirror at I (invalid)
        bit mirror_invalid = (dut.u_coh.mirror_q == 32'h0);
        
        // Verify arbiter preference = 0 (core 0 wins)
        bit arb_pref_zero = (dut.u_arb.pref_q == 1'b0);
        
        bit pass = core0_idle && core1_idle && mgr0_idle && mgr1_idle &&
                   pc0_zero && pc1_zero && counters_zero && mirror_invalid && arb_pref_zero;
        
        report_test("Reset Verification", pass);
    endtask
    
    // =====================================================================
    // TEST 2: SINGLE-CORE LOAD/STORE
    // =====================================================================
    
    task test_2_single_core_load_store();
        $display("\n=== TEST 2: Single-Core Load/Store ===");
        
        // Load 0x12345678 from SRAM[0x100] into core 0
        // Core 0 issues: LW x1, 0x100(x0)
        // Expected: dmem_ack = 1, dmem_rdata = (value from shared SRAM)
        
        // Pre-populate shared SRAM location
        dut.u_sram.mem[32'h100 >> 2] = 32'h12345678;
        
        wait_cycles(5);  // Let reset stabilize
        
        // Inject load request from core 0
        dut.per_core[0].u_core.PC = 32'h0;
        dut.per_core[0].u_core.dmem_req = 1'b1;
        dut.per_core[0].u_core.dmem_we = 1'b0;  // Read
        dut.per_core[0].u_core.dmem_addr = 32'h100;
        
        // Wait for transaction
        int timeout = 0;
        while (!dut.per_core[0].u_dcmgr.dmem_ack && timeout < 100) begin
            wait_cycles(1);
            timeout++;
        end
        
        bit pass = (dut.per_core[0].u_dcmgr.dmem_ack == 1'b1);
        report_test("Single-Core Load/Store", pass);
    endtask
    
    // =====================================================================
    // TEST 3: CACHE HIT DETECTION
    // =====================================================================
    
    task test_3_cache_hit();
        $display("\n=== TEST 3: Cache Hit Detection ===");
        
        // Fill cache with data, then verify hit
        // Expected: hit signal asserts, no AXI traffic
        
        wait_cycles(5);
        
        // Manually load cache line 0 with valid data (simulating prior miss fill)
        dut.per_core[0].u_dcache.mem[0].valid = 1'b1;
        dut.per_core[0].u_dcache.mem[0].tag = 28'h001;
        dut.per_core[0].u_dcache.mem[0].data = 32'hDEADBEEF;
        dut.per_core[0].u_dcache.mem[0].state = 2'b01;  // S (shared)
        
        wait_cycles(1);
        
        // Issue request that should hit
        dut.per_core[0].u_core.dmem_addr = {28'h001, 4'h0};  // Tag matches
        
        bit hit = dut.per_core[0].u_dcache.hit;
        bit miss = dut.per_core[0].u_dcache.miss;
        
        bit pass = (hit == 1'b1) && (miss == 1'b0);
        report_test("Cache Hit Detection", pass);
    endtask
    
    // =====================================================================
    // TEST 4: CACHE MISS + AXI FILL
    // =====================================================================
    
    task test_4_cache_miss_fill();
        $display("\n=== TEST 4: Cache Miss + AXI Fill ===");
        
        // Issue load that misses
        // Expected: cache manager transitions through MISS_READ → AXI_AR → AXI_R → FILL
        // Expected: dmem_ack asserts after fill completes
        
        wait_cycles(10);
        
        // Pre-populate SRAM with test value
        dut.u_sram.mem[32'h200 >> 2] = 32'hCAFEBABE;
        
        // Issue miss request
        dut.per_core[0].u_core.dmem_req = 1'b1;
        dut.per_core[0].u_core.dmem_we = 1'b0;
        dut.per_core[0].u_core.dmem_addr = 32'h200;
        
        // Monitor FSM progression
        int timeout = 0;
        bit got_ack = 1'b0;
        while (timeout < 200) begin
            wait_cycles(1);
            if (dut.per_core[0].u_dcmgr.dmem_ack)
                got_ack = 1'b1;
            timeout++;
        end
        
        report_test("Cache Miss + Fill", got_ack);
    endtask
    
    // =====================================================================
    // TEST 5: CROSS-CORE COHERENCE (Write-Invalidate Demo)
    // =====================================================================
    
    task test_5_cross_core_coherence();
        $display("\n=== TEST 5: Cross-Core Coherence (Write-Invalidate) ===");
        
        // Core 0 has cache line in S state
        // Core 1 writes to same line
        // Expected: Core 0's line invalidated (M→I transition)
        
        wait_cycles(10);
        
        // Pre-fill both caches with same line at different states
        dut.per_core[0].u_dcache.mem[1].valid = 1'b1;
        dut.per_core[0].u_dcache.mem[1].tag = 28'h003;
        dut.per_core[0].u_dcache.mem[1].state = 2'b01;  // S
        
        dut.per_core[1].u_dcache.mem[1].valid = 1'b1;
        dut.per_core[1].u_dcache.mem[1].tag = 28'h003;
        dut.per_core[1].u_dcache.mem[1].state = 2'b01;  // S
        
        wait_cycles(2);
        
        // Core 1 write to same line
        dut.per_core[1].u_core.dmem_req = 1'b1;
        dut.per_core[1].u_core.dmem_we = 1'b1;
        dut.per_core[1].u_core.dmem_addr = 32'h300_0000 | (28'h003 << 4);
        dut.per_core[1].u_core.dmem_wdata = 32'hBEEFCAFE;
        dut.per_core[1].u_core.dmem_wmask = 4'hF;
        
        // Monitor invalidation
        int timeout = 0;
        bit inv_fired = 1'b0;
        while (timeout < 100) begin
            wait_cycles(1);
            if (dut.u_coh.inv_fire_o)
                inv_fired = 1'b1;
            timeout++;
        end
        
        // Check if Core 0's line was invalidated
        bit core0_line_invalid = (dut.per_core[0].u_dcache.mem[1].state == 2'b00);
        
        report_test("Cross-Core Coherence", inv_fired && core0_line_invalid);
    endtask
    
    // =====================================================================
    // TEST 6: ARBITER FAIRNESS (Simultaneous Writes)
    // =====================================================================
    
    task test_6_arbiter_fairness();
        $display("\n=== TEST 6: Arbiter Fairness (Simultaneous Writes) ===");
        
        // Both cores request bus simultaneously
        // Expected: Core 0 wins on first round (pref=0)
        // Then pref flips, Core 1 wins on next request
        
        wait_cycles(10);
        
        // Issue simultaneous requests
        dut.per_core[0].u_core.dmem_req = 1'b1;
        dut.per_core[0].u_core.dmem_we = 1'b1;
        dut.per_core[0].u_core.dmem_addr = 32'h400;
        
        dut.per_core[1].u_core.dmem_req = 1'b1;
        dut.per_core[1].u_core.dmem_we = 1'b1;
        dut.per_core[1].u_core.dmem_addr = 32'h404;
        
        // Check which core got grant
        wait_cycles(3);
        bit core0_granted_first = (dut.u_arb.state_q == 2'b01);  // ARB_G0
        
        // Wait for first transaction to complete
        while (!(dut.u_arb.done0 || dut.u_arb.done1))
            wait_cycles(1);
        
        wait_cycles(5);
        
        // Check if pref flipped
        bit pref_flipped = (dut.u_arb.pref_q == 1'b1);
        
        bit pass = core0_granted_first && pref_flipped;
        report_test("Arbiter Fairness", pass);
    endtask
    
    // =====================================================================
    // TEST 7: MULTIPLE LINES (No Spurious Invalidation)
    // =====================================================================
    
    task test_7_no_spurious_invalidation();
        $display("\n=== TEST 7: Multiple Lines (No Spurious Invalidation) ===");
        
        // Fill both caches with different lines
        // Core 1 writes to line A
        // Expected: Core 0's line B NOT invalidated
        
        wait_cycles(10);
        
        // Core 0: cache line 0 = tag 0x010
        dut.per_core[0].u_dcache.mem[0].valid = 1'b1;
        dut.per_core[0].u_dcache.mem[0].tag = 28'h010;
        dut.per_core[0].u_dcache.mem[0].state = 2'b01;  // S
        
        // Core 0: cache line 1 = tag 0x020 (different from core 1)
        dut.per_core[0].u_dcache.mem[1].valid = 1'b1;
        dut.per_core[0].u_dcache.mem[1].tag = 28'h020;
        dut.per_core[0].u_dcache.mem[1].state = 2'b01;  // S
        
        wait_cycles(2);
        
        // Core 1 writes to different line (tag 0x030)
        dut.per_core[1].u_core.dmem_req = 1'b1;
        dut.per_core[1].u_core.dmem_we = 1'b1;
        dut.per_core[1].u_core.dmem_addr = 32'h300_0000 | (28'h030 << 4);
        dut.per_core[1].u_core.dmem_wdata = 32'hDEADDEAD;
        dut.per_core[1].u_core.dmem_wmask = 4'hF;
        
        wait_cycles(50);
        
        // Check Core 0's lines are still valid
        bit line0_valid = (dut.per_core[0].u_dcache.mem[0].state != 2'b00);
        bit line1_valid = (dut.per_core[0].u_dcache.mem[1].state != 2'b00);
        
        report_test("No Spurious Invalidation", line0_valid && line1_valid);
    endtask
    
    // =====================================================================
    // TEST 8: UNCACHED MMIO ACCESS (R9 Bypass)
    // =====================================================================
    
    task test_8_uncached_mmio();
        $display("\n=== TEST 8: Uncached MMIO Access (R9 Bypass) ===");
        
        // Write to MMIO address (0x0001_0000)
        // Expected: Write bypasses cache, goes directly to MMIO
        // Expected: No cache line allocated
        
        wait_cycles(10);
        
        // Issue write to MMIO address
        dut.per_core[0].u_core.dmem_req = 1'b1;
        dut.per_core[0].u_core.dmem_we = 1'b1;
        dut.per_core[0].u_core.dmem_addr = 32'h0001_0000;  // MMIO base
        dut.per_core[0].u_core.dmem_wdata = 32'h0000_0001;
        dut.per_core[0].u_core.dmem_wmask = 4'hF;
        
        // Wait for transaction
        wait_cycles(30);
        
        // Check: Cache lines all invalid (no allocation)
        bit no_cache_alloc = (dut.per_core[0].u_dcache.mem[0].valid == 1'b0) &&
                            (dut.per_core[0].u_dcache.mem[1].valid == 1'b0) &&
                            (dut.per_core[0].u_dcache.mem[2].valid == 1'b0) &&
                            (dut.per_core[0].u_dcache.mem[3].valid == 1'b0);
        
        report_test("Uncached MMIO Access", no_cache_alloc);
    endtask
    
    // =====================================================================
    // TEST 9: UNMAPPED ADDRESS (DECERR Error)
    // =====================================================================
    
    task test_9_unmapped_address();
        $display("\n=== TEST 9: Unmapped Address (DECERR Error) ===");
        
        // Write to unmapped address
        // Expected: DECERR response (bresp = 2'b11)
        // Expected: dmem_err = 1
        
        wait_cycles(10);
        
        // Issue write to unmapped address
        dut.per_core[0].u_core.dmem_req = 1'b1;
        dut.per_core[0].u_core.dmem_we = 1'b1;
        dut.per_core[0].u_core.dmem_addr = 32'hDEAD_0000;  // Unmapped
        dut.per_core[0].u_core.dmem_wdata = 32'hFFFF_FFFF;
        dut.per_core[0].u_core.dmem_wmask = 4'hF;
        
        // Wait for error response
        int timeout = 0;
        bit got_error = 1'b0;
        while (timeout < 100) begin
            wait_cycles(1);
            if (dut.per_core[0].u_dcmgr.dmem_err)
                got_error = 1'b1;
            timeout++;
        end
        
        report_test("Unmapped Address (DECERR)", got_error);
    endtask
    
    // =====================================================================
    // TEST 10: COUNTER INCREMENTS
    // =====================================================================
    
    task test_10_counters();
        $display("\n=== TEST 10: Counter Increments ===");
        
        // Trigger cache hit, miss, and invalidation
        // Verify counters increment correctly
        
        wait_cycles(10);
        
        // Initial counter values
        logic [31:0] hit_init = dut.u_mmio.hit_count_q;
        logic [31:0] miss_init = dut.u_mmio.miss_count_q;
        logic [31:0] inv_init = dut.u_mmio.inv_count_q;
        
        // Inject hit signal
        force dut.per_core[0].u_dcmgr.hit = 1'b1;
        wait_cycles(2);
        release dut.per_core[0].u_dcmgr.hit;
        
        // Inject miss signal
        force dut.per_core[1].u_dcmgr.miss = 1'b1;
        wait_cycles(2);
        release dut.per_core[1].u_dcmgr.miss;
        
        // Inject invalidation
        force dut.u_coh.inv_fire_o = 1'b1;
        wait_cycles(2);
        release dut.u_coh.inv_fire_o;
        
        wait_cycles(5);
        
        // Verify increments
        bit hit_incremented = (dut.u_mmio.hit_count_q == hit_init + 32'h1);
        bit miss_incremented = (dut.u_mmio.miss_count_q == miss_init + 32'h1);
        bit inv_incremented = (dut.u_mmio.inv_count_q == inv_init + 32'h1);
        
        bit pass = hit_incremented && miss_incremented && inv_incremented;
        report_test("Counter Increments", pass);
    endtask
    
    // =====================================================================
    // MAIN TEST SEQUENCER
    // =====================================================================
    
    initial begin
        $display("\n================================================================================");
        $display("  RISC-V DUAL-CORE SOC WITH COHERENT MEMORY SUBSYSTEM");
        $display("  DIRECTED TESTBENCH (10 SCENARIOS)");
        $display("  Date: September 6, 2026");
        $display("================================================================================\n");
        
        wait_cycles(5);  // Wait for reset to complete
        
        test_1_reset();
        test_2_single_core_load_store();
        test_3_cache_hit();
        test_4_cache_miss_fill();
        test_5_cross_core_coherence();
        test_6_arbiter_fairness();
        test_7_no_spurious_invalidation();
        test_8_uncached_mmio();
        test_9_unmapped_address();
        test_10_counters();
        
        $display("\n================================================================================");
        $display("  ALL TESTS COMPLETED SUCCESSFULLY");
        $display("================================================================================\n");
        
        $finish;
    end

endmodule : tb_directed
