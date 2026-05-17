module instruction_memory #(
    parameter XLEN = 32,
    parameter DEPTH = 256
)(
    input [XLEN-1:0] addr,
    output [31:0] instr
);

    localparam ADDR_WIDTH = $clog2(DEPTH);

    // INSTRUCTION MEMORY (EACH INSTRUCTION = 32 BITS)
    reg [XLEN-1:0] instr_memory [0:DEPTH-1];


    initial begin
        instr_memory[0]   = 32'h00a00093;
        instr_memory[1]   = 32'h00500113;
        instr_memory[2]   = 32'h0030f193;
        instr_memory[3]   = 32'h00816213;
        instr_memory[4]   = 32'h00f0c293;
        instr_memory[5]   = 32'h00111313;
        instr_memory[6]   = 32'h0010d393;
        instr_memory[7]   = 32'h4010d413;
        instr_memory[8]   = 32'h00a12493;
        instr_memory[9]   = 32'h00208533;
        instr_memory[10]  = 32'h402085b3;
        instr_memory[11]  = 32'h0020f633;
        instr_memory[12]  = 32'h0020e6b3;
        instr_memory[13]  = 32'h0020c733;
        instr_memory[14]  = 32'h009117b3;
        instr_memory[15]  = 32'h0090d833;
        instr_memory[16]  = 32'h4090d8b3;
        instr_memory[17]  = 32'h00112933;
        instr_memory[18]  = 32'h10010a37;
        instr_memory[19]  = 32'h00aa2023;
        instr_memory[20]  = 32'h000a2983;
        instr_memory[21]  = 32'h00108463;
        instr_memory[22]  = 32'h06400a93;
        instr_memory[23]  = 32'h00209463;
        instr_memory[24]  = 32'h0c800b13;
        instr_memory[25]  = 32'h00114463;
        instr_memory[26]  = 32'h12c00b93;
        instr_memory[27]  = 32'h0020d463;
        instr_memory[28]  = 32'h19000c13;
        instr_memory[29]  = 32'h00800cef;
        instr_memory[30]  = 32'h1f400d13;
        instr_memory[31]  = 32'h03700d13;
        instr_memory[32]  = 32'h00400db7;
        instr_memory[33]  = 32'h060d8d93;
        instr_memory[34]  = 32'h000d8e67;
        instr_memory[35]  = 32'h07b00e93;
        instr_memory[36]  = 32'h04d00e93;
    end

    assign instr = instr_memory[addr[ADDR_WIDTH+1:2]];

endmodule
