# Core RTL Quick Reference

**Day 1 Deliverable Quick Lookup**

---

## Module Signatures

### alu.sv
```verilog
module alu (
  input  logic [31:0] a,         // Operand A
  input  logic [31:0] b,         // Operand B
  input  logic [3:0]  func,      // Opcode: 0=ADD, 1=SUB, 2=SLL, ...
  output logic [31:0] result,    // Result
  output logic        zero       // Branch flag
);
```

**func[3:0] Encoding:**
| func | Opcode | Mnemonic | Operation |
|------|--------|----------|-----------|
| 4'b0000 | R/I(000/0) | ADD/ADDI | result = a + b |
| 4'b0001 | R(000/20) | SUB | result = a - b |
| 4'b0010 | I(001)/R(001/00) | SLL | result = a << b[4:0] |
| 4'b0011 | I(010)/R(010) | SLT | result = (a < b signed) ? 1 : 0 |
| 4'b0100 | I(011)/R(011) | SLTU | result = (a < b unsigned) ? 1 : 0 |
| 4'b0101 | I(100)/R(100) | XOR | result = a ^ b |
| 4'b0110 | I(101)/R(101/00) | SRL | result = a >> b[4:0] (logical) |
| 4'b0111 | I(101)/R(101/20) | SRA | result = a >> b[4:0] (arith) |
| 4'b1000 | I(111)/R(111) | AND | result = a & b |
| 4'b1001 | I(110)/R(110) | OR | result = a \| b |

---

### reg_file.sv
```verilog
module reg_file (
  input  logic        clk,       // Write clock
  input  logic        rst_n,     // Async reset
  input  logic [4:0]  wa,        // Write address (x0-x31)
  input  logic [31:0] wd,        // Write data
  input  logic        we,        // Write enable
  input  logic [4:0]  ra,        // Read address A
  output logic [31:0] rd_a,      // Read data A
  input  logic [4:0]  rb,        // Read address B
  output logic [31:0] rd_b       // Read data B
);
```

**Behavior:**
- x0: Always returns 0, writes ignored
- x1–x31: Normal read/write
- Write on posedge clk (synchronous)
- Reads combinational (async)

---

### control_unit.sv
```verilog
module control_unit (
  input  logic [31:0] instr,            // Instruction word
  output logic [3:0]  alu_func,         // ALU opcode
  output logic        rf_we,            // RF write enable
  output logic [4:0]  rf_wa,            // RF write address
  output logic [1:0]  rf_wd_sel,        // Write-back source
  output logic        dmem_req,         // Data mem request
  output logic        dmem_we,          // Data mem write enable
  output logic [1:0]  pc_sel,           // PC mux select
  output logic [31:0] imm,              // Sign-extended immediate
  output logic [3:0]  ls_ctrl,          // Load/store control
  output logic        is_branch,        // Is branch inst
  output logic        is_jump           // Is jump inst
);
```

**rf_wd_sel[1:0] Encoding:**
| sel | Source |
|-----|--------|
| 00 | ALU result |
| 01 | Load data |
| 10 | PC+4 (for JAL/JALR) |
| 11 | Reserved |

**pc_sel[1:0] Encoding:**
| sel | Source |
|-----|--------|
| 00 | PC+4 (sequential) |
| 01 | PC+imm (branch/JAL) |
| 10 | RS1+imm (JALR) |
| 11 | Reset (0x0) |

**ls_ctrl[3:0] (Load/Store):**
```
[3] = 0 for load, 1 for store
[2:0] = size (from func3):
  001 = byte
  010 = halfword
  011 = word
  100 = byte unsigned
  101 = halfword unsigned
```

---

### pc_logic.sv
```verilog
module pc_logic (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [31:0] pc_current,       // Current PC
  input  logic [31:0] imm,              // Immediate offset
  input  logic [31:0] rs1_data,         // For JALR
  input  logic [1:0]  pc_sel,           // Mux select (above)
  input  logic        alu_zero,         // Branch condition
  input  logic        branch_type,      // Branch type
  output logic [31:0] pc_next,          // Next PC (registered)
  output logic [31:0] pc_plus_4         // PC+4
);
```

