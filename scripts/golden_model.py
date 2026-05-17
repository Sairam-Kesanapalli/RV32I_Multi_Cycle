import re
import sys

# 1. Parse instruction_mem.v to extract hex opcodes
def parse_imem(path):
    instrs = []
    with open(path) as f:
        for line in f:
            m = re.search(r'32\'h([0-9a-fA-F]+)', line)
            if m:
                instrs.append(int(m.group(1), 16))
    return instrs

# 2. Tiny RV32I simulator
#    Models the same word-indexed memory as the RTL:
#    RTL uses memory[addr[ADDR_WIDTH+1:2]], i.e. word_index = (byte_addr >> 2) & 0xFF
MEM_DEPTH = 256

IMEM_DEPTH = 256

def simulate(instrs, max_cycles=800):
    """
    Cycle-accurate RV32I simulator.
    Counts clock cycles per instruction to match the RTL FSM:
      - R-Type, I-Type, LUI, AUIPC: 3 cycles (FETCH -> DECODE -> PC_INC)
      - Load:                        5 cycles (FETCH -> DECODE -> MEM_ADDR -> MEM_READ -> MEM_WB)
      - Store:                       4 cycles (FETCH -> DECODE -> MEM_ADDR -> MEM_WRITE)
      - Branch (not taken):          4 cycles (FETCH -> DECODE -> BRANCH_EX -> PC_INC)
      - Branch (taken):              3 cycles (FETCH -> DECODE -> BRANCH_EX)
      - JAL:                         3 cycles (FETCH -> DECODE -> JUMP_EX)
      - JALR:                        3 cycles (FETCH -> DECODE -> JALR_EX)
    """
    # Pad instruction memory to match RTL depth (unexecuted slots = NOP = 0x00000013)
    padded_imem = instrs[:] + [0x00000013] * (IMEM_DEPTH - len(instrs))
    regs = [0] * 32
    mem  = [None] * MEM_DEPTH  # None = uninitialized (matches RTL 'x')
    pc   = 0
    cycle = 0

    def sign_ext(val, bits):
        if val & (1 << (bits-1)):
            val -= (1 << bits)
        return val

    def word_index(byte_addr):
        """Mirror RTL: memory[addr[ADDR_WIDTH+1:2]] with ADDR_WIDTH=8"""
        return (byte_addr >> 2) & (MEM_DEPTH - 1)

    while cycle < max_cycles:
        idx = word_index(pc)
        instr = padded_imem[idx]
        opcode = instr & 0x7F
        rd     = (instr >> 7)  & 0x1F
        funct3 = (instr >> 12) & 0x7
        rs1    = (instr >> 15) & 0x1F
        rs2    = (instr >> 20) & 0x1F
        funct7 = (instr >> 25) & 0x7F
        i_imm  = sign_ext((instr >> 20), 12)
        s_imm  = sign_ext(((instr>>25)<<5)|((instr>>7)&0x1F), 12)
        b_imm  = sign_ext(((instr>>31)<<12)|((instr>>7&1)<<11)|
                          ((instr>>25&0x3F)<<5)|((instr>>8&0xF)<<1), 13)
        u_imm  = sign_ext((instr >> 12) << 12, 32)
        j_imm  = sign_ext(((instr>>31)<<20)|((instr>>12&0xFF)<<12)|
                          ((instr>>20&1)<<11)|((instr>>21&0x3FF)<<1), 21)

        regs[0] = 0  # x0 hardwired zero
        r1, r2  = regs[rs1], regs[rs2]
        next_pc = pc + 4
        instr_cycles = 3  # Default: R/I/LUI/AUIPC/JAL/JALR

        if opcode == 0x33:    # R-type (3 cycles)
            if   funct3==0: regs[rd] = (r1+r2 if funct7==0 else r1-r2) & 0xFFFFFFFF
            elif funct3==1: regs[rd] = (r1 << (r2 & 0x1F)) & 0xFFFFFFFF          # SLL
            elif funct3==2: regs[rd] = 1 if sign_ext(r1,32) < sign_ext(r2,32) else 0  # SLT
            elif funct3==3: regs[rd] = 1 if (r1 & 0xFFFFFFFF) < (r2 & 0xFFFFFFFF) else 0  # SLTU
            elif funct3==4: regs[rd] = (r1^r2) & 0xFFFFFFFF                       # XOR
            elif funct3==5:                                                        # SRL / SRA
                if funct7==0: regs[rd] = (r1 >> (r2 & 0x1F)) & 0xFFFFFFFF
                else:         regs[rd] = (sign_ext(r1,32) >> (r2 & 0x1F)) & 0xFFFFFFFF
            elif funct3==6: regs[rd] = (r1|r2) & 0xFFFFFFFF                       # OR
            elif funct3==7: regs[rd] = (r1&r2) & 0xFFFFFFFF                       # AND
            instr_cycles = 4  # FETCH -> DECODE -> EXEC_R -> PC_INC
        elif opcode == 0x13:  # I-type arithmetic (3 cycles)
            if   funct3==0: regs[rd] = (r1 + i_imm) & 0xFFFFFFFF                  # ADDI
            elif funct3==2: regs[rd] = 1 if sign_ext(r1, 32) < sign_ext(i_imm, 32) else 0  # SLTI
            elif funct3==3: regs[rd] = 1 if (r1 & 0xFFFFFFFF) < (i_imm & 0xFFFFFFFF) else 0  # SLTIU
            elif funct3==4: regs[rd] = (r1 ^ i_imm) & 0xFFFFFFFF                  # XORI
            elif funct3==6: regs[rd] = (r1 | i_imm) & 0xFFFFFFFF                  # ORI
            elif funct3==7: regs[rd] = (r1 & i_imm) & 0xFFFFFFFF                  # ANDI
            elif funct3==1: regs[rd] = (r1 << (i_imm & 0x1F)) & 0xFFFFFFFF        # SLLI
            elif funct3==5:                                                        # SRLI / SRAI
                if funct7==0: regs[rd] = (r1 >> (i_imm & 0x1F)) & 0xFFFFFFFF
                else:         regs[rd] = (sign_ext(r1,32) >> (i_imm & 0x1F)) & 0xFFFFFFFF
            instr_cycles = 4  # FETCH -> DECODE -> EXEC_I -> PC_INC
        elif opcode == 0x03:  # Load (LW) - 5 cycles
            addr = (r1 + i_imm) & 0xFFFFFFFF
            wi = word_index(addr)
            regs[rd] = mem[wi] if mem[wi] is not None else 0
            instr_cycles = 5  # FETCH -> DECODE -> MEM_ADDR -> MEM_READ -> MEM_WB
        elif opcode == 0x23:  # Store (SW) - 4 cycles
            addr = (r1 + s_imm) & 0xFFFFFFFF
            wi = word_index(addr)
            mem[wi] = r2 & 0xFFFFFFFF
            instr_cycles = 4  # FETCH -> DECODE -> MEM_ADDR -> MEM_WRITE
        elif opcode == 0x63:  # Branch
            taken = False
            if   funct3==0: taken = (r1==r2)
            elif funct3==1: taken = (r1!=r2)
            elif funct3==4: taken = (sign_ext(r1,32) < sign_ext(r2,32))
            elif funct3==5: taken = (sign_ext(r1,32) >= sign_ext(r2,32))
            elif funct3==6: taken = ((r1 & 0xFFFFFFFF) < (r2 & 0xFFFFFFFF))
            elif funct3==7: taken = ((r1 & 0xFFFFFFFF) >= (r2 & 0xFFFFFFFF))
            if taken:
                next_pc = pc + b_imm
                instr_cycles = 3  # FETCH -> DECODE -> BRANCH_EX (taken -> FETCH)
            else:
                instr_cycles = 4  # FETCH -> DECODE -> BRANCH_EX -> PC_INC
        elif opcode == 0x67:  # JALR - 3 cycles
            regs[rd] = (pc + 4) & 0xFFFFFFFF
            next_pc  = (r1 + i_imm) & 0xFFFFFFFE
            instr_cycles = 3  # FETCH -> DECODE -> JALR_EX
        elif opcode == 0x6F:  # JAL - 3 cycles
            regs[rd] = (pc + 4) & 0xFFFFFFFF
            next_pc  = pc + j_imm
            instr_cycles = 3  # FETCH -> DECODE -> JUMP_EX
        elif opcode == 0x37:  # LUI - 3 cycles
            regs[rd] = u_imm & 0xFFFFFFFF
            instr_cycles = 3  # FETCH -> DECODE -> PC_INC
        elif opcode == 0x17:  # AUIPC - 3 cycles
            regs[rd] = (pc + u_imm) & 0xFFFFFFFF
            instr_cycles = 3  # FETCH -> DECODE -> PC_INC
        else:
            instr_cycles = 3  # NOP / Unknown

        regs[0] = 0
        
        # Check if this instruction would exceed our cycle budget
        if cycle + instr_cycles > max_cycles:
            break
        
        pc = next_pc & 0xFFFFFFFF
        cycle += instr_cycles

    return regs, mem, pc

