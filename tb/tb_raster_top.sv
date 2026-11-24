`timescale 1ns/1ps
module tb_raster_top;
    localparam int W = 16, H = 12;
    localparam int WORDS = W*H;
    localparam int AW = $clog2(WORDS);
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, clear_valid = 0, tri_valid = 0;
    logic clear_ready, clear_done, tri_ready, tri_done, busy;
    logic signed [15:0] x0,y0,x1,y1,x2,y2;
    logic [15:0] color;
    logic [AW-1:0] rd_addr = 0;
    logic [15:0] rd_data;
    logic [15:0] expected [0:W*H-1];
    int errors = 0;

    raster_top #(.WIDTH(W),.HEIGHT(H)) dut (
        .clk, .rst_n, .clear_valid, .clear_ready, .clear_done,
        .tri_valid, .tri_ready, .x0, .y0, .x1, .y1, .x2, .y2,
        .color, .tri_done, .busy, .rd_addr, .rd_data
    );

    function automatic longint signed ref_edge(
        input int ax, ay, bx, by, px, py
    );
        longint signed dx, dy, rx, ry;
        begin
            dx=bx-ax; dy=by-ay; rx=px-ax; ry=py-ay;
            ref_edge=dx*ry-dy*rx;
        end
    endfunction

    task automatic reference_triangle(
        input int xa,ya,xb,yb,xc,yc,
        input logic [15:0] rgb
    );
        int vx[0:2], vy[0:2], tx,ty,dx,dy;
        longint signed area, e;
        bit covered, include_edge;
        vx[0]=xa; vy[0]=ya;
        vx[1]=xb; vy[1]=yb;
        vx[2]=xc; vy[2]=yc;
        area=ref_edge(xa,ya,xb,yb,xc,yc);
        if (area != 0) begin
            if (area < 0) begin
                tx=vx[1]; ty=vy[1];
                vx[1]=vx[2]; vy[1]=vy[2];
                vx[2]=tx; vy[2]=ty;
            end
            for (int py=0; py<H; py++) begin
                for (int px=0; px<W; px++) begin
                    covered=1;
                    for (int j=0; j<3; j++) begin
                        dx=vx[(j+1)%3]-vx[j];
                        dy=vy[(j+1)%3]-vy[j];
                        e=ref_edge(vx[j],vy[j],vx[(j+1)%3],vy[(j+1)%3],
                               16*px+8,16*py+8);
                        include_edge=(dy<0)||((dy==0)&&(dx>0));
                        if ((e<0)||((e==0)&&!include_edge)) covered=0;
                    end
                    if (covered) expected[py*W+px]=rgb;
                end
            end
        end
    endtask

    task automatic send_triangle(
        input int xa,ya,xb,yb,xc,yc,
        input logic [15:0] rgb
    );
        @(negedge clk);
        while (!tri_ready) @(negedge clk);
        x0=xa; y0=ya; x1=xb; y1=yb; x2=xc; y2=yc;
        color=rgb; tri_valid=1;
        @(negedge clk);
        tri_valid=0;
        // Change the bus immediately after acceptance to check input latching.
        x0=16'sd300; y0=16'sd300;
        x1=16'sd320; y1=16'sd300;
        x2=16'sd300; y2=16'sd320;
        color=16'h1234;
        wait(tri_done);
        reference_triangle(xa,ya,xb,yb,xc,yc,rgb);
    endtask

    task automatic clear_frame;
        @(negedge clk);
        while (!clear_ready) @(negedge clk);
        clear_valid=1;
        @(negedge clk);
        clear_valid=0;
        wait(clear_done);
        for (int k=0; k<W*H; k++) expected[k]=0;
    endtask

    task automatic check_frame;
        for (int pixel=0; pixel<WORDS; pixel++) begin
            @(negedge clk);
            rd_addr=pixel;
            @(negedge clk);
            if (rd_data !== expected[pixel]) begin
                $display("Mismatch pixel=%0d got=%04h expected=%04h",
                         pixel, rd_data, expected[pixel]);
                errors++;
            end
        end
        if (errors) $fatal(1,"Frame check failed: %0d mismatches",errors);
    endtask

    initial begin
        for (int k=0; k<W*H; k++) expected[k]=0;
        x0=0; y0=0; x1=0; y1=0; x2=0; y2=0; color=0;
        repeat (4) @(negedge clk);
        rst_n=1;
        clear_frame();
        check_frame();

        // Two triangles exactly tile an 8x8 square.
        send_triangle(32,32, 160,32, 160,160, 16'hF800);
        send_triangle(32,32, 160,160, 32,160, 16'h07E0);
        check_frame();

        // Fractional vertices, reversed winding, and off-screen geometry.
        send_triangle(-16,64, 128,176, 256,80, 16'h001F);
        send_triangle(36,20, 68,156, 208,44, 16'hFFE0);
        send_triangle(16,16, 32,32, 48,48, 16'hFFFF);
        send_triangle(-128,-128, -64,-128, -64,-64, 16'h07FF);
        check_frame();

        clear_frame();
        check_frame();
        $display("PASS: clear, shared edge, clipping, winding, fractional vertices");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1,"Simulation timeout");
    end
endmodule
