# RISC-V RV32I Multi-Cycle Processor

A fully functional **multi-cycle RISC-V RV32I processor** implemented in synthesizable Verilog, featuring a Finite State Machine (FSM) control unit, a cycle-accurate Python golden model for automated verification, and a co-simulation SVT framework.

---

## Architecture Overview

Unlike a single-cycle design where each instruction completes in one clock cycle, this multi-cycle processor breaks instruction execution into **3–5 stages**, sharing hardware resources (ALU, memory) across cycles. This reduces the critical path and mirrors real-world CPU design principles.

### FSM Execution Stages

| State | Cycle | Description |
|---|---|---|
| `FETCH` | 1 | Fetch instruction from instruction memory into IR |
| `DECODE` | 2 | Decode opcode, read register file, compute immediate, calculate PC+Imm |
| `EXEC_R / EXEC_I` | 3 | Execute ALU operation for R-type or I-type instructions |
| `MEM_ADDR` | 3 | Compute memory address for Load/Store |
| `BRANCH_EX` | 3 | Evaluate branch condition |
| `JUMP_EX / JALR_EX` | 3 | Compute jump target |
| `MEM_READ` | 4 | Read data from memory (Load) |
| `MEM_WRITE` | 4 | Write data to memory (Store) |
| `MEM_WB` | 5 | Write loaded data back to register file |
| `PC_INC` | 3–4 | Increment PC and write ALU result to register file |

### Cycle Count Per Instruction

| Instruction Type | Cycles | States Traversed |
|---|---|---|
| R-Type (ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT) | 4 | FETCH → DECODE → EXEC_R → PC_INC |
| I-Type (ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI, SLTI) | 4 | FETCH → DECODE → EXEC_I → PC_INC |
| LUI / AUIPC | 3 | FETCH → DECODE → PC_INC |
| Load (LW) | 5 | FETCH → DECODE → MEM_ADDR → MEM_READ → MEM_WB |
| Store (SW) | 4 | FETCH → DECODE → MEM_ADDR → MEM_WRITE |
| Branch (taken) | 3 | FETCH → DECODE → BRANCH_EX |
| Branch (not taken) | 4 | FETCH → DECODE → BRANCH_EX → PC_INC |
| JAL | 3 | FETCH → DECODE → JUMP_EX |
| JALR | 3 | FETCH → DECODE → JALR_EX |

---

## Supported Instructions

### R-Type (Register-Register)
`ADD`, `SUB`, `AND`, `OR`, `XOR`, `SLL`, `SRL`, `SRA`, `SLT`, `SLTU`

### I-Type (Register-Immediate)
`ADDI`, `ANDI`, `ORI`, `XORI`, `SLLI`, `SRLI`, `SRAI`, `SLTI`, `SLTIU`

### Load / Store
`LW`, `SW`

### Branch
`BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`

### Jump
`JAL`, `JALR`

### Upper Immediate
`LUI`, `AUIPC`

---

## Directory Structure

```
RV32I_Multi_Cycle/
├── src/
│   ├── core/
│   │   ├── rv32i_multi_cycle.v   # Top-level datapath (PC, IR, ALU muxes, state registers)
│   │   ├── control_unit.v        # FSM control unit (12 states)
│   │   ├── alu_control.v         # ALU operation decoder
│   │   ├── imm_gen.v             # Immediate generator (R/I/S/B/U/J formats)
│   │   └── register.v           # 32x32 register file (x0 hardwired to zero)
│   ├── alu/
│   │   ├── ALU_n_bit.v           # Parameterized N-bit ALU
│   │   └── full_adder_n_bit.v    # N-bit ripple-carry adder
│   └── memory/
│       ├── instruction_mem.v     # Instruction memory (ROM, hardcoded program)
│       └── data_mem.v            # Data memory (256-word, synchronous write)
├── tb/
│   ├── rv32i_tb.v                # Basic simulation testbench (VCD dump)
│   ├── svt_tb.v                  # Software Verification Testbench (auto-compare)
│   └── test_lw_sw.v              # Debug testbench for Load/Store
├── scripts/
│   └── golden_model.py           # Cycle-accurate Python RV32I ISS
├── docs/
│   ├── formats.txt               # RV32I instruction encoding formats
│   ├── instructions.txt          # Hex instruction listing
│   └── DATAPATH                  # Datapath architecture notes
├── Makefile                      # Build automation
└── README.md
```

---

## Key Design Decisions

- **Harvard Architecture**: Separate instruction and data memories for simplified verification. Instruction memory is read-only (ROM); data memory supports synchronous writes and combinational reads.
- **Instruction Register (IR)**: The fetched instruction is latched in `IR` during `FETCH` to keep the opcode stable as the PC advances in subsequent cycles.
- **State Registers**: Intermediate values (`A`, `B`, `ALUOut`, `MDR`) are latched at each cycle boundary to hold data across the multi-cycle pipeline.
- **Early LUI/AUIPC**: These instructions compute their results during `DECODE` by leveraging the immediate generator, saving one execution cycle.

---

## Prerequisites

