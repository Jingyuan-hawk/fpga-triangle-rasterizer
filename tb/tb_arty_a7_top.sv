`timescale 1ns/1ps
module tb_arty_a7_top;
    logic CLK100MHZ = 0;
    always #5 CLK100MHZ = ~CLK100MHZ;
    logic [1:0] btn = 0;
    logic [3:0] led;
    logic uart_rxd_out;
    logic [7:0] received;
    logic [31:0] uart_cycles;

    arty_a7_top dut (.*);

    task automatic receive_byte(output logic [7:0] value);
        @(negedge uart_rxd_out);
        repeat (54) @(posedge CLK100MHZ);
        if (uart_rxd_out !== 1'b0) $fatal(1,"Invalid UART start bit");
        for (int bit_no=0; bit_no<8; bit_no++) begin
            repeat (109) @(posedge CLK100MHZ);
            value[bit_no] = uart_rxd_out;
        end
        repeat (109) @(posedge CLK100MHZ);
        if (uart_rxd_out !== 1'b1) $fatal(1,"Invalid UART stop bit");
    endtask

    initial begin
        wait(led[0] == 1'b1); // Frame ready after clear and three triangles.
        @(negedge CLK100MHZ);
        btn[0] = 1'b1;
        receive_byte(received);
        btn[0] = 1'b0;
        if (received !== 8'h52) $fatal(1,"Header R");
        receive_byte(received); if (received !== 8'h41) $fatal(1,"Header A");
        receive_byte(received); if (received !== 8'h53) $fatal(1,"Header S");
        receive_byte(received); if (received !== 8'h54) $fatal(1,"Header T");
        receive_byte(received); if (received !== 8'h40) $fatal(1,"Width low");
        receive_byte(received); if (received !== 8'h01) $fatal(1,"Width high");
        receive_byte(received); if (received !== 8'hf0) $fatal(1,"Height low");
        receive_byte(received); if (received !== 8'h00) $fatal(1,"Height high");
        for (int i=0; i<4; i++) begin
            receive_byte(received);
            uart_cycles[8*i +: 8] = received;
        end
        if (uart_cycles !== dut.frame_draw_cycles)
            $fatal(1,"Frame cycle count mismatch");
        receive_byte(received); if (received !== 8'h00) $fatal(1,"First pixel low");
        receive_byte(received); if (received !== 8'h00) $fatal(1,"First pixel high");
        $display("FRAME_DRAW_CYCLES=%0d",uart_cycles);
        $display("PASS: Arty top drew frame and sent UART timing / first pixel");
        $finish;
    end

    initial begin
        #10000000;
        $display("DEBUG por=%h rst_n=%b state=%0d clear_done=%b tri_index=%0d tri_done=%b led=%b",
            dut.por, dut.rst_n, dut.state,
            dut.clear_done, dut.tri_index, dut.tri_done, led);
        $fatal(1,"Arty top simulation timeout");
    end
endmodule
