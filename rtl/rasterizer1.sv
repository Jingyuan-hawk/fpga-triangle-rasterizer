`timescale 1ns/1ps
// One RGB565 pixel is tested per clock. Vertex coordinates use 1/16 pixels.
module rasterizer1 #(
    parameter int WIDTH = 320,
    parameter int HEIGHT = 240,
    parameter int ADDR_W = (WIDTH*HEIGHT <= 1) ? 1 : $clog2(WIDTH*HEIGHT)
) (
    input  logic clk,
    input  logic rst_n,
    input  logic tri_valid,
    output logic tri_ready,
    input  logic signed [15:0] x0_in, y0_in, x1_in, y1_in, x2_in, y2_in,
    input  logic [15:0] color_in,
    output logic tri_done,
    output logic busy,
    output logic wr_valid,
    input  logic wr_ready,
    output logic [ADDR_W-1:0] wr_addr,
    output logic [15:0] wr_data
);
    typedef enum logic {IDLE, RUN} state_t;
    state_t state;

    function automatic signed [63:0] edge_value(
        input logic signed [31:0] ax, ay, bx, by, px, py
    );
        logic signed [31:0] dx, dy, rx, ry;
        begin
            dx = bx - ax;
            dy = by - ay;
            rx = px - ax;
            ry = py - ay;
            edge_value = dx*ry - dy*rx;
        end
    endfunction

    function automatic signed [31:0] min3(
        input logic signed [31:0] a, b, c
    );
        min3 = (a < b) ? ((a < c) ? a : c) : ((b < c) ? b : c);
    endfunction
    
    function automatic signed [31:0] max3(
        input logic signed [31:0] a, b, c
    );
        max3 = (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c);
    endfunction
    
    function automatic signed [31:0] ceil_div16(input logic signed [31:0] v);
        ceil_div16 = -((-v) >>> 4);
    endfunction
    
    function automatic signed [63:0] times16(input logic signed [31:0] v);
        logic signed [63:0] wide;
        begin
            wide = v;
            times16 = wide <<< 4;
        end
    endfunction

    logic signed [31:0] ax, ay, bx_raw, by_raw, cx_raw, cy_raw;
    logic signed [31:0] bx, by, cx, cy;
    logic signed [31:0] dx0, dy0, dx1, dy1, dx2, dy2;
    logic signed [31:0] left_raw, right_raw, top_raw, bottom_raw;
    logic signed [31:0] left_clip, right_clip, top_clip, bottom_clip;
    logic signed [31:0] sample_x, sample_y;
    logic signed [63:0] area, initial0, initial1, initial2;
    logic [2:0] inclusive_in;

    logic signed [31:0] x, first_x, x_max, y, y_max;
    logic signed [63:0] e0, e1, e2, row0, row1, row2;
    logic signed [63:0] sx0, sx1, sx2, sy0, sy1, sy2;
    logic [2:0] inclusive;
    logic [15:0] color;

    logic pixel_inside;
    always_comb begin
        // Normalize winding so all three edge tests have the same sign.
        ax = x0_in; ay = y0_in;
        bx_raw = x1_in; by_raw = y1_in;
        cx_raw = x2_in; cy_raw = y2_in;
        area = edge_value(ax,ay,bx_raw,by_raw,cx_raw,cy_raw);
        bx = (area < 0) ? cx_raw : bx_raw;
        by = (area < 0) ? cy_raw : by_raw;
        cx = (area < 0) ? bx_raw : cx_raw;
        cy = (area < 0) ? by_raw : cy_raw;

        dx0 = bx-ax; dy0 = by-ay;
        dx1 = cx-bx; dy1 = cy-by;
        dx2 = ax-cx; dy2 = ay-cy;
        inclusive_in = {
            (dy2 < 0) || ((dy2 == 0) && (dx2 > 0)),
            (dy1 < 0) || ((dy1 == 0) && (dx1 > 0)),
            (dy0 < 0) || ((dy0 == 0) && (dx0 > 0))
        };

        // Pixel centers are (16*x+8, 16*y+8); clip the bounding box.
        left_raw = ceil_div16(min3(ax,bx,cx)-32'sd8);
        right_raw = (max3(ax,bx,cx)-32'sd8) >>> 4;
        top_raw = ceil_div16(min3(ay,by,cy)-32'sd8);
        bottom_raw = (max3(ay,by,cy)-32'sd8) >>> 4;
        left_clip = (left_raw < 0) ? 0 : left_raw;
        right_clip = (right_raw >= WIDTH) ? WIDTH-1 : right_raw;
        top_clip = (top_raw < 0) ? 0 : top_raw;
        bottom_clip = (bottom_raw >= HEIGHT) ? HEIGHT-1 : bottom_raw;
        sample_x = (left_clip <<< 4) + 32'sd8;
        sample_y = (top_clip <<< 4) + 32'sd8;
        initial0 = edge_value(ax,ay,bx,by,sample_x,sample_y);
        initial1 = edge_value(bx,by,cx,cy,sample_x,sample_y);
        initial2 = edge_value(cx,cy,ax,ay,sample_x,sample_y);

        pixel_inside = ((e0 > 0) || ((e0 == 0) && inclusive[0])) &&
                       ((e1 > 0) || ((e1 == 0) && inclusive[1])) &&
                       ((e2 > 0) || ((e2 == 0) && inclusive[2]));
        wr_valid = (state == RUN) && pixel_inside;
        wr_addr = y*WIDTH + x;
        wr_data = color;
        tri_ready = (state == IDLE);
        busy = (state == RUN);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            tri_done <= 1'b0;
            x <= 0; first_x <= 0; x_max <= 0;
            y <= 0; y_max <= 0;
            e0 <= 0; e1 <= 0; e2 <= 0;
            row0 <= 0; row1 <= 0; row2 <= 0;
            sx0 <= 0; sx1 <= 0; sx2 <= 0;
            sy0 <= 0; sy1 <= 0; sy2 <= 0;
            inclusive <= 0;
            color <= 0;
        end else begin
            tri_done <= 1'b0;
            if (state == IDLE) begin
                if (tri_valid) begin
                    if ((area == 0) || (left_clip > right_clip) ||
                        (top_clip > bottom_clip)) begin
                        tri_done <= 1'b1;
                    end else begin
                        state <= RUN;
                        x <= left_clip;
                        first_x <= left_clip;
                        x_max <= right_clip;
                        y <= top_clip;
                        y_max <= bottom_clip;
                        e0 <= initial0; e1 <= initial1; e2 <= initial2;
                        row0 <= initial0; row1 <= initial1; row2 <= initial2;
                        sx0 <= -times16(dy0);
                        sx1 <= -times16(dy1);
                        sx2 <= -times16(dy2);
                        sy0 <= times16(dx0);
                        sy1 <= times16(dx1);
                        sy2 <= times16(dx2);
                        inclusive <= inclusive_in;
                        color <= color_in;
                    end
                end
            end else if (!wr_valid || wr_ready) begin
                // Empty pixels advance; covered pixels wait for the write port.
                if (x == x_max) begin
                    if (y == y_max) begin
                        state <= IDLE;
                        tri_done <= 1'b1;
                    end else begin
                        y <= y + 1;
                        x <= first_x;
                        row0 <= row0 + sy0;
                        row1 <= row1 + sy1;
                        row2 <= row2 + sy2;
                        e0 <= row0 + sy0;
                        e1 <= row1 + sy1;
                        e2 <= row2 + sy2;
                    end
                end else begin
                    x <= x + 1;
                    e0 <= e0 + sx0;
                    e1 <= e1 + sx1;
                    e2 <= e2 + sx2;
                end
            end
        end
    end
endmodule
