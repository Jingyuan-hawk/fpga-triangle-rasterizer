`timescale 1ns/1ps
// One RGB565 pixel per address. Read is synchronous, one clock latency.
// Simultaneous read/write of the same address is intentionally unspecified.
module framebuffer_rgb565 #(
    parameter int WIDTH = 320,
    parameter int HEIGHT = 240,
    parameter int WORDS = WIDTH*HEIGHT,
    parameter int ADDR_W = (WORDS <= 1) ? 1 : $clog2(WORDS)
) (
    input  logic clk,
    input  logic wr_en,
    input  logic [ADDR_W-1:0] wr_addr,
    input  logic [15:0] wr_data,
    input  logic [ADDR_W-1:0] rd_addr,
    output logic [15:0] rd_data
);
    logic [15:0] mem [0:WORDS-1];

    always_ff @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
        rd_data <= mem[rd_addr];
    end
endmodule