**Combinational (available same cycle):**
- pc_plus_4 = pc_current + 4

**Registered (updated at posedge clk):**
- pc_next ← mux output (based on pc_sel)

---

### rv32i_core.sv (Top-Level CPU)
```verilog
module rv32i_core #(
  parameter RESET_PC = 32'h0000_0000
) (
  input  logic        clk,
  input  logic        rst_n,
  
  // Instruction Memory (async read)
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,
  
  // Data Memory (req/ack)
  output logic        dmem_req,
  output logic        dmem_we,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  output logic [3:0]  dmem_wmask,
  input  logic [31:0] dmem_rdata,
  input  logic        dmem_ack,
  input  logic        dmem_err
);
```

**Datapath Flow:**
```
PC → I-SRAM (async read)
↓
Instr → ControlUnit (decode)
↓
RF read A, RF read B (async)
↓
ALU operation (comb)
↓
Write-back mux (select source)
↓
Register file write (sync @ posedge clk)
↓
PC update (sync @ posedge clk)
```

**FSM (RUN/STALL_MEM):**
```
RUN:
  - Fetch & execute
  - If dmem_req & !dmem_ack: → STALL_MEM
  - Else: remain in RUN

STALL_MEM:
  - Hold core state
  - Wait for dmem_ack
  - On dmem_ack: → RUN
```

---

### i_sram.sv (Instruction Memory)
```verilog
module i_sram #(
  parameter DEPTH = 256,
  parameter WIDTH = 32,
  parameter INIT_FILE = ""
) (
  input  logic                clk,
  input  logic                rst_n,
  
  // Read (async)
  input  logic [$clog2(DEPTH)-1:0] raddr,
  output logic [WIDTH-1:0]         rdata,
  
  // Write (sync, for test only)
  input  logic [$clog2(DEPTH)-1:0] waddr,
  input  logic [WIDTH-1:0]         wdata,
  input  logic                     we
);
```

**Behavior:**
- Asynchronous read: rdata = mem[raddr] (combinational)
- Synchronous write: mem[waddr] ← wdata @ posedge clk (if we)
- Optional init from hex file: $readmemh(INIT_FILE, mem)

---

## Critical Code Sections

### ALU Barrel Shifter (SLL)
```verilog
// Cascade 5 levels: shift by 1, 2, 4, 8, 16 conditionally
assign shift_level_1 = b[0] ? {a[30:0], 1'b0}   : a;
assign shift_level_2 = b[1] ? {shift_level_1[29:0], 2'b0}   : shift_level_1;
assign shift_level_4 = b[2] ? {shift_level_2[27:0], 4'b0}   : shift_level_2;
assign shift_level_8 = b[3] ? {shift_level_4[23:0], 8'b0}   : shift_level_4;
assign sll_result    = b[4] ? {shift_level_8[15:0], 16'b0}  : shift_level_8;
```

### Branch Condition Resolution
```verilog
always_comb begin
  branch_taken = 1'b0;
  if (is_branch) begin
    case (func3)
      3'b000: branch_taken = alu_zero;        // BEQ
      3'b001: branch_taken = ~alu_zero;       // BNE
      3'b100: branch_taken = alu_result[0];   // BLT (SLT result)
      3'b101: branch_taken = ~alu_result[0];  // BGE
      3'b110: branch_taken = alu_result[0];   // BLTU
      3'b111: branch_taken = ~alu_result[0];  // BGEU
      default: branch_taken = 1'b0;
    endcase
  end
end
```

### Load Data Sign-Extension
```verilog
case (func3)
  3'b000: // LB (byte, signed)
    dmem_rdata_resized = {{24{dmem_rdata[byte_idx*8+7]}}, dmem_rdata[byte_idx*8+:8]};
  3'b001: // LH (halfword, signed)
    dmem_rdata_resized = {{16{dmem_rdata[hw_idx*16+15]}}, dmem_rdata[hw_idx*16+:16]};
  3'b010: // LW (word)
    dmem_rdata_resized = dmem_rdata;
  3'b100: // LBU (byte, unsigned)
    dmem_rdata_resized = {24'b0, dmem_rdata[byte_idx*8+:8]};
  3'b101: // LHU (halfword, unsigned)
    dmem_rdata_resized = {16'b0, dmem_rdata[hw_idx*16+:16]};
endcase
```

