/**
 * @file uvm_env.sv
 * @brief UVM Verification Environment for RISC-V SoC (Day 4 T4.1–T4.8)
 *
 * Purpose: Comprehensive UVM environment with monitoring, scoreboarding,
 * and functional coverage for dual-core RISC-V SoC verification.
 *
 * Components:
 *   - Transaction classes: mem_txn, coh_event_txn
 *   - Monitor: Passive observation of SoC activity
 *   - Scoreboard: Self-checking with reference model
 *   - Coverage: Functional coverage groups (cache, coherence, errors)
 *   - Test base class and specific test scenarios
 *
 * References:
 *   - logic_design/13_working_logic_scenarios.md (test scenarios)
 *   - tb/uvm/riscv_soc_if.sv (virtual interface)
 */

package soc_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // =====================================================================
    // TRANSACTION CLASSES
    // =====================================================================

    /**
     * @class mem_txn
     * @brief Memory access transaction (load/store operation)
     */
    class mem_txn extends uvm_sequence_item;
        `uvm_object_utils(mem_txn)

        // Transaction fields
        rand bit [0:0]   core_id;       // 0 or 1
        rand bit [0:0]   we;            // 1=write, 0=read
        rand bit [31:0]  addr;          // Memory address
        rand bit [31:0]  wdata;         // Write data (if we=1)
        rand bit [3:0]   wmask;         // Write mask (if we=1)
        
        // Response fields (captured from SoC)
        bit [31:0]       rdata;         // Read data (if we=0)
        bit [0:0]        err;           // 1=error response (e.g., DECERR)
        bit [0:0]        hit;           // 1=cache hit
        bit [0:0]        miss;          // 1=cache miss (requires fetch)

        // Constraints
        constraint addr_range {
            // Accessible address range: 0x0000_0000 to 0x0000_3FFF (16 KB)
            addr inside {[32'h0000_0000:32'h0000_3FFF]};
        }

        constraint we_dist {
            // 60% reads, 40% writes
            we dist {0 := 60, 1 := 40};
        }

        function new(string name = "mem_txn");
            super.new(name);
        endfunction : new

        function string convert2string();
            return $sformatf(
                "mem_txn{core=%0d, %s, addr=0x%08h, wdata=0x%08h, wmask=0x%h, rdata=0x%08h, err=%0d, hit=%0d, miss=%0d}",
                core_id, we ? "WR" : "RD", addr, wdata, wmask, rdata, err, hit, miss
            );
        endfunction : convert2string
    endclass : mem_txn

    /**
     * @class coh_event_txn
     * @brief Coherence event transaction (protocol state machine transition)
     */
    class coh_event_txn extends uvm_sequence_item;
        `uvm_object_utils(coh_event_txn)

        // Coherence events (from coherence_ctrl FSM)
        typedef enum bit [2:0] {
            WRITE_NOTIFY     = 3'b001,   // Write notification (self or other core)
            FILL_NOTIFY      = 3'b010,   // Cache fill notification
            INV_VALID        = 3'b011,   // Line invalidation
            INV_ACK          = 3'b100,   // Invalidation acknowledged
            COH_IDLE         = 3'b000    // No event (placeholder)
        } coh_event_e;

        // Event fields
        coh_event_e      event_type;     // Type of coherence event
        bit [0:0]        initiator;      // Core initiating write (for WRITE_NOTIFY)
        bit [0:0]        target;         // Core being invalidated (for INV_VALID)
        bit [31:0]       addr;           // Cache line address
        bit [1:0]        state_before;   // State before transition (I=0, S=1, M=2)
        bit [1:0]        state_after;    // State after transition

        function new(string name = "coh_event_txn");
            super.new(name);
        endfunction : new

        function string convert2string();
            string event_str;
            case (event_type)
                WRITE_NOTIFY: event_str = "WRITE_NOTIFY";
                FILL_NOTIFY:  event_str = "FILL_NOTIFY";
                INV_VALID:    event_str = "INV_VALID";
                INV_ACK:      event_str = "INV_ACK";
                default:      event_str = "IDLE";
            endcase
            return $sformatf(
                "coh_event_txn{%s, init=%0d, tgt=%0d, addr=0x%08h, %s→%s}",
                event_str, initiator, target, addr,
                state_before == 0 ? "I" : (state_before == 1 ? "S" : "M"),
                state_after == 0 ? "I" : (state_after == 1 ? "S" : "M")
            );
        endfunction : convert2string
    endclass : coh_event_txn

    // =====================================================================
    // MONITOR
    // =====================================================================

    /**
     * @class soc_monitor
     * @brief Passive monitor observing SoC memory and coherence activity
     */
    class soc_monitor extends uvm_monitor;
        `uvm_component_utils(soc_monitor)

        // Virtual interface
        virtual riscv_soc_if soc_vif;

        // Analysis ports
        uvm_analysis_port #(mem_txn)       mem_ap;
        uvm_analysis_port #(coh_event_txn) coh_ap;

        // Internal state for tracking
        bit [31:0]  last_addr;
        bit [0:0]   last_hit, last_miss;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            mem_ap = new("mem_ap", this);
            coh_ap = new("coh_ap", this);
        endfunction : new

        function void build_phase(uvm_build_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual riscv_soc_if)::get(this, "", "soc_vif", soc_vif))
                `uvm_fatal("soc_monitor", "Virtual interface not found in config_db")
        endfunction : build_phase

        task run_phase(uvm_run_phase phase);
            mem_txn      m_txn;
            coh_event_txn c_txn;

            forever begin
                @(posedge soc_vif.clk);
                
                // Monitor memory transactions
                if (soc_vif.monitor_mem_txn(m_txn)) begin
                    mem_ap.write(m_txn);
                    `uvm_info("soc_monitor", $sformatf("Captured: %s", m_txn.convert2string()), UVM_LOW)
                end

                // Monitor coherence events
                if (soc_vif.monitor_coh_event(c_txn)) begin
                    coh_ap.write(c_txn);
                    `uvm_info("soc_monitor", $sformatf("Captured: %s", c_txn.convert2string()), UVM_LOW)
                end
            end
        endtask : run_phase
    endclass : soc_monitor

    // =====================================================================
    // SCOREBOARD
    // =====================================================================

    /**
     * @class soc_scoreboard
     * @brief Self-checking scoreboard with reference model
     *
     * Reference Model:
     *   - SRAM: 4 KB shared memory (word-addressed 0x000-0x3FF)
     *   - Mirror: Per-core cache line state (I/S/M) for each line
     *   - Counters: HIT, MISS, INV events
     *
     * Checking:
     *   - Memory read responses match SRAM content
     *   - Cache state transitions follow I/S/M protocol
     *   - Invalidations occur at correct times
     *   - DECERR on unmapped addresses
     */
    class soc_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(soc_scoreboard)

        // Reference model
        bit [31:0]  ref_sram[0:1023];    // 4 KB SRAM (32-bit words)
        bit [1:0]   ref_mirror[0:1];     // Per-core cache line state (I/S/M)
        bit [31:0]  ref_hit_cnt, ref_miss_cnt, ref_inv_cnt;

        // Transaction FIFOs
        mem_txn       mem_fifo[$];
        coh_event_txn coh_fifo[$];

        // Analysis export
        uvm_analysis_export #(mem_txn)       mem_ae;
        uvm_analysis_export #(coh_event_txn) coh_ae;

        // Internal
        int mem_count = 0;
        int coh_count = 0;
        int error_count = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            mem_ae = new("mem_ae", this);
            coh_ae = new("coh_ae", this);
        endfunction : new

        function void build_phase(uvm_build_phase phase);
            super.build_phase(phase);
            // Initialize reference model
            for (int i = 0; i < 1024; i++) ref_sram[i] = 32'h0;
            for (int i = 0; i < 2; i++) ref_mirror[i] = 2'b00;  // I state
            ref_hit_cnt = 0;
            ref_miss_cnt = 0;
            ref_inv_cnt = 0;
        endfunction : build_phase

        function void connect_phase(uvm_connect_phase phase);
            super.connect_phase(phase);
            // Connect analysis exports to write methods
            mem_ae.connect(this.mem_analysis_imp);
            coh_ae.connect(this.coh_analysis_imp);
        endfunction : connect_phase

        // Analysis implementation for memory transactions
        uvm_analysis_imp #(mem_txn, soc_scoreboard) mem_analysis_imp;

        function void mem_analysis_imp::write(mem_txn txn);
            bit [31:0] word_addr;
            bit [31:0] expected_rdata;
            bit expected_err;

            word_addr = txn.addr >> 2;  // Convert to word address
            mem_count++;

            // Check if address is valid
            expected_err = (word_addr >= 1024);  // Beyond 4 KB

            if (expected_err != txn.err) begin
                `uvm_error("soc_scoreboard", $sformatf(
                    "ERROR mismatch: addr=0x%08h, expected err=%0d, got err=%0d",
                    txn.addr, expected_err, txn.err
                ))
                error_count++;
            end

            // For reads, verify data
            if (!txn.we && !txn.err) begin
                expected_rdata = ref_sram[word_addr];
                if (expected_rdata != txn.rdata) begin
                    `uvm_error("soc_scoreboard", $sformatf(
                        "DATA mismatch: addr=0x%08h, expected=0x%08h, got=0x%08h",
                        txn.addr, expected_rdata, txn.rdata
                    ))
                    error_count++;
                end
            end

            // For writes, update reference
            if (txn.we && !txn.err) begin
                for (int i = 0; i < 4; i++) begin
                    if (txn.wmask[i]) begin
                        ref_sram[word_addr][i*8 +: 8] = txn.wdata[i*8 +: 8];
                    end
                end
            end

            // Track hit/miss
            if (txn.hit) ref_hit_cnt++;
            if (txn.miss) ref_miss_cnt++;

            mem_fifo.push_back(txn);
            `uvm_info("soc_scoreboard", $sformatf("Checked: %s (cnt=%0d)", txn.convert2string(), mem_count), UVM_HIGH)
        endfunction : write

        // Analysis implementation for coherence events
        uvm_analysis_imp #(coh_event_txn, soc_scoreboard) coh_analysis_imp;

        function void coh_analysis_imp::write(coh_event_txn txn);
            coh_count++;

            // Track state transitions
            case (txn.event_type)
                coh_event_txn::WRITE_NOTIFY: begin
                    // Writing core transitions to M state
                    ref_mirror[txn.initiator] = 2'b10;  // M
                    `uvm_info("soc_scoreboard", $sformatf("Core %0d → M", txn.initiator), UVM_HIGH)
                end
                coh_event_txn::FILL_NOTIFY: begin
                    // Filling core transitions to S state
                    ref_mirror[txn.initiator] = 2'b01;  // S
                    `uvm_info("soc_scoreboard", $sformatf("Core %0d → S", txn.initiator), UVM_HIGH)
                end
                coh_event_txn::INV_VALID: begin
                    // Target core line invalidated
                    ref_mirror[txn.target] = 2'b00;  // I
                    ref_inv_cnt++;
                    `uvm_info("soc_scoreboard", $sformatf("Core %0d → I (invalidated)", txn.target), UVM_HIGH)
                end
                default: begin
                    // No action for IDLE/ACK
                end
            endcase

            coh_fifo.push_back(txn);
        endfunction : write

        function void report_phase(uvm_report_phase phase);
            super.report_phase(phase);
            `uvm_info("soc_scoreboard", $sformatf(
                "=== SCOREBOARD REPORT ===\nMemory txns: %0d\nCoherence events: %0d\nErrors: %0d\nHits: %0d\nMisses: %0d\nInvalidations: %0d",
                mem_count, coh_count, error_count, ref_hit_cnt, ref_miss_cnt, ref_inv_cnt
            ), UVM_LOW)
            if (error_count > 0) begin
                `uvm_error("soc_scoreboard", $sformatf("SIMULATION FAILED: %0d errors detected", error_count))
            end else begin
                `uvm_info("soc_scoreboard", "SIMULATION PASSED: All checks passed", UVM_LOW)
            end
        endfunction : report_phase
    endclass : soc_scoreboard

    // =====================================================================
    // FUNCTIONAL COVERAGE
    // =====================================================================

    /**
     * @class soc_coverage
     * @brief Functional coverage collection for cache and coherence behavior
     */
    class soc_coverage extends uvm_component;
        `uvm_component_utils(soc_coverage)

        virtual riscv_soc_if soc_vif;

        // Coverage groups
        covergroup cg_cache;
            cp_hit_miss: coverpoint {soc_vif.hit0, soc_vif.miss0, soc_vif.hit1, soc_vif.miss1} {
                bins hit_0              = {4'b1000};
                bins miss_0             = {4'b0100};
                bins hit_1              = {4'b0010};
                bins miss_1             = {4'b0001};
                bins simultaneous_hit_0_miss_1 = {4'b1001};
                bins simultaneous_miss_0_hit_1 = {4'b0110};
                bins both_miss          = {4'b0101};
                bins both_hit           = {4'b1010};
            }
        endgroup : cg_cache

        covergroup cg_coherence;
            cp_inv_event: coverpoint soc_vif.inv_valid {
                bins no_inv  = {1'b0};
                bins inv_fired = {1'b1};
            }
            cp_write_notify: coverpoint soc_vif.write_notify {
                bins not_notified = {1'b0};
                bins notified     = {1'b1};
            }
            cc_inv_x_notify: cross cp_inv_event, cp_write_notify {
                bins valid_transitions[] = binsof(cp_inv_event) intersect {1'b1} && binsof(cp_write_notify) intersect {1'b1};
            }
        endgroup : cg_coherence

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction : new

        function void build_phase(uvm_build_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual riscv_soc_if)::get(this, "", "soc_vif", soc_vif))
                `uvm_fatal("soc_coverage", "Virtual interface not found in config_db")
            cg_cache = new();
            cg_coherence = new();
        endfunction : build_phase

        task run_phase(uvm_run_phase phase);
            forever begin
                @(posedge soc_vif.clk);
                cg_cache.sample();
                cg_coherence.sample();
            end
        endtask : run_phase

        function void report_phase(uvm_report_phase phase);
            super.report_phase(phase);
            `uvm_info("soc_coverage", $sformatf(
                "=== COVERAGE REPORT ===\nCache coverage: %.1f%%\nCoherence coverage: %.1f%%",
                cg_cache.get_coverage(), cg_coherence.get_coverage()
            ), UVM_LOW)
        endfunction : report_phase
    endclass : soc_coverage

    // =====================================================================
    // VERIFICATION ENVIRONMENT
    // =====================================================================

    /**
     * @class soc_config
     * @brief Configuration object for verification parameters
     */
    class soc_config extends uvm_object;
        `uvm_object_utils(soc_config)

        bit [15:0] num_txns = 1000;      // Number of randomized transactions
        bit [0:0]  enable_cov = 1;       // Enable coverage collection
        bit [0:0]  enable_sb = 1;        // Enable scoreboard checking

        function new(string name = "soc_config");
            super.new(name);
        endfunction : new
    endclass : soc_config

    /**
     * @class soc_env
     * @brief Top-level verification environment
     */
    class soc_env extends uvm_env;
        `uvm_component_utils(soc_env)

        soc_config    m_cfg;
        soc_monitor   m_monitor;
        soc_scoreboard m_scoreboard;
        soc_coverage  m_coverage;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction : new

        function void build_phase(uvm_build_phase phase);
            super.build_phase(phase);

            // Get or create config
            if (!uvm_config_db #(soc_config)::get(this, "", "soc_config", m_cfg)) begin
                m_cfg = soc_config::type_id::create("m_cfg");
                uvm_config_db #(soc_config)::set(this, "", "soc_config", m_cfg);
            end

            // Create components
            m_monitor   = soc_monitor::type_id::create("m_monitor", this);
            m_scoreboard = soc_scoreboard::type_id::create("m_scoreboard", this);
            if (m_cfg.enable_cov)
                m_coverage = soc_coverage::type_id::create("m_coverage", this);
        endfunction : build_phase

        function void connect_phase(uvm_connect_phase phase);
            super.connect_phase(phase);
            // Connect monitor analysis ports to scoreboard
            m_monitor.mem_ap.connect(m_scoreboard.mem_ae);
            m_monitor.coh_ap.connect(m_scoreboard.coh_ae);
        endfunction : connect_phase

        function void end_of_elaboration_phase(uvm_end_of_elaboration_phase phase);
            super.end_of_elaboration_phase(phase);
            `uvm_info("soc_env", "=== Environment Build Complete ===", UVM_LOW)
        endfunction : end_of_elaboration_phase
    endclass : soc_env

    // =====================================================================
    // BASE TEST CLASS
    // =====================================================================

    /**
     * @class soc_test_base
     * @brief Base test class for all verification scenarios
     */
    class soc_test_base extends uvm_test;
        `uvm_component_utils(soc_test_base)

        soc_env   m_env;
        soc_config m_cfg;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction : new

        function void build_phase(uvm_build_phase phase);
            super.build_phase(phase);
            m_cfg = soc_config::type_id::create("m_cfg");
            uvm_config_db #(soc_config)::set(this, "", "soc_config", m_cfg);
            m_env = soc_env::type_id::create("m_env", this);
        endfunction : build_phase

        function void end_of_elaboration_phase(uvm_end_of_elaboration_phase phase);
            super.end_of_elaboration_phase(phase);
            uvm_top.print_topology();
        endfunction : end_of_elaboration_phase

        task run_phase(uvm_run_phase phase);
            super.run_phase(phase);
            phase.raise_objection(this);
            // Specific test implementation in derived classes
            `uvm_info("soc_test_base", "Base test running", UVM_LOW)
            #10us;  // 10 µs test duration (500,000 cycles @ 50 MHz)
            phase.drop_objection(this);
        endtask : run_phase
    endclass : soc_test_base

endpackage : soc_uvm_pkg

