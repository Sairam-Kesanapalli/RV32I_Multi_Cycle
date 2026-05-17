`timescale 1ns/1ps
module rv32i_tb;
reg clk;
reg rst_n;


rv32i_single_cycle rv (
    .clk(clk),
    .rst_n(rst_n)
);

always #5 clk = ~clk;

    integer i;
    initial begin

       $dumpfile("RV32I_verification.vcd");
       $dumpvars;
       for (i = 0; i < 32; i = i + 1) begin
           $dumpvars(0, rv32i_tb.rv.rf.regs[i]);
       end
        clk = 0;
        rst_n = 0;
         #10;
        rst_n = 1;
        #400;
        $finish;
    end
endmodule
