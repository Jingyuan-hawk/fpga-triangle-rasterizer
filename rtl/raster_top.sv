`timescale 1ns/1ps
// Generic integration: clear engine + one-lane rasterizer + framebuffer.
module raster_top #(
    parameter int WIDTH = 320,
    parameter int HEIGHT = 240,
    parameter int WORDS = WIDTH*HEIGHT,
    parameter int ADDR_W = (WORDS <= 1) ? 1 : $clog2(WORDS)
) (
    input  logic clk,
    input  logic rst_n,
    input  logic clear_valid,
    output logic clear_ready,
    output logic clear_done,
    input  logic tri_valid,
    output logic tri_ready,
    input  logic signed [15:0] x0, y0, x1, y1, x2, y2,
    input  logic [15:0] color,
    output logic tri_done,
    output logic busy,
    input  logic [ADDR_W-1:0] rd_addr,
    output logic [15:0] rd_data
);
    logic clearing;
    logic [ADDR_W-1:0] clear_addr;
    logic core_ready, core_busy, core_done;
    logic core_wr_valid;
    logic [ADDR_W-1:0] core_wr_addr;
    logic [15:0] core_wr_data;
    logic fb_wr_en;
    logic [ADDR_W-1:0] fb_wr_addr;
    logic [15:0] fb_wr_data;

    // Clear has priority if both commands arrive in the same idle cycle.
    always_comb begin
        clear_ready = !clearing && core_ready;
        tri_ready = !clearing && !clear_valid && core_ready;
        tri_done = core_done;
        busy = clearing || core_busy;
        fb_wr_en = clearing || core_wr_valid;
        fb_wr_addr = clearing ? clear_addr : core_wr_addr;
        fb_wr_data = clearing ? 16'b0 : core_wr_data;
    end

    rasterizer1 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.ADDR_W(ADDR_W)) core (
        .clk, .rst_n,
        .tri_valid(tri_valid && tri_ready), .tri_ready(core_ready),
        .x0_in(x0), .y0_in(y0), .x1_in(x1), .y1_in(y1),
        .x2_in(x2), .y2_in(y2), .color_in(color),
        .tri_done(core_done), .busy(core_busy),
        .wr_valid(core_wr_valid), .wr_ready(!clearing),
        .wr_addr(core_wr_addr), .wr_data(core_wr_data)
    );

    framebuffer_rgb565 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),
                          .WORDS(WORDS),.ADDR_W(ADDR_W)) framebuffer (
        .clk, .wr_en(fb_wr_en), .wr_addr(fb_wr_addr),
        .wr_data(fb_wr_data),
        .rd_addr, .rd_data
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clearing <= 1'b0;
            clear_addr <= '0;
            clear_done <= 1'b0;
        end else begin
            clear_done <= 1'b0;
            if (!clearing) begin
                if (clear_valid && clear_ready) begin
                    clearing <= 1'b1;
                    clear_addr <= '0;
                end
            end else if (clear_addr == WORDS-1) begin
                clearing <= 1'b0;
                clear_done <= 1'b1;
            end else begin
                clear_addr <= clear_addr + 1'b1;
            end
        end
    end
endmodule
