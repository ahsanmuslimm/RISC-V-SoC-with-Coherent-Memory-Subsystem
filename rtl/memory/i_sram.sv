/**
 * @file i_sram.sv
 * @brief Instruction SRAM (I-SRAM) - Private per-core instruction memory
 * @project Dual-Core RV32I SoC with Coherent Memory Subsystem
 * @doc_ref logic_design/08_memory_subsystem.md, gate_level/09_memory_gate_level.md
 * @date Day 1, Task T2.2 (parallel with Day 1 core RTL)
 * 
 * 1 KB per core (256 × 32-bit words).
 * Asynchronous read: imem_rdata available combinationally (same cycle).
 * This keeps the core single-cycle (no pipeline bubbles on fetch).
 * Write port for initialization/test only (disabled during normal operation).
 * 
 * Each core has one I-SRAM instance (i_sram_0, i_sram_1 in top-level).
 */

module i_sram #(
  parameter DEPTH = 256,                // Depth: 256 words = 1 KB
  parameter WIDTH = 32,                 // Width: 32 bits per word
  parameter INIT_FILE = ""              // Hex init file (optional)
) (
  input  logic                clk,       // Write clock (for test writes)
  input  logic                rst_n,     // Async reset (for hygiene, not used in memories)
  
  // Read port (asynchronous - combinational)
  input  logic [$clog2(DEPTH)-1:0] raddr, // Read address
  output logic [WIDTH-1:0]         rdata, // Read data (combinational)
  
  // Write port (synchronous - for initialization/testing only)
  input  logic [$clog2(DEPTH)-1:0] waddr, // Write address
  input  logic [WIDTH-1:0]         wdata, // Write data
  input  logic                     we     // Write enable (0 during normal op)
);

  // ==================== Memory Array ====================
  logic [WIDTH-1:0] mem [0:DEPTH-1];

  // ==================== Initialization ====================
  // Load program from hex file if provided (Verilog/simulation only)
  // For FPGA: bitstream handles init
  // For ASIC: memory init handled at synthesis/PD level

  initial begin
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end else begin
      // Default: fill with zeros
      for (int i = 0; i < DEPTH; i++) begin
        mem[i] = 32'b0;
      end
    end
  end

  // ==================== Asynchronous Read Port ====================
  // Combinational: address → data in same cycle (no latency)
  // Enables single-cycle instruction fetch

  assign rdata = mem[raddr];

  // ==================== Synchronous Write Port ====================
  // Used only during test/initialization (set we=0 during normal operation)
  // Write happens on positive clock edge

  always_ff @(posedge clk) begin
    if (we) begin
      mem[waddr] <= wdata;
    end
  end

endmodule
