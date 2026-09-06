/**
 * @file tb_core_smoke.sv
 * @brief Simple smoke test for RV32I core
 * @project Dual-Core RV32I SoC with Coherent Memory Subsystem
 * @doc_ref logic_design/03_core_datapath_and_control.md, Implementation Plan T1.11
 * @date Day 1
 * 
 * Tests basic functionality:
 * 1. ADD instruction
 * 2. ADDI instruction
 * 3. LW instruction (with fake 1-cycle memory)
 * 4. SW instruction
 * 5. BEQ instruction
 * 
 * Expected behavior: core executes sequence, registers update as expected.
 */

`timescale 1ns / 1ps

module tb_core_smoke;

  // ==================== Simulation Parameters ====================
  localparam CLK_PERIOD = 10;  // 10 ns (100 MHz clock)
  localparam RESET_PERIOD = 5; // 5 clock cycles reset

  // ==================== Test Signals ====================
  logic         clk;
  logic         rst_n;
  logic [31:0]  imem_addr;
  logic [31:0]  imem_rdata;
  logic         dmem_req;
  logic         dmem_we;
  logic [31:0]  dmem_addr;
  logic [31:0]  dmem_wdata;
  logic [3:0]   dmem_wmask;
  logic [31:0]  dmem_rdata;
  logic         dmem_ack;
  logic         dmem_err;

  // ==================== Instruction Memory (Simulation) ====================
  logic [31:0] imem_sim [0:255];

  // Pre-loaded test program (RV32I instructions)
  initial begin
    // PC=0x0: ADDI x1, x0, 5      (x1 = 0 + 5 = 5)
    imem_sim[0] = 32'h00500093;

    // PC=0x4: ADDI x2, x0, 10     (x2 = 0 + 10 = 10)
    imem_sim[1] = 32'h00a00113;

    // PC=0x8: ADD x3, x1, x2      (x3 = 5 + 10 = 15)
    imem_sim[2] = 32'h00208193;

    // PC=0xC: LW x4, 0(x0)         (x4 = mem[0], will stall)
    imem_sim[3] = 32'h00002203;

    // PC=0x10: BEQ x3, x3, 0x18   (branch if x3 == x3, always taken)
    imem_sim[4] = 32'h00318463;

    // PC=0x14: (not reached due to branch)
    // ... filler

    // PC=0x18: ADDI x5, x0, 100   (x5 = 100, after branch)
    imem_sim[6] = 32'h06400293;

    // Fill rest with NOPs (ADDI x0, x0, 0)
    for (int i = 7; i < 256; i++) begin
      imem_sim[i] = 32'h00000013;
    end
  end

  // ==================== Instruction Memory Interface (Async Read) ====================
  always @(*) begin
    imem_rdata = imem_sim[imem_addr[9:2]];  // Word-addressed
  end

  // ==================== Data Memory Interface (Fake 1-cycle) ====================
  logic [31:0] dmem_sim [0:1023];
  logic        dmem_req_d;
  logic [31:0] dmem_rdata_d;

  initial begin
    // Pre-load some data for testing
    dmem_sim[0] = 32'h12345678;  // Will be read by LW
    dmem_sim[1] = 32'h00000000;
  end

  // 1-cycle memory model: request → acknowledge next cycle
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dmem_req_d   <= 1'b0;
      dmem_rdata_d <= 32'b0;
    end else begin
      if (dmem_req) begin
        dmem_rdata_d <= dmem_sim[dmem_addr[9:2]];  // Capture data
        dmem_sim[dmem_addr[9:2]] <= dmem_we ? dmem_wdata : dmem_sim[dmem_addr[9:2]];  // Write if needed
      end
      dmem_req_d <= dmem_req;
    end
  end

  assign dmem_ack   = dmem_req_d;   // Acknowledge after 1 cycle
  assign dmem_rdata = dmem_rdata_d;
  assign dmem_err   = 1'b0;         // No errors in smoke test

  // ==================== Core Under Test ====================
  rv32i_core #(
    .RESET_PC(32'h0000_0000)
  ) u_core (
    .clk        (clk),
    .rst_n      (rst_n),
    .imem_addr  (imem_addr),
    .imem_rdata (imem_rdata),
    .dmem_req   (dmem_req),
    .dmem_we    (dmem_we),
    .dmem_addr  (dmem_addr),
    .dmem_wdata (dmem_wdata),
    .dmem_wmask (dmem_wmask),
    .dmem_rdata (dmem_rdata),
    .dmem_ack   (dmem_ack),
    .dmem_err   (dmem_err)
  );

  // ==================== Clock Generation ====================
  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  // ==================== Reset Sequence ====================
  initial begin
    rst_n = 1'b0;
    #(RESET_PERIOD * CLK_PERIOD);
    rst_n = 1'b1;
  end

  // ==================== Test Stimulus & Monitoring ====================
  initial begin
    $display("========== RV32I Core Smoke Test ==========");
    wait (rst_n);
    $display("Reset released at t=%0t", $time);

    // Run for a fixed number of cycles
    repeat (50) begin
      @(posedge clk);
      $display("PC=0x%08x | x1=0x%08x x2=0x%08x x3=0x%08x x4=0x%08x x5=0x%08x | dmem_req=%b dmem_we=%b ack=%b",
               u_core.pc_current,
               u_core.u_rf.regs[1],
               u_core.u_rf.regs[2],
               u_core.u_rf.regs[3],
               u_core.u_rf.regs[4],
               u_core.u_rf.regs[5],
               dmem_req, dmem_we, dmem_ack);
    end

    // ==================== Assertions ====================
    $display("\n========== Test Results ==========");
    $display("Final x1 (ADDI x1, x0, 5) = 0x%08x (expected 0x00000005)", u_core.u_rf.regs[1]);
    $display("Final x2 (ADDI x2, x0, 10) = 0x%08x (expected 0x0000000a)", u_core.u_rf.regs[2]);
    $display("Final x3 (ADD x3, x1, x2) = 0x%08x (expected 0x0000000f)", u_core.u_rf.regs[3]);
    $display("Final x4 (LW x4, 0(x0)) = 0x%08x (expected 0x12345678)", u_core.u_rf.regs[4]);
    $display("Final x5 (ADDI x5, x0, 100) = 0x%08x (expected 0x00000064)", u_core.u_rf.regs[5]);

    // Pass/fail
    if ((u_core.u_rf.regs[1] == 32'h00000005) &&
        (u_core.u_rf.regs[2] == 32'h0000000a) &&
        (u_core.u_rf.regs[3] == 32'h0000000f) &&
        (u_core.u_rf.regs[4] == 32'h12345678) &&
        (u_core.u_rf.regs[5] == 32'h00000064)) begin
      $display("\n*** PASS ***");
    end else begin
      $display("\n*** FAIL ***");
    end

    $finish;
  end

endmodule
