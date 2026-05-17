/*********************************************************************************
 * MULTI-CYCLE FSM CONTROL UNIT
 * -------------------------------------------------------------------------------
 * This acts as the "Traffic Cop" over multiple clock cycles. It explicitly
 * controls every multiplexer and register write-enable signal based on the
 * current stage of instruction execution (Fetch -> Decode -> Execute -> etc.)
 *********************************************************************************/
module control_unit (
    input clk,
    input rst_n,
    input [6:0] op_code,
    input branch_taken,

    output reg PCWrite,
    output reg IRWrite,
    output reg RegWrite,
    output reg MemRead,
    output reg MemWrite,
    output reg Branch,
    output reg Jump,
    output reg [1:0] ALUSrcA_ctrl,
    output reg [1:0] ALUSrcB_ctrl,
    output reg [1:0] PCSource_ctrl,
    output reg MemToReg,
    output reg [2:0] ALU_OP
);

    // =========================================================================
    // STATE DEFINITIONS
    // =========================================================================
    localparam FETCH      = 4'd0;
    localparam DECODE     = 4'd1;
    localparam EXEC_R     = 4'd2;
    localparam EXEC_I     = 4'd3;
    localparam MEM_ADDR   = 4'd4;
    localparam MEM_READ   = 4'd5;
    localparam MEM_WB     = 4'd6;
    localparam MEM_WRITE  = 4'd7;
    localparam BRANCH_EX  = 4'd8;
    localparam JUMP_EX    = 4'd9;
    localparam LUI_EX     = 4'd10;
    localparam AUIPC_EX   = 4'd11;
    localparam JALR_EX    = 4'd12;
    localparam PC_INC     = 4'd13;

    reg [3:0] current_state, next_state;

    // =========================================================================
    // STATE REGISTER UPDATE
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) current_state <= FETCH;
        else current_state <= next_state;
    end

    // =========================================================================
    // NEXT STATE LOGIC
    // =========================================================================
    always @(*) begin
        case(current_state)
            FETCH: next_state = DECODE;
            DECODE: begin
                case(op_code)
                    7'b0110011: next_state = EXEC_R;
                    7'b0010011: next_state = EXEC_I;
                    7'b0000011: next_state = MEM_ADDR; // LW
                    7'b0100011: next_state = MEM_ADDR; // SW
                    7'b1100011: next_state = BRANCH_EX;
                    7'b1101111: next_state = JUMP_EX;  // JAL
                    7'b1100111: next_state = JALR_EX;  // JALR
                    7'b0110111: next_state = LUI_EX;
                    7'b0010111: next_state = AUIPC_EX;
                    default: next_state = FETCH;
                endcase
            end
            EXEC_R:    next_state = PC_INC;
            EXEC_I:    next_state = PC_INC;
            MEM_ADDR: begin
                if (op_code == 7'b0000011) next_state = MEM_READ;
                else next_state = MEM_WRITE;
            end
            MEM_READ:  next_state = MEM_WB;
            MEM_WB:    next_state = FETCH;
            MEM_WRITE: next_state = FETCH;
            BRANCH_EX: begin
                if (branch_taken) next_state = FETCH;
                else next_state = PC_INC;
            end
            JUMP_EX:   next_state = FETCH;
            LUI_EX:    next_state = PC_INC;
            AUIPC_EX:  next_state = PC_INC;
            JALR_EX:   next_state = FETCH;
            PC_INC:    next_state = FETCH;
            default:   next_state = FETCH;
        endcase
    end

    // =========================================================================
    // OUTPUT CONTROL LOGIC
    // =========================================================================
    always @(*) begin
        // Default all signals to 0 to prevent accidental writes or latches
        PCWrite       = 0;
        IRWrite       = 0;
        RegWrite      = 0;
        MemRead       = 0;
        MemWrite      = 0;
        Branch        = 0;
        Jump          = 0;
        ALUSrcA_ctrl  = 2'b00;
        ALUSrcB_ctrl  = 2'b00;
        PCSource_ctrl = 2'b00;
        MemToReg      = 0;
        ALU_OP        = 3'd0;

        case(current_state)
            FETCH: begin
                IRWrite = 1;
            end

            DECODE: begin
                if (op_code == 7'b1100111 || op_code == 7'b1101111) begin
                    // For Jumps (JAL/JALR), we need to compute PC+4 to save in rd
                    // ALUOut = PC + 4
                    ALUSrcA_ctrl = 2'b00; // PC
                    ALUSrcB_ctrl = 2'b01; // 4
                    ALU_OP       = 3'd3;  // ADD
                end else begin
                    // Compute branch target early: ALUOut = PC + imm
                    ALUSrcA_ctrl = 2'b00; // PC
                    ALUSrcB_ctrl = 2'b10; // imm
                    ALU_OP       = 3'd3;  // ADD
                end
            end

            EXEC_R: begin
                // ALUOut = A op B
                ALUSrcA_ctrl = 2'b01; // A
                ALUSrcB_ctrl = 2'b00; // B
                ALU_OP       = 3'd2;  // R-Type
            end

            EXEC_I: begin
                // ALUOut = A op imm
                ALUSrcA_ctrl = 2'b01; // A
                ALUSrcB_ctrl = 2'b10; // imm
                ALU_OP       = 3'd0;  // I-Type
            end

            MEM_ADDR: begin
                // ALUOut = A + imm (Address calculation)
                ALUSrcA_ctrl = 2'b01; // A
                ALUSrcB_ctrl = 2'b10; // imm
                ALU_OP       = 3'd3;  // ADD
            end

            MEM_READ: begin
                MemRead = 1;
            end

            MEM_WB: begin
                RegWrite = 1;
                MemToReg = 1;         // Select MDR

                // Concurrent PC+4 Increment!
                ALUSrcA_ctrl = 2'b00; // PC
                ALUSrcB_ctrl = 2'b01; // 4
                ALU_OP       = 3'd3;  // ADD
                PCSource_ctrl= 2'b00; // alu_result
                PCWrite      = 1;
            end

            MEM_WRITE: begin
                MemWrite = 1;

                // Concurrent PC+4 Increment!
                ALUSrcA_ctrl = 2'b00; // PC
                ALUSrcB_ctrl = 2'b01; // 4
                ALU_OP       = 3'd3;  // ADD
                PCSource_ctrl= 2'b00; // alu_result
                PCWrite      = 1;
            end

            BRANCH_EX: begin
                // Compute A - B to set flags
                ALUSrcA_ctrl = 2'b01; // A
                ALUSrcB_ctrl = 2'b00; // B
                ALU_OP       = 3'd1;  // SUB for Branch
                Branch       = 1;
                if (branch_taken) begin
                    PCSource_ctrl = 2'b01; // ALUOut (which has PC+imm from DECODE)
                    PCWrite       = 1;
                end
            end

            JUMP_EX: begin
                // PC = PC + imm (using ALU), Reg = PC+4 (from ALUOut)
                ALUSrcA_ctrl = 2'b00; // PC
                ALUSrcB_ctrl = 2'b10; // imm
                ALU_OP       = 3'd3;  // ADD
                RegWrite     = 1;
                MemToReg     = 0;     // Writes ALUOut (PC+4 from DECODE)
                Jump         = 1;
                PCSource_ctrl= 2'b00; // alu_result (PC+imm)
                PCWrite      = 1;
            end

            JALR_EX: begin
                // PC = (A + imm) & ~1, Reg = PC+4 (from ALUOut)
                ALUSrcA_ctrl = 2'b01; // A
                ALUSrcB_ctrl = 2'b10; // imm
                ALU_OP       = 3'd3;  // ADD
                RegWrite     = 1;
                MemToReg     = 0;     // Writes ALUOut (PC+4 from DECODE)
                Jump         = 1;
                PCSource_ctrl= 2'b10; // alu_result & ~1
                PCWrite      = 1;
            end

            LUI_EX: begin
                // ALUOut = 0 + imm
                ALUSrcA_ctrl = 2'b10; // 0
                ALUSrcB_ctrl = 2'b10; // imm
                ALU_OP       = 3'd3;  // ADD
            end

            AUIPC_EX: begin
                // ALUOut = PC + imm (Already computed in DECODE!)
                // So we can just go straight to PC_INC and write back ALUOut!
            end

            PC_INC: begin
                // Write back for EXEC_R, EXEC_I, LUI, AUIPC
                if (op_code == 7'b0110011 || op_code == 7'b0010011 || op_code == 7'b0110111 || op_code == 7'b0010111) begin
                    RegWrite = 1;
                    MemToReg = 0;
                end

                // Increment PC
                ALUSrcA_ctrl = 2'b00; // PC
                ALUSrcB_ctrl = 2'b01; // 4
                ALU_OP       = 3'd3;  // ADD
                PCSource_ctrl= 2'b00; // alu_result
                PCWrite      = 1;
            end
        endcase
    end
endmodule