- [Icarus Verilog](http://iverilog.icarus.com/) (`iverilog` ≥ 12.0)
- [GTKWave](http://gtkwave.sourceforge.net/) (optional, for viewing VCD waveforms)
- Python 3.6+ (for the golden model / SVT verification)

---

## Quick Start

### Build & Simulate
```bash
make            # Compile and run the basic testbench
```

### Run the SVT (Software Verification Testbench)
```bash
make svt        # Auto-generates golden model → compiles → simulates → compares
```

### Run the CI Regression Suite
```bash
make regression # Runs automated testing for all test folders (I-Type, R-Type, U-Type, J-Type)
```

Expected output on success:
```
=======================================================
              RUNNING REGRESSION SUITE                 
=======================================================
Running tests/I-Type...
[PASS] I-Type
Running tests/J-Type...
[PASS] J-Type
Running tests/R-Type...
[PASS] R-Type
Running tests/U-Type...
[PASS] U-Type
=======================================================
```

### Other Targets
```bash
make compile    # Compile only (no simulation)
make sim        # Compile + simulate the main testbench
make debug      # Run the Load/Store debug testbench
make svt_golden # Generate golden .hex files only (without running RTL sim)
make clean      # Remove all generated files (binaries, VCD, hex)
```

### View Waveforms
```bash
gtkwave RV32I_verification.vcd    # Main testbench waveform
gtkwave SVT_verification.vcd      # SVT testbench waveform
```

---

## Continuous Integration (CI) & Regression Testing

To ensure code stability and facilitate rapid hardware iteration, a robust, automated Regression Testing and Continuous Integration system has been established.

### 1. Regression Suite Structure
Individual tests are placed under the `tests/` directory:
- **`tests/I-Type`**: Immediate-register arithmetic and logical operations (`ADDI`, `SLLI`, `SLTI`, etc.).
- **`tests/R-Type`**: Register-register operations (`ADD`, `SUB`, `SLL`, `XOR`, etc.).
- **`tests/U-Type`**: Upper immediate instructions (`LUI`, `AUIPC`).
- **`tests/J-Type`**: Unconditional Jumps (`JAL`).

Each subdirectory contains a **`program.hex`** file containing the compiled raw hexadecimal instructions. When you run `make regression`:
1. The Python Instruction Set Simulator (ISS) evaluates the hex file.
2. It auto-generates `expected_regs.hex`, `expected_mem.hex`, and `expected_pc.hex` directly inside that test's directory.
3. The RTL simulator dynamically loads the program via `$readmemh` (using the `+TEST_DIR` argument), simulates, and compares actual outputs vs expected outputs.

### 2. GitHub Actions Integration
A GitHub Actions workflow (`.github/workflows/makefile.yml`) is fully integrated. On every `push` or `pull_request` to the `main` branch, the CI:
1. Provisions a clean Ubuntu environment.
2. Installs `iverilog` and `python3`.
3. Runs `make svt` and `make regression`.
4. Uses exit-status code tracking (`exit $$failed`) to block buggy merges or commits from entering the main codebase.

---

## Verification Framework

This project uses a **co-simulation approach** for verification — a Python Instruction Set Simulator (ISS) serves as the golden reference model.

### How It Works

```
instruction_mem.v
      │
      ├──→ RTL (iverilog/vvp) ────→ actual register/memory/PC state
      │
      └──→ Python ISS ───────────→ expected register/memory/PC state
                                            │
                                            ▼
                                   auto-generate
                               expected_regs.hex
                               expected_mem.hex
                               expected_pc.hex
                                            │
                                            ▼
                                  svt_tb.v ($readmemh)
                                  compares actual vs expected
                                            │
                                            ▼
                                   [SVT PASS] or [SVT FAIL]
```

### Key Features

- **Cycle-Accurate**: The Python ISS counts clock cycles per instruction type, matching the RTL FSM exactly. Both ISS and RTL are guaranteed to be at the same instruction boundary at any given cycle count.
- **Automatic**: Change the program in `instruction_mem.v` and just run `make svt` — the golden model auto-regenerates expected results.
- **Memory Model Parity**: The ISS uses identical word-indexed addressing (`(addr >> 2) & 0xFF`) as the RTL, including correct handling of uninitialized memory (`x` values).

---

## Modifying the Program

The test program is hardcoded in `src/memory/instruction_mem.v`. To run a different program:

1. Replace the hex values in `instruction_mem.v` with your assembled RV32I instructions.
2. Run `make svt` — the Python ISS will automatically parse the new instructions, simulate them, and verify the RTL matches.

---

## Generated Files (Auto-Cleaned)

These files are generated during simulation and are safe to delete. `make clean` removes all of them:

| File | Source | Purpose |
|---|---|---|
| `rv32i_sim` | `make compile` | Compiled simulation binary |
| `debug_sim` | `make debug` | Debug testbench binary |
| `svt_sim` | `make svt` | SVT testbench binary |
| `golden_sim` | calibration | Temporary golden extraction binary |
| `*.vcd` | `vvp` | Waveform dump files |
| `tb/expected_regs.hex` | `golden_model.py` | Expected register state |
| `tb/expected_mem.hex` | `golden_model.py` | Expected memory state |
| `tb/expected_pc.hex` | `golden_model.py` | Expected program counter |
