`timescale 1ns/1ps
// Arty A7-100T demo: draw three triangles, send RGB565 frame over USB UART
// after BTN0 is pressed. BTN1 resets and redraws the scene.
module arty_a7_top (
    input  logic CLK100MHZ,
    input  logic [1:0] btn,
    output logic [3:0] led,
    output logic uart_rxd_out
);
    localparam int WIDTH = 320;
    localparam int HEIGHT = 240;
    localparam int WORDS = WIDTH*HEIGHT;
    localparam int ADDR_W = $clog2(WORDS);
    localparam int FRAME_BYTES = WIDTH*HEIGHT*2;

    // Configuration initializes POR to zero on 7-series FPGAs.
    logic [15:0] por = 0;
    logic [31:0] tri_cycles;
    logic [31:0] last_tri_cycles;
    logic rst_n;

    always_ff @(posedge CLK100MHZ) begin
        if (btn[1]) por <= 0;
        else if (!por[15]) por <= por + 1'b1;
    end
    always_comb begin
        rst_n = por[15] && !btn[1];
    end

    (* ASYNC_REG = "TRUE" *) logic btn0_meta, btn0_sync;
    logic btn0_prev;
    always_ff @(posedge CLK100MHZ or negedge rst_n) begin
        if (!rst_n) begin
            btn0_meta <= 0;
            btn0_sync <= 0;
            btn0_prev <= 0;
        end else begin
            btn0_meta <= btn[0];
            btn0_sync <= btn0_meta;
            btn0_prev <= btn0_sync;
        end
    end
    logic btn0_rise;
    always_comb begin
        btn0_rise = btn0_sync && !btn0_prev;
    end

    typedef enum logic [3:0] {
        S_CLEAR, S_CLEAR_WAIT, S_TRI, S_TRI_WAIT, S_READY,
        S_HEADER, S_READ_ADDR, S_READ_WAIT, S_SEND_BYTE
    } state_t;
    state_t state;
    logic [1:0] tri_index;
    logic [3:0] header_index;
    logic [17:0] byte_index;
    logic [ADDR_W-1:0] rd_addr;
    logic [15:0] rd_data;
    logic clear_valid, clear_ready, clear_done;
    logic tri_valid, tri_ready, tri_done, busy;
    logic signed [15:0] x0,y0,x1,y1,x2,y2;
    logic [15:0] color;
    logic tx_valid, tx_ready;
    logic [7:0] tx_data;

    always_comb begin
        clear_valid = (state == S_CLEAR);
        tri_valid = (state == S_TRI);
        led[0] = (state == S_READY);
        led[1] = (state == S_HEADER) || (state == S_READ_ADDR) ||
                 (state == S_READ_WAIT) || (state == S_SEND_BYTE);
        led[2] = tri_valid || (state == S_TRI_WAIT);
        led[3] = clear_valid || (state == S_CLEAR_WAIT);
    end

    // The same scene as the MATLAB demo, coordinates multiplied by 16.
    always_comb begin
        x0=0; y0=0; x1=0; y1=0; x2=0; y2=0; color=0;
        case (tri_index)
            0: begin
                x0=192; y0=192; x1=2964; y1=488;
                x2=732; y2=3200; color=16'hF800;
            end
            1: begin
                x0=960; y0=720; x1=3360; y1=3280;
                x2=4640; y2=560; color=16'h07E0;
            end
            2: begin
                x0=-320; y0=2400; x1=2560; y1=4160;
                x2=5040; y2=1920; color=16'h001F;
            end
            default: ;
        endcase
    end

    raster_top #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) raster (
        .clk(CLK100MHZ), 
        .rst_n,
        .clear_valid, 
        .clear_ready, 
        .clear_done,
        .tri_valid, 
        .tri_ready, 
        .x0, 
        .y0, 
        .x1, 
        .y1, 
        .x2, 
        .y2,
        .color, 
        .tri_done, 
        .busy, 
        .rd_addr, 
        .rd_data
    );
    always_ff @(posedge CLK100MHZ or negedge rst_n) begin
        if (!rst_n) begin
            tri_cycles      <= 0;
            last_tri_cycles <= 0;
        end else begin
            if (tri_valid && tri_ready)
                tri_cycles <= 0;
            else if (busy)
                tri_cycles <= tri_cycles + 1;

            if (tri_done)
                last_tri_cycles <= tri_cycles;
        end
    end
    always_comb begin
        tx_valid = (state == S_HEADER) || (state == S_SEND_BYTE);
        tx_data = 8'h00;
        if (state == S_HEADER) begin
            case (header_index)
                0: tx_data = "R";
                1: tx_data = "A";
                2: tx_data = "S";
                3: tx_data = "T";
                4: tx_data = 8'(WIDTH);
                5: tx_data = 8'(WIDTH >> 8);
                6: tx_data = 8'(HEIGHT);
                7: tx_data = 8'(HEIGHT >> 8);
                default: tx_data = 0;
            endcase
        end else if (state == S_SEND_BYTE) begin
            tx_data = rd_data[8*byte_index[0] +: 8];
        end
    end
    uart_tx #(.CLOCK_HZ(100_000_000), .BAUD(921_600)) serial_tx (
        .clk(CLK100MHZ), .rst_n,
        .valid(tx_valid), .ready(tx_ready), .data(tx_data),
        .tx(uart_rxd_out)
    );

    always_ff @(posedge CLK100MHZ or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_CLEAR;
            tri_index <= 0;
            header_index <= 0;
            byte_index <= 0;
            rd_addr <= 0;
        end else begin
            case (state)
                S_CLEAR: if (clear_ready) state <= S_CLEAR_WAIT;
                S_CLEAR_WAIT: if (clear_done) begin
                    tri_index <= 0;
                    state <= S_TRI;
                end
                S_TRI: if (tri_ready) state <= S_TRI_WAIT;
                S_TRI_WAIT: if (tri_done) begin
                    if (tri_index == 2) state <= S_READY;
                    else begin
                        tri_index <= tri_index + 1'b1;
                        state <= S_TRI;
                    end
                end
                S_READY: if (btn0_rise) begin
                    header_index <= 0;
                    byte_index <= 0;
                    state <= S_HEADER;
                end
                S_HEADER: if (tx_ready) begin
                    if (header_index == 7) state <= S_READ_ADDR;
                    else header_index <= header_index + 1'b1;
                end
                S_READ_ADDR: begin
                    rd_addr <= byte_index[17:1];
                    state <= S_READ_WAIT;
                end
                S_READ_WAIT: state <= S_SEND_BYTE;
                S_SEND_BYTE: if (tx_ready) begin
                    if (byte_index == FRAME_BYTES-1) state <= S_READY;
                    else begin
                        byte_index <= byte_index + 1'b1;
                        state <= S_READ_ADDR;
                    end
                end
                default: state <= S_CLEAR;
            endcase
        end
    end
endmodule
