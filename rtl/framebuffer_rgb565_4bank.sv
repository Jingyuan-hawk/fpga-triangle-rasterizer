`timescale 1ns/1ps
// Four write banks accept four adjacent pixels on one clock.
// The serial frame reader still observes one-clock synchronous read latency.
module framebuffer_rgb565_4bank #(
    parameter int WIDTH = 320,
    parameter int HEIGHT = 240,
    parameter int WORDS = WIDTH*HEIGHT,
    parameter int ADDR_W = (WORDS <= 1) ? 1 : $clog2(WORDS)
) (
    input logic clk,
    input logic [3:0] wr_en,
    input logic [3:0][ADDR_W-1:0] wr_addr,
    input logic [15:0] wr_data,
    input logic [ADDR_W-1:0] rd_addr,
    output logic [15:0] rd_data
);
    localparam int BANK_WORDS = WORDS/4;
    logic [3:0][15:0] bank_rd_data;
    logic [1:0] rd_bank;

    if ((WIDTH % 4) != 0) begin : invalid_width
        initial $fatal(1, "Four-bank framebuffer requires WIDTH divisible by four");
    end

    for (genvar bank=0; bank<4; bank++) begin : banks
        logic [15:0] mem [0:BANK_WORDS-1];
        always_ff @(posedge clk) begin
            if (wr_en[bank])
                mem[wr_addr[bank] >> 2] <= wr_data;
            bank_rd_data[bank] <= mem[rd_addr >> 2];
        end
    end

    always_ff @(posedge clk)
        rd_bank <= rd_addr[1:0];
    always_comb
        rd_data = bank_rd_data[rd_bank];
endmodule