# 3. Emit expected_regs.hex for $readmemh
def emit_hex(regs, mem, pc, out_dir="."):
    import os
    with open(os.path.join(out_dir, "expected_regs.hex"), 'w') as f:
        for v in regs:
            f.write(f"{v:08x}\n")
    # Write word-indexed memory (matches RTL data_mem array indices 0..15)
    with open(os.path.join(out_dir, "expected_mem.hex"), 'w') as f:
        for i in range(16):
            val = mem[i]
            if val is None:
                f.write("xxxxxxxx\n")  # Uninitialized — matches RTL 'x'
            else:
                f.write(f"{val:08x}\n")
    with open(os.path.join(out_dir, "expected_pc.hex"), 'w') as f:
        f.write(f"{pc:08x}\n")
    print(f"[golden] PC={pc:#010x}  x1={regs[1]:#010x}  x2={regs[2]:#010x}")

if __name__ == "__main__":
    import os
    
    # Try to find the instruction_mem.v file gracefully if executed from different directories
    if os.path.exists("src/memory/instruction_mem.v"):
        imem_path = "src/memory/instruction_mem.v"
        out_dir = "tb"
    elif os.path.exists("../src/memory/instruction_mem.v"):
        imem_path = "../src/memory/instruction_mem.v"
        out_dir = "../tb"
    else:
        print("Cannot find instruction_mem.v")
        sys.exit(1)
        
    instrs = parse_imem(imem_path)
    regs, mem, pc = simulate(instrs)
    emit_hex(regs, mem, pc, out_dir)
