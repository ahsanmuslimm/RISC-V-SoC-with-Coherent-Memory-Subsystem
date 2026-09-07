/**
 * @file d_cache.sv
 * @brief Data Cache storage and hit/miss logic
 * @project Dual-Core RV32I SoC with Coherent Memory Subsystem
 * @doc_ref logic_design/04_dcache_fsm.md §4.2–4.3
 * @date Day 2, Task T2.4
 *
 * FIXES APPLIED (Second Draft):
 *  BUG-002a: line_valid port changed from logic [1:0] to logic (1-bit), matching
 *            the underlying 1-bit line_valid_reg. Dead upper bit eliminated.
 *  BUG-002b: Removed the mixed line_state port that illegally packed coherence state
 *            with req_idx. Replaced with two clean, correctly-typed ports:
 *              - line_coh_state[i] : 2-bit I/S/M coherence state per line
 *              - line_req_idx      : 2-bit current request line index (req_addr[3:2])
 *  BUG-002c: line_out port trimmed from 64 bits to 63 bits. Content is
 *            {state[1:0], tag[27:0], data[31:0], valid} = 2+28+32+1 = 63 bits.
 *            The previously-declared bit 63 was always zero.
 *
 * Direct-mapped 4-line cache (1 word per line).
 * Each line: valid bit + 28-bit tag + 32-bit data + 2-bit I/S/M state.
 * Hit/miss detection combinational.
 * Invalidation via dedicated input.
 *
 * Parameters:
 *   LINES - number of cache lines (4)
 */

module d_cache #(
  parameter int LINES = 4
) (
  input  logic        clk,
  input  logic        rst_n,

  // Request side (from core)
  input  logic [31:0] req_addr,          // Request address (byte-addressed)
  output logic        hit,               // Cache hit
  output logic        miss,              // Cache miss (inverted hit)
  output logic [1:0]  hit_idx,           // Index of hit line (valid when hit=1)

  // Hit data (combinational read of hit line)
  output logic [31:0] hit_data,

  // Line state info (read for dispatch, see doc 05 §5.3)
  // BUG-002a fix: 1-bit per entry, matching line_valid_reg
  output logic        line_valid[LINES-1:0],      // Valid bits (1-bit each)
  // BUG-002b fix: separate coherence-state and request-index ports
  output logic [1:0]  line_coh_state[LINES-1:0],  // I/S/M coherence state per line
  output logic [1:0]  line_req_idx,               // Current request line index (req_addr[3:2])

  // Line storage (read for debugging/verification)
  // BUG-002c fix: 63 bits — {state[1:0], tag[27:0], data[31:0], valid} = 2+28+32+1
  output logic [62:0] line_out[LINES-1:0],

  // Write/invalidate from cache manager
  input  logic [1:0]  wr_idx,            // Write line index
  input  logic [31:0] wr_data,           // Write data
  input  logic [27:0] wr_tag,            // Write tag
  input  logic [1:0]  wr_state,          // Write state (I/S/M)
  input  logic        wr_valid,          // Write valid bit
  input  logic [LINES-1:0] wr_we,        // Write enable (1-hot)

  // Invalidation from coherence
  input  logic [1:0]  inv_idx,           // Invalidate line index
  input  logic        inv_we             // Invalidate write enable
);

  // ==================== Encoding ====================
  // I = 2'b00, S = 2'b01, M = 2'b10

  // ==================== Cache Line Storage ====================
  // Each line: {state[1:0], tag[27:0], data[31:0], valid} = 63 bits
  logic [1:0]  line_state_reg[LINES-1:0];  // Coherence state (I/S/M)
  logic [27:0] line_tag_reg[LINES-1:0];    // Tag (addr[31:4])
  logic [31:0] line_data_reg[LINES-1:0];   // Cached data word
  logic        line_valid_reg[LINES-1:0];  // Valid bit

  // ==================== Hit/Miss Detection ====================
  logic [27:0] req_tag;
  logic [1:0]  req_idx;

  assign req_tag = req_addr[31:4];
  assign req_idx = req_addr[3:2];

  // Parallel tag comparators for all lines
  logic tag_match[LINES-1:0];
  logic state_valid[LINES-1:0];   // state != I

  generate
    for (genvar i = 0; i < LINES; i++) begin : tag_compare
      assign tag_match[i]   = (req_tag == line_tag_reg[i]);
      assign state_valid[i] = (line_state_reg[i] != 2'b00);  // Not I
    end
  endgenerate

  // Hit condition: tag match AND valid AND (state != I)
  logic hit_combined[LINES-1:0];

  generate
    for (genvar i = 0; i < LINES; i++) begin : hit_logic
      assign hit_combined[i] = tag_match[i] && line_valid_reg[i] && state_valid[i];
    end
  endgenerate

  assign hit  = |hit_combined;
  assign miss = ~hit;

  // Find hit line index (priority encoder)
  always_comb begin
    hit_idx = 2'b0;
    for (int i = 0; i < LINES; i++) begin
      if (hit_combined[i]) begin
        hit_idx = i[1:0];
      end
    end
  end

  // Return data from hit line
  always_comb begin
    hit_data = 32'b0;
    for (int i = 0; i < LINES; i++) begin
      if (hit_combined[i]) begin
        hit_data = line_data_reg[i];
      end
    end
  end

  // ==================== Output Line State Info ====================
  // BUG-002a: line_valid[i] is 1-bit, directly from line_valid_reg[i]
  // BUG-002b: line_coh_state[i] carries only I/S/M; line_req_idx carries request index
  generate
    for (genvar i = 0; i < LINES; i++) begin : output_state
      assign line_valid[i]     = line_valid_reg[i];       // 1-bit, no dead upper bit
      assign line_coh_state[i] = line_state_reg[i];       // 2-bit I/S/M only
    end
  endgenerate

  assign line_req_idx = req_idx;   // 2-bit request line index (req_addr[3:2])

  // ==================== Output for Debugging ====================
  // BUG-002c: 63-bit packing — {state[1:0], tag[27:0], data[31:0], valid}
  generate
    for (genvar i = 0; i < LINES; i++) begin : debug_output
      assign line_out[i] = {line_state_reg[i], line_tag_reg[i],
                             line_data_reg[i], line_valid_reg[i]};
    end
  endgenerate

  // ==================== Synchronous Updates ====================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < LINES; i++) begin
        line_valid_reg[i] <= 1'b0;
        line_state_reg[i] <= 2'b00;  // I
        line_tag_reg[i]   <= 28'b0;
        line_data_reg[i]  <= 32'b0;
      end
    end else begin
      // Write path (from cache manager)
      for (int i = 0; i < LINES; i++) begin
        if (wr_we[i]) begin
          line_valid_reg[i] <= wr_valid;
          line_state_reg[i] <= wr_state;
          line_tag_reg[i]   <= wr_tag;
          line_data_reg[i]  <= wr_data;
        end

        // Invalidation path (from coherence controller)
        if (inv_we && (inv_idx == i[1:0])) begin
          line_valid_reg[i] <= 1'b0;
          line_state_reg[i] <= 2'b00;  // I
        end
      end
    end
  end

endmodule
