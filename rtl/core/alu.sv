/**
 * @file alu.sv
 * @brief 32-bit Arithmetic Logic Unit for RV32I ISA
 * @project Dual-Core RV32I SoC with Coherent Memory Subsystem
 * @doc_ref logic_design/02_alu_logic.md, gate_level/01_alu_gate_level.md
 * @date Day 1, Task T1.7
 * 
 * Implements all RV32I arithmetic, logical, and shift operations.
 * Combinational logic: inputs → result in same cycle.
 */

module alu (
  input  logic [31:0] a,              // Operand A
  input  logic [31:0] b,              // Operand B
  input  logic [3:0]  func,           // ALU function select (from control_unit)
  output logic [31:0] result,         // 32-bit result
  output logic        zero            // 1 if result == 0 (branch condition)
);

  // ==================== Internal Signals ====================
  logic [31:0] sum;                   // Adder output
  logic [31:0] diff;                  // Subtractor output
  logic [31:0] sll_result;            // Shift left logical
  logic [31:0] srl_result;            // Shift right logical
  logic [31:0] sra_result;            // Shift right arithmetic
  logic [31:0] and_result;            // Bitwise AND
  logic [31:0] or_result;             // Bitwise OR
  logic [31:0] xor_result;            // Bitwise XOR
  logic        less;                  // a < b (signed)
  logic        less_u;                // a < b (unsigned)

  // ==================== Arithmetic Operations ====================

  // ADD / ADDI: result = a + b
  assign sum = a + b;

  // SUB: result = a - b (computed via b negation)
  assign diff = a - b;

  // ==================== Shift Operations ====================

  // SLL (Shift Left Logical): shift a left by b[4:0] positions
  // Implemented as cascaded MUXes: shift by 1, 2, 4, 8, 16 conditionally
  logic [31:0] shift_level_1, shift_level_2, shift_level_4, shift_level_8, shift_level_16;

  assign shift_level_1 = b[0] ? {a[30:0], 1'b0} : a;
  assign shift_level_2 = b[1] ? {shift_level_1[29:0], 2'b0} : shift_level_1;
  assign shift_level_4 = b[2] ? {shift_level_2[27:0], 4'b0} : shift_level_2;
  assign shift_level_8 = b[3] ? {shift_level_4[23:0], 8'b0} : shift_level_4;
  assign sll_result    = b[4] ? {shift_level_8[15:0], 16'b0} : shift_level_8;

  // SRL (Shift Right Logical): shift a right by b[4:0] positions (fill with 0s)
  logic [31:0] srl_level_1, srl_level_2, srl_level_4, srl_level_8, srl_level_16;

  assign srl_level_1 = b[0] ? {1'b0, a[31:1]} : a;
  assign srl_level_2 = b[1] ? {2'b0, srl_level_1[31:2]} : srl_level_1;
  assign srl_level_4 = b[2] ? {4'b0, srl_level_2[31:4]} : srl_level_2;
  assign srl_level_8 = b[3] ? {8'b0, srl_level_4[31:8]} : srl_level_4;
  assign srl_result  = b[4] ? {16'b0, srl_level_8[31:16]} : srl_level_8;

  // SRA (Shift Right Arithmetic): shift a right by b[4:0] positions (fill with sign bit)
  logic [31:0] sra_level_1, sra_level_2, sra_level_4, sra_level_8, sra_level_16;
  logic [7:0]  sign_ext_8;
  logic [15:0] sign_ext_16;

  assign sign_ext_8  = {8{a[31]}};
  assign sign_ext_16 = {16{a[31]}};

  assign sra_level_1 = b[0] ? {a[31], a[31:1]} : a;
  assign sra_level_2 = b[1] ? {{2{a[31]}}, sra_level_1[31:2]} : sra_level_1;
  assign sra_level_4 = b[2] ? {{4{a[31]}}, sra_level_2[31:4]} : sra_level_2;
  assign sra_level_8 = b[3] ? {{8{a[31]}}, sra_level_4[31:8]} : sra_level_4;
  assign sra_result  = b[4] ? {sign_ext_16, sra_level_8[31:16]} : sra_level_8;

  // ==================== Logical Operations ====================

  assign and_result = a & b;
  assign or_result  = a | b;
  assign xor_result = a ^ b;

  // ==================== Comparison Operations ====================

  // SLT (Set Less Than, signed): result = (a < b) ? 1 : 0
  // Implemented via subtraction: if a - b is negative (MSB=1), then a < b
  assign less = (a[31] ^ b[31]) ? a[31] : diff[31];  // XOR checks sign bits
                                                       // If signs differ, compare sign of a
                                                       // Otherwise use sign of diff

  // SLTU (Set Less Than Unsigned): result = (a < b) ? 1 : 0
  // Compare absolute difference magnitude
  assign less_u = (a < b);  // Direct unsigned comparison

  // ==================== Result Multiplexer ====================
  // func[3:0] encoding (from doc 02 §2.3):
  // 0000: ADD/ADDI
  // 0001: SUB
  // 0010: SLL
  // 0011: SLT
  // 0100: SLTU
  // 0101: XOR
  // 0110: SRL
  // 0111: SRA
  // 1000: AND
  // 1001: OR
  // 1010-1111: Reserved (default to ADD for safety)

  always_comb begin
    case (func)
      4'b0000: result = sum;        // ADD, ADDI
      4'b0001: result = diff;       // SUB
      4'b0010: result = sll_result; // SLL
      4'b0011: result = {{31{1'b0}}, less};     // SLT (sign-extended to 32-bit)
      4'b0100: result = {{31{1'b0}}, less_u};  // SLTU
      4'b0101: result = xor_result; // XOR
      4'b0110: result = srl_result; // SRL
      4'b0111: result = sra_result; // SRA
      4'b1000: result = and_result; // AND
      4'b1001: result = or_result;  // OR
      default: result = sum;        // Default to ADD (safe)
    endcase
  end

  // ==================== Zero Detection ====================
  // Used for branch conditions (BEQ, BNE, BLTU, BGE, etc.)
  assign zero = (result == 32'b0);

endmodule
