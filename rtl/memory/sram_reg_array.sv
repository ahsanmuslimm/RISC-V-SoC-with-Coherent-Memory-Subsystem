/**
 * @file sram_reg_array.sv
 * @brief Generic parameterized SRAM register array
 * @project Dual-Core RV32I SoC with Coherent Memory Subsystem
 * @doc_ref logic_design/08_memory_subsystem.md §8.1
 * @date Day 2, Task T2.1
 * 
 * Generic SRAM implementation using register arrays.
 * Supports both async and sync read modes (configurable).
 * Suitable for both ASIC (sky130A) and FPGA (BRAM/LUTRAM).
 * 
 * Parameters:
 *   DEPTH - number of words (default 1024)
 *   WIDTH - bits per word (default 32)
 *   ASYNC_READ - 0=sync read (BRAM), 1=async read (LUTRAM)
 */

module sram_reg_array #(
  parameter int DEPTH = 1024,
  parameter int WIDTH = 32,
  parameter int ASYNC_READ = 0     // 0 = sync read, 1 = async read
) (
  input  logic                    clk,
  input  logic                    rst_n,
  
  // Read port
  input  logic [$clog2(DEPTH)-1:0] raddr,
  output logic [WIDTH-1:0]         rdata,
  
  // Write port (byte-writable)
  input  logic [$clog2(DEPTH)-1:0] waddr,
  input  logic [WIDTH-1:0]         wdata,
  input  logic [WIDTH/8-1:0]       wmask,   // Byte enable mask
  input  logic                     we
);

  // ==================== Memory Array ====================
  logic [WIDTH-1:0] mem [0:DEPTH-1];

  // ==================== Asynchronous Read ====================
  if (ASYNC_READ) begin : async_read_mode
    assign rdata = mem[raddr];  // Combinational read
  end else begin : sync_read_mode
    // ==================== Synchronous Read ====================
    // Read data captured at posedge clk
    logic [WIDTH-1:0] rdata_q;
    assign rdata = rdata_q;
    
    always_ff @(posedge clk) begin
      rdata_q <= mem[raddr];
    end
  end

  // ==================== Synchronous Write ====================
  // Write happens on positive clock edge
  // Supports byte-level write masking (wmask[n] = 1 → write byte n)

  always_ff @(posedge clk) begin
    if (we) begin
      // Byte-masked write: only write bytes where wmask[i] = 1
      for (int byte_idx = 0; byte_idx < WIDTH/8; byte_idx++) begin
        if (wmask[byte_idx]) begin
          mem[waddr][byte_idx*8 +: 8] <= wdata[byte_idx*8 +: 8];
        end
      end
    end
  end

  // ==================== Initialization (Simulation Only) ====================
  // pragma translate_off
  initial begin
    // Initialize memory to zero
    for (int i = 0; i < DEPTH; i++) begin
      mem[i] = '0;
    end
  end
  // pragma translate_on

endmodule
