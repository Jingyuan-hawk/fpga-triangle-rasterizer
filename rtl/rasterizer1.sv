`timescale 1ns/1ps
// One RGB565 pixel is tested per clock. Vertex coordinates use 1/16 pixels.
module rasterizer1 #(
    parameter int WIDTH = 320,
    parameter int HEIGHT = 240,
    parameter int ADDR_W = (WIDTH*HEIGHT <= 1) ? 1 : $clog2(WIDTH*HEIGHT)
) (
    input logic clk, rst_n, tri_valid,
    output logic tri_ready,
    input logic signed [15:0] x0_in, y0_in, x1_in, y1_in, x2_in, y2_in,
    input logic [15:0] color_in,
    output logic tri_done, busy, wr_valid,
    input logic wr_ready,
    output logic [ADDR_W-1:0] wr_addr,
    output logic [15:0] wr_data
);
    typedef enum logic [2:0] {IDLE, CALC_AREA, ORIENT, BBOX, INIT_EDGE, RUN} state_t;
    state_t state, state_next;
    // 16-bit vertices and the 320x240 frame fit safely within 36-bit edges.
    localparam int EDGE_W = 36;

    // q holds the current triangle and scan position; d is its next value.
    typedef struct packed {
        logic signed [15:0] x0, y0, x1, y1, x2, y2;
        logic [15:0] color;
        logic signed [EDGE_W-1:0] area;
        logic signed [EDGE_W-1:0] area_p0, area_p1;
        logic area_phase;
        logic signed [15:0] ax, ay, bx, by, cx, cy;
        logic signed [31:0] x, first_x, x_max, y, y_max;
        logic signed [31:0] sample_x, sample_y;
        logic signed [16:0] dx0, dy0, dx1, dy1, dx2, dy2;
        logic signed [16:0] rx0, ry0, rx1, ry1, rx2, ry2;
        logic signed [EDGE_W-1:0] p0a, p0b, p1a, p1b, p2a, p2b;
        logic init_phase;
        logic signed [EDGE_W-1:0] e0, e1, e2, row0, row1, row2;
        logic signed [EDGE_W-1:0] sx0, sx1, sx2, sy0, sy1, sy2;
        logic [2:0] inclusive;
    } pipe_t;
    pipe_t q, d;
    logic tri_done_next, pixel_inside;

    function automatic signed [31:0] min3(input logic signed [31:0] a, b, c);
        min3 = (a < b) ? ((a < c) ? a : c) : ((b < c) ? b : c);
    endfunction
    function automatic signed [31:0] max3(input logic signed [31:0] a, b, c);
        max3 = (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c);
    endfunction
    function automatic signed [31:0] ceil_div16(input logic signed [31:0] v);
        ceil_div16 = -((-v) >>> 4);
    endfunction
    function automatic signed [EDGE_W-1:0] times16(input logic signed [31:0] v);
        logic signed [EDGE_W-1:0] wide;
        begin wide = v; times16 = wide <<< 4; end
    endfunction

    logic signed [31:0] left_raw, right_raw, top_raw, bottom_raw;
    logic signed [31:0] left_clip, right_clip, top_clip, bottom_clip;
    logic signed [31:0] dx0, dy0, dx1, dy1, dx2, dy2;
    logic signed [16:0] area_dx, area_dy, area_rx, area_ry;
    always_comb begin
        area_dx = $signed(q.x1) - $signed(q.x0);
        area_dy = $signed(q.y1) - $signed(q.y0);
        area_rx = $signed(q.x2) - $signed(q.x0);
        area_ry = $signed(q.y2) - $signed(q.y0);
        dx0 = $signed(q.bx) - $signed(q.ax);
        dy0 = $signed(q.by) - $signed(q.ay);
        dx1 = $signed(q.cx) - $signed(q.bx);
        dy1 = $signed(q.cy) - $signed(q.by);
        dx2 = $signed(q.ax) - $signed(q.cx);
        dy2 = $signed(q.ay) - $signed(q.cy);

        // Pixel centers are (16*x+8, 16*y+8).
        left_raw = ceil_div16(min3(q.ax,q.bx,q.cx)-32'sd8);
        right_raw = (max3(q.ax,q.bx,q.cx)-32'sd8) >>> 4;
        top_raw = ceil_div16(min3(q.ay,q.by,q.cy)-32'sd8);
        bottom_raw = (max3(q.ay,q.by,q.cy)-32'sd8) >>> 4;
        left_clip = (left_raw < 0) ? 0 : left_raw;
        right_clip = (right_raw >= WIDTH) ? WIDTH-1 : right_raw;
        top_clip = (top_raw < 0) ? 0 : top_raw;
        bottom_clip = (bottom_raw >= HEIGHT) ? HEIGHT-1 : bottom_raw;

        pixel_inside = ((q.e0 > 0) || ((q.e0 == 0) && q.inclusive[0])) &&
                       ((q.e1 > 0) || ((q.e1 == 0) && q.inclusive[1])) &&
                       ((q.e2 > 0) || ((q.e2 == 0) && q.inclusive[2]));
        wr_valid = (state == RUN) && pixel_inside;
        wr_addr = q.y*WIDTH + q.x;
        wr_data = q.color;
        tri_ready = (state == IDLE);
        busy = (state != IDLE);
    end

    always_comb begin
        d = q;
        state_next = state;
        tri_done_next = 1'b0;
        case (state)
            IDLE: if (tri_valid) begin
                d.x0 = x0_in; d.y0 = y0_in;
                d.x1 = x1_in; d.y1 = y1_in;
                d.x2 = x2_in; d.y2 = y2_in;
                d.color = color_in;
                d.area_phase = 1'b0;
                state_next = CALC_AREA;
            end
            CALC_AREA: begin
                if (!q.area_phase) begin
                    d.area_p0 = area_dx * area_ry;
                    d.area_p1 = area_dy * area_rx;
                    d.area_phase = 1'b1;
                end else begin
                    d.area = q.area_p0 - q.area_p1;
                    state_next = ORIENT;
                end
            end
            ORIENT: begin
                d.ax = q.x0; d.ay = q.y0;
                d.bx = (q.area < 0) ? q.x2 : q.x1;
                d.by = (q.area < 0) ? q.y2 : q.y1;
                d.cx = (q.area < 0) ? q.x1 : q.x2;
                d.cy = (q.area < 0) ? q.y1 : q.y2;
                if (q.area == 0) begin
                    state_next = IDLE;
                    tri_done_next = 1'b1;
                end else state_next = BBOX;
            end
            BBOX: begin
                d.x = left_clip; d.first_x = left_clip; d.x_max = right_clip;
                d.y = top_clip; d.y_max = bottom_clip;
                d.sample_x = (left_clip <<< 4) + 32'sd8;
                d.sample_y = (top_clip <<< 4) + 32'sd8;
                d.dx0 = dx0; d.dy0 = dy0;
                d.dx1 = dx1; d.dy1 = dy1;
                d.dx2 = dx2; d.dy2 = dy2;
                d.rx0 = d.sample_x - $signed(q.ax);
                d.ry0 = d.sample_y - $signed(q.ay);
                d.rx1 = d.sample_x - $signed(q.bx);
                d.ry1 = d.sample_y - $signed(q.by);
                d.rx2 = d.sample_x - $signed(q.cx);
                d.ry2 = d.sample_y - $signed(q.cy);
                d.init_phase = 1'b0;
                d.sx0 = -times16(dy0); d.sy0 = times16(dx0);
                d.sx1 = -times16(dy1); d.sy1 = times16(dx1);
                d.sx2 = -times16(dy2); d.sy2 = times16(dx2);
                d.inclusive = {
                    (dy2 < 0) || ((dy2 == 0) && (dx2 > 0)),
                    (dy1 < 0) || ((dy1 == 0) && (dx1 > 0)),
                    (dy0 < 0) || ((dy0 == 0) && (dx0 > 0))
                };
                state_next = INIT_EDGE;
            end
            INIT_EDGE: begin
                if ((q.x > q.x_max) || (q.y > q.y_max)) begin
                    state_next = IDLE;
                    tri_done_next = 1'b1;
                end else if (!q.init_phase) begin
                    // Multiply first, then subtract on the following clock.
                    d.p0a = q.dx0 * q.ry0; d.p0b = q.dy0 * q.rx0;
                    d.p1a = q.dx1 * q.ry1; d.p1b = q.dy1 * q.rx1;
                    d.p2a = q.dx2 * q.ry2; d.p2b = q.dy2 * q.rx2;
                    d.init_phase = 1'b1;
                end else begin
                    d.e0 = q.p0a - q.p0b;
                    d.e1 = q.p1a - q.p1b;
                    d.e2 = q.p2a - q.p2b;
                    d.row0 = d.e0; d.row1 = d.e1; d.row2 = d.e2;
                    state_next = RUN;
                end
            end
            RUN: if (!pixel_inside || wr_ready) begin
                // A covered pixel waits until the write port accepts it.
                if (q.x == q.x_max) begin
                    if (q.y == q.y_max) begin
                        state_next = IDLE;
                        tri_done_next = 1'b1;
                    end else begin
                        d.y = q.y + 1; d.x = q.first_x;
                        d.row0 = q.row0 + q.sy0;
                        d.row1 = q.row1 + q.sy1;
                        d.row2 = q.row2 + q.sy2;
                        d.e0 = d.row0; d.e1 = d.row1; d.e2 = d.row2;
                    end
                end else begin
                    d.x = q.x + 1;
                    d.e0 = q.e0 + q.sx0;
                    d.e1 = q.e1 + q.sx1;
                    d.e2 = q.e2 + q.sx2;
                end
            end
            default: state_next = IDLE;
        endcase
    end

    // The flip-flops only reset or copy the values chosen above.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            q <= '0;
            tri_done <= 1'b0;
        end else begin
            state <= state_next;
            q <= d;
            tri_done <= tri_done_next;
        end
    end
endmodule
