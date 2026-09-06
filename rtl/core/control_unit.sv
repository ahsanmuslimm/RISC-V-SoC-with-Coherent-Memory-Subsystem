/**
 * @file control_unit.sv
 * @brief RV32I Instruction Decoder & Control Signal Generator
 * @project Dual-Core RV32I SoC with Coherent Memory Subsystem
 * @doc_ref logic_design/03_core_datapath_and_control.md, gate_level/03_control_unit_gate_level.md
 * @date Day 1, Task T1.9
 * 
 * Decodes 32-bit RV32I instruction into control signals.
 * Supports all RV32I base-integer instructions (37 total).
 * Generates ALU function, register file controls, memory controls, PC mux select, immediate value.
 */

module control_unit (
  input  logic [31:0] instr,            // Instruction word (from I-SRAM)
  output logic [3:0]  alu_func,         // ALU function select
  output logic        rf_we,            // Register file write enable
  output logic [4:0]  rf_wa,            // Register file write address (rd)
  output logic [1:0]  rf_wd_sel,        // Write-back source select
  output logic        dmem_req,         // Data memory request
  output logic        dmem_we,          // Data memory write enable (1=store, 0=load)
  output logic [1:0]  pc_sel,           // PC source select
  output logic [31:0] imm,              // Sign-extended immediate
  output logic [3:0]  ls_ctrl,          // Load/store control (size + signed)
  output logic        is_branch,        // Is branch instruction (for branch resolution)
  output logic        is_jump           // Is jump instruction (JAL/JALR)
);

  // ==================== Instruction Field Extraction ====================
  logic [6:0]  opcode;
  logic [4:0]  rd;
  logic [2:0]  func3;
  logic [4:0]  rs1;
  logic [4:0]  rs2;
  logic [6:0]  func7;
  logic [11:0] imm_i;
  logic [11:0] imm_s;
  logic [12:0] imm_b;
  logic [19:0] imm_u;
  logic [20:0] imm_j;

  assign opcode = instr[6:0];
  assign rd     = instr[11:7];
  assign func3  = instr[14:12];
  assign rs1    = instr[19:15];
  assign rs2    = instr[24:20];
  assign func7  = instr[31:25];

  // Immediate extraction (bit positions per RV32I spec)
  assign imm_i = instr[31:20];                      // I-type
  assign imm_s = {instr[31:25], instr[11:7]};      // S-type
  assign imm_b = {instr[31], instr[7], instr[30:25], instr[11:8]};  // B-type
  assign imm_u = instr[31:12];                      // U-type (upper 20 bits)
  assign imm_j = {instr[31], instr[19:12], instr[20], instr[30:21]};  // J-type

  // ==================== Sign Extension ====================
  // Extend immediates to 32-bit with sign extension
  logic [31:0] imm_i_ext;
  logic [31:0] imm_s_ext;
  logic [31:0] imm_b_ext;
  logic [31:0] imm_u_ext;
  logic [31:0] imm_j_ext;

  assign imm_i_ext = {{20{imm_i[11]}}, imm_i};
  assign imm_s_ext = {{20{imm_s[11]}}, imm_s};
  assign imm_b_ext = {{19{imm_b[12]}}, imm_b, 1'b0};  // B-type << 1 (for branch offset)
  assign imm_u_ext = {imm_u, 12'b0};                   // U-type << 12
  assign imm_j_ext = {{11{imm_j[20]}}, imm_j, 1'b0};  // J-type << 1 (for jump offset)

  // ==================== Instruction Decode ====================
  // Full case statement covering all RV32I opcodes and sub-opcodes

  always_comb begin
    // Default values (invalid instruction behavior)
    alu_func    = 4'b0000;  // ADD (safe default)
    rf_we       = 1'b0;
    rf_wa       = 5'b0;
    rf_wd_sel   = 2'b00;    // 00=ALU, 01=load, 10=PC+4, 11=reserved
    dmem_req    = 1'b0;
    dmem_we     = 1'b0;
    pc_sel      = 2'b00;    // 00=PC+4, 01=PC+imm, 10=RS1+imm, 11=reset
    imm         = 32'b0;
    ls_ctrl     = 4'b0;     // Load/store size (001=byte, 010=halfword, 011=word)
    is_branch   = 1'b0;
    is_jump     = 1'b0;

    case (opcode)

      // ==================== I-TYPE (Immediate Arithmetic) ====================
      7'b0010011: begin  // ADDI, SLTI, SLTIU, ANDI, ORI, XORI, SLLI, SRLI, SRAI
        rf_we     = 1'b1;
        rf_wa     = rd;
        rf_wd_sel = 2'b00;  // ALU result
        imm       = imm_i_ext;

        case (func3)
          3'b000: begin  // ADDI
            alu_func = 4'b0000;  // ADD
          end
          3'b001: begin  // SLLI
            alu_func = 4'b0010;  // SLL
            imm      = {27'b0, rs2};  // Shift amount in rs2 field
          end
          3'b010: begin  // SLTI (signed less than immediate)
            alu_func = 4'b0011;  // SLT
          end
          3'b011: begin  // SLTIU (unsigned less than immediate)
            alu_func = 4'b0100;  // SLTU
          end
          3'b100: begin  // XORI
            alu_func = 4'b0101;  // XOR
          end
          3'b101: begin  // SRLI / SRAI
            imm = {27'b0, rs2};  // Shift amount
            if (func7[5]) begin
              alu_func = 4'b0111;  // SRA
            end else begin
              alu_func = 4'b0110;  // SRL
            end
          end
          3'b110: begin  // ORI
            alu_func = 4'b1001;  // OR
          end
          3'b111: begin  // ANDI
            alu_func = 4'b1000;  // AND
          end
        endcase
      end

      // ==================== R-TYPE (Register Arithmetic) ====================
      7'b0110011: begin  // ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, AND, OR
        rf_we     = 1'b1;
        rf_wa     = rd;
        rf_wd_sel = 2'b00;  // ALU result
        imm       = {27'b0, rs2};  // rs2 as shift amount / ALU operand

        case ({func7[5], func3})
          4'b0000: alu_func = 4'b0000;  // ADD
          4'b1000: alu_func = 4'b0001;  // SUB
          4'b0001: alu_func = 4'b0010;  // SLL
          4'b0010: alu_func = 4'b0011;  // SLT
          4'b0011: alu_func = 4'b0100;  // SLTU
          4'b0100: alu_func = 4'b0101;  // XOR
          4'b0101: alu_func = 4'b0110;  // SRL
          4'b1101: alu_func = 4'b0111;  // SRA
          4'b0110: alu_func = 4'b1001;  // OR
          4'b0111: alu_func = 4'b1000;  // AND
          default: alu_func = 4'b0000;  // ADD (safe)
        endcase
      end

      // ==================== LOAD (I-TYPE variant) ====================
      7'b0000011: begin  // LB, LH, LW, LBU, LHU
        rf_we     = 1'b1;
        rf_wa     = rd;
        rf_wd_sel = 2'b01;  // Load data
        dmem_req  = 1'b1;
        dmem_we   = 1'b0;   // Read
        alu_func  = 4'b0000;  // ADD (for address calculation)
        imm       = imm_i_ext;
        ls_ctrl   = {1'b0, func3};  // Load control: width + signedness in func3

        // func3 encoding:
        // 000 = LB (byte, signed)
        // 001 = LH (halfword, signed)
        // 010 = LW (word, no extension)
        // 100 = LBU (byte, unsigned)
        // 101 = LHU (halfword, unsigned)
      end

      // ==================== STORE (S-TYPE) ====================
      7'b0100011: begin  // SB, SH, SW
        dmem_req  = 1'b1;
        dmem_we   = 1'b1;   // Write
        alu_func  = 4'b0000;  // ADD (for address calculation)
        imm       = imm_s_ext;
        ls_ctrl   = {1'b1, func3};  // Store control: width in func3

        // func3 encoding:
        // 000 = SB (byte)
        // 001 = SH (halfword)
        // 010 = SW (word)
      end

      // ==================== BRANCH (B-TYPE) ====================
      7'b1100011: begin  // BEQ, BNE, BLT, BGE, BLTU, BGEU
        is_branch = 1'b1;
        alu_func  = 4'b0001;  // SUB (for comparison)
        imm       = imm_b_ext;
        pc_sel    = 2'b01;   // PC + immediate (will be muxed based on branch condition)

        // Branch condition is resolved by comparing register values in ALU
        // Control logic elsewhere checks if branch is taken
      end

      // ==================== JAL (J-TYPE) ====================
      7'b1101111: begin  // JAL
        is_jump   = 1'b1;
        rf_we     = 1'b1;
        rf_wa     = rd;
        rf_wd_sel = 2'b10;  // PC + 4 (link register)
        pc_sel    = 2'b01;   // PC + imm_j
        imm       = imm_j_ext;
      end

      // ==================== JALR (I-TYPE variant) ====================
      7'b1100111: begin  // JALR
        is_jump   = 1'b1;
        rf_we     = 1'b1;
        rf_wa     = rd;
        rf_wd_sel = 2'b10;  // PC + 4
        pc_sel    = 2'b10;   // RS1 + imm
        alu_func  = 4'b0000;  // ADD
        imm       = imm_i_ext;
      end

      // ==================== LUI (U-TYPE) ====================
      7'b0110111: begin  // LUI
        rf_we     = 1'b1;
        rf_wa     = rd;
        rf_wd_sel = 2'b00;  // ALU result
        alu_func  = 4'b1001;  // OR (to place imm in upper 20 bits, OR with 0)
        imm       = imm_u_ext;
      end

      // ==================== AUIPC (U-TYPE) ====================
      7'b0010111: begin  // AUIPC (Add Upper Immediate to PC)
        rf_we     = 1'b1;
        rf_wa     = rd;
        rf_wd_sel = 2'b00;  // ALU result
        alu_func  = 4'b0000;  // ADD (PC + upper imm)
        imm       = imm_u_ext;
      end

      // ==================== Invalid Opcode ====================
      default: begin
        // All fields already set to safe defaults
      end

    endcase
  end

endmodule