### Store Data Rotation
```verilog
logic [1:0] addr_offset = alu_result[1:0];
case (func3)
  3'b000: // SB (byte)
    begin
      dmem_wmask_processed = 4'b0001 << addr_offset;
      dmem_wdata_processed = rs2_data << (addr_offset * 8);
    end
  3'b001: // SH (halfword)
    begin
      dmem_wmask_processed = 4'b0011 << {addr_offset[1], 1'b0};
      dmem_wdata_processed = rs2_data << {addr_offset[1], 4'b0};
    end
  3'b010: // SW (word)
    begin
      dmem_wmask_processed = 4'b1111;
      dmem_wdata_processed = rs2_data;
    end
endcase
```

---

## Integration Checklist for Day 2+

When integrating rv32i_core with cache/coherence subsystem:

- [ ] PC is word-addressed (imem_addr[31:2] selects word in I-SRAM)
- [ ] dmem_addr drives cache manager address (byte-addressed)
- [ ] dmem_wmask is byte mask (bit 0 = byte 0, etc.)
- [ ] dmem_rdata must be captured when dmem_ack is asserted
- [ ] dmem_err during load: no register writeback, PC still advances
- [ ] rst_n is async assert, sync release (use 2-FF synchronizer at SoC top)
- [ ] All combinational paths: I-SRAM, ALU, RegisterFile reads
- [ ] All sequential paths: PC register, RF write, Core FSM register

---

## Simulation / Debug Tips

### Monitoring Core State in Testbench
```verilog
$display("PC=0x%08x | instr=0x%08x | x[rd]=0x%08x | dmem_req=%b ack=%b",
         u_core.pc_current,
         u_core.instr,
         u_core.u_rf.regs[rd_addr],
         dmem_req, dmem_ack);
```

### Inspecting Register File
```verilog
$display("Registers after cycle:");
for (int i = 1; i < 32; i++)
  if (u_core.u_rf.regs[i] != 0)
    $display("  x%0d = 0x%08x", i, u_core.u_rf.regs[i]);
```

### Checking ALU Output
```verilog
$display("ALU: a=0x%08x, b=0x%08x, func=%b → result=0x%08x, zero=%b",
         u_core.alu_operand_a, u_core.alu_operand_b, 
         alu_func, alu_result, alu_zero);
```

---

## Common Bugs & Fixes

| Bug | Symptom | Fix |
|-----|---------|-----|
| **Immediate sign-extension wrong** | ADDI x1, x0, -1 gives wrong value | Check imm_i_ext: `{{20{imm_i[11]}}, imm_i}` |
| **Branch always taken** | BEQ/BNE execute same as BLT | Check func3 in branch_taken logic; verify alu_zero for BEQ |
| **x0 not hardwired** | x0 register holds value instead of 0 | Check reg_file.sv: `rd_a = (ra == 5'b0) ? 32'b0 : regs[ra]` |
| **Load data stale** | LW returns old data | Ensure dmem_rdata_resized captured at dmem_ack, not combinationally |
| **PC stuck** | Core hangs, PC doesn't advance | Check dmem_ack timeout; verify FSM transitions in RUN/STALL_MEM |
| **Shift amount ignored** | SLL x1, x2, 5 shifts by x2, not 5 | For I-type shift: pass immediate as shift amount, not rs2_data |

---

## Links to Detailed Docs

| For | See |
|-----|-----|
| ALU truth table | `logic_design/02_alu_logic.md` |
| Datapath detail | `logic_design/03_core_datapath_and_control.md` |
| FSM states | `logic_design/03_core_datapath_and_control.md` §5 |
| Instruction decode table | `logic_design/03_core_datapath_and_control.md` §4 |
| Gate-level circuits | `logic_design/gate_level/01-03_*.md` |
| Integration | `logic_design/12_integration_logic.md` |
| Verification | `logic_design/13_working_logic_scenarios.md` |

---

**Last Updated:** September 6, 2026  
**Version:** 1.0  
**Ready for:** Day 2 Cache Integration

