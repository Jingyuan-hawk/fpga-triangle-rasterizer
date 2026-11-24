`timescale 1ns/1ps
module tb_scene_frame;
    localparam int W=320, H=240, WORDS=W*H, AW=$clog2(WORDS);
    logic clk=0;
    always #5 clk=~clk;
    logic rst_n=0, clear_valid=0, tri_valid=0;
    logic clear_ready, clear_done, tri_ready, tri_done, busy;
    logic signed [15:0] x0,y0,x1,y1,x2,y2;
    logic [15:0] color;
    logic [AW-1:0] rd_addr=0;
    logic [15:0] rd_data;
    logic [15:0] expected [0:WORDS-1];
    int errors=0;

    raster_top #(.WIDTH(W),.HEIGHT(H)) dut (
        .clk,.rst_n,.clear_valid,.clear_ready,.clear_done,
        .tri_valid,.tri_ready,.x0,.y0,.x1,.y1,.x2,.y2,
        .color,.tri_done,.busy,.rd_addr,.rd_data
    );

    function automatic longint signed ref_edge(
        input int ax,ay,bx,by,px,py
    );
        longint signed dx,dy,rx,ry;
        begin
            dx=bx-ax; dy=by-ay; rx=px-ax; ry=py-ay;
            ref_edge=dx*ry-dy*rx;
        end
    endfunction

    task automatic reference_triangle(
        input int xa,ya,xb,yb,xc,yc,
        input logic [15:0] rgb
    );
        int vx[0:2], vy[0:2], t, dx, dy;
        longint signed area,e;
        bit covered,include_edge;
        vx[0]=xa; vy[0]=ya;
        vx[1]=xb; vy[1]=yb;
        vx[2]=xc; vy[2]=yc;
        area=ref_edge(xa,ya,xb,yb,xc,yc);
        if (area<0) begin
            t=vx[1]; vx[1]=vx[2]; vx[2]=t;
            t=vy[1]; vy[1]=vy[2]; vy[2]=t;
        end
        if (area!=0) begin
            for (int py=0;py<H;py++) begin
                for (int px=0;px<W;px++) begin
                    covered=1;
                    for (int j=0;j<3;j++) begin
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
        wait(tri_done);
        reference_triangle(xa,ya,xb,yb,xc,yc,rgb);
    endtask

    initial begin
        for (int p=0;p<WORDS;p++) expected[p]=0;
        x0=0;y0=0;x1=0;y1=0;x2=0;y2=0;color=0;
        repeat (4) @(negedge clk);
        rst_n=1;
        @(negedge clk);
        clear_valid=1;
        @(negedge clk);
        clear_valid=0;
        wait(clear_done);
        send_triangle(192,192, 2964,488, 732,3200, 16'hF800);
        send_triangle(960,720, 3360,3280, 4640,560, 16'h07E0);
        send_triangle(-320,2400, 2560,4160, 5040,1920, 16'h001F);
        for (int p=0;p<WORDS;p++) begin
            @(negedge clk);
            rd_addr=p;
            @(negedge clk);
            if (rd_data !== expected[p]) begin
                if (errors<10)
                    $display("Mismatch pixel=%0d got=%04h expected=%04h",
                             p,rd_data,expected[p]);
                errors++;
            end
        end
        if (errors) $fatal(1,"Full frame mismatch: %0d pixels",errors);
        $display("PASS: full 320x240 scene matches the reference");
        $finish;
    end
    initial begin
        #5000000;
        $fatal(1,"Full frame simulation timeout");
    end
endmodule
