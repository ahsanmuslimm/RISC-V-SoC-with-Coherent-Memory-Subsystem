/**
 * @file pc_logic.sv
 * @brief Program Counter Logic (PC Multiplexer & Update)
 * @project Dual-Core RV32I SoC with Coherent Memory Subsystem
 * @doc_ref logic_design/03_core_datapath_and_control.md, gate_level/02_regfile_pc_gate_level.md
 * @date Day 1, Task T1.9 (integrated into rv32i_core)
 * 
 * Implements:
 * - PC multiplexer (sequential, branch-taken, JALR, reset)
 * - PC register (stores next PC, updated synchronously)
 * - PC+4 logic (for link register in JAL/JALR)
 * - Branch condition resolution (zero flag from ALU)
 */

module pc_logic (
  input  logic        clk,              // Clock
  input  logic        rst_n,            // Async reset (active-low)
  input  logic [31:0] pc_current,       // Current PC (feedback from register)
  input  logic [31:0] imm,              // Immediate offset (branch/jump)
  input  logic [31:0] rs1_data,         // RS1 data (for JALR)
  input  logic [1:0]  pc_sel,           // PC mux select (from control_unit)
  input  logic        alu_zero,         // Branch condition from ALU
  input  logic        branch_type,      // Branch type (from control_unit)
  output logic [31:0] pc_next,          // Next PC (registered)
  output logic [31:0] pc_plus_4         // PC + 4 (for JAL/JALR link)
);

  // ==================== Combinational PC+4 Calculation ====================
  assign pc_plus_4 = pc_current + 32'd4;

  // ==================== Branch Condition Resolution ====================
  // Maps branch type (func3 from control unit) to condition
  // Reuses ALU's subtraction result via alu_zero flag
  // Control unit should pass branch type when branch instruction detected

  logic pc_mux_sel_final;

  // For simplicity: if branch instruction and condition met, take branch
  // Full branch type resolution happens in rv32i_core (based on func3)
  // This module is designed to integrate with that logic

  // ==================== PC Multiplexer ====================
  // pc_sel encoding:
  // 00 = PC + 4 (sequential)
  // 01 = PC + imm (branch or JAL)
  // 10 = RS1 + imm (JALR)
  // 11 = reset (0x0000_0000)

  logic [31:0] pc_branch;
  logic [31:0] pc_jalr;

  assign pc_branch = pc_current + imm;
  assign pc_jalr   = rs1_data + imm;

  logic [31:0] pc_mux_out;

  always_comb begin
    case (pc_sel)
      2'b00:   pc_mux_out = pc_plus_4;     // Sequential
      2'b01:   pc_mux_out = pc_branch;     // Branch / JAL
      2'b10:   pc_mux_out = pc_jalr;       // JALR
      2'b11:   pc_mux_out = 32'h0000_0000; // Reset
      default: pc_mux_out = pc_plus_4;     // Safe default
    endcase
  end

  // ==================== PC Register (Synchronous Update) ====================
  // Holds the next PC to fetch in the next cycle
  // On reset: PC = 0x0000_0000

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_next <= 32'h0000_0000;
    end else begin
      pc_next <= pc_mux_out;
    end
  end

endmodule
