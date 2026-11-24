`timescale 1ns/1ps
// 8N1 UART transmitter. Accepts one byte when valid && ready.
module uart_tx #(
    parameter int CLOCK_HZ = 100_000_000,
    parameter int BAUD = 921_600,
    parameter int DIVIDER = (CLOCK_HZ + BAUD/2) / BAUD,
    parameter int COUNT_W = (DIVIDER <= 1) ? 1 : $clog2(DIVIDER)
) (
    input  logic clk,
    input  logic rst_n,
    input  logic valid,
    output logic ready,
    input  logic [7:0] data,
    output logic tx
);
    logic active;
    logic [9:0] shift_reg;
    logic [3:0] bit_index;
    logic [COUNT_W-1:0] count;

    always_comb begin
        ready = !active;
        tx = active ? shift_reg[0] : 1'b1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 1'b0;
            shift_reg <= 10'h3ff;
            bit_index <= 0;
            count <= 0;
        end else if (!active) begin
            if (valid) begin
                shift_reg <= {1'b1, data, 1'b0};
                bit_index <= 0;
                count <= COUNT_W'(DIVIDER-1);
                active <= 1'b1;
            end
        end else if (count == 0) begin
            count <= COUNT_W'(DIVIDER-1);
            shift_reg <= {1'b1, shift_reg[9:1]};
            if (bit_index == 9)
                active <= 1'b0;
            else
                bit_index <= bit_index + 1'b1;
        end else begin
            count <= count - 1'b1;
        end
    end
endmodule
