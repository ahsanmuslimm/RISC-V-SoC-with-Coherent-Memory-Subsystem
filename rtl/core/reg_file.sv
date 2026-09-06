/**
 * @file reg_file.sv
 * @brief 32×32-bit Register File for RV32I CPU Core
 * @project Dual-Core RV32I SoC with Coherent Memory Subsystem
 * @doc_ref logic_design/03_core_datapath_and_control.md, gate_level/02_regfile_pc_gate_level.md
 * @date Day 1, Task T1.8
 * 
 * Provides 2 read ports (combinational) and 1 write port (synchronous).
 * x0 (zero register) is hardwired: always reads 0, writes ignored.
 * All other registers x1–x31 behave normally.
 */

module reg_file (
  input  logic        clk,              // Write clock
  input  logic        rst_n,            // Async reset (active-low)
  
  // Write port (synchronous)
  input  logic [4:0]  wa,               // Write address (x0–x31)
  input  logic [31:0] wd,               // Write data
  input  logic        we,               // Write enable
  
  // Read port A (combinational)
  input  logic [4:0]  ra,               // Read address A
  output logic [31:0] rd_a,             // Read data A
  
  // Read port B (combinational)
  input  logic [4:0]  rb,               // Read address B
  output logic [31:0] rd_b              // Read data B
);

  // ==================== Register Array ====================
  // 32 registers × 32 bits each
  // Indexed 0–31 (x0–x31 in RISC-V convention)
  logic [31:0] regs [0:31];

  // ==================== Synchronous Write Port ====================
  // Write happens on positive clock edge
  // x0 writes are silently ignored (always 0)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Reset all registers to 0
      for (int i = 0; i < 32; i++) begin
        regs[i] <= 32'b0;
      end
    end else if (we && wa != 5'b0) begin
      // Write only if wa is not x0, and we is asserted
      regs[wa] <= wd;
    end
  end

  // ==================== Combinational Read Ports ====================
  // x0 always reads 0 (hardwired)
  // Other registers read directly from the array (combinational)

  assign rd_a = (ra == 5'b0) ? 32'b0 : regs[ra];
  assign rd_b = (rb == 5'b0) ? 32'b0 : regs[rb];

endmodule
