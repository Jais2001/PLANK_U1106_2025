`timescale 1ns/1ps
module PLANK_UART_tb();

    bit i_clk = 0;
    bit i_rst;
    bit i_rx_serial;

    bit i_attn_31p5;
    bit i_phase_180;
    bit i_TR_pulse;
    bit i_inhibit;

    logic [7:0] o_ch_power;  
    logic [5:0] o_attn_ch1; 
    logic [5:0] o_attn_ch2; 
    logic [5:0] o_attn_ch3; 
    logic [5:0] o_attn_ch4; 
    logic [5:0] o_attn_ch5; 
    logic [5:0] o_attn_ch6; 
    logic [5:0] o_attn_ch7; 
    logic [5:0] o_attn_ch8;

    logic [5:0] o_phase_ch1; 
    logic [5:0] o_phase_ch2; 
    logic [5:0] o_phase_ch3; 
    logic [5:0] o_phase_ch4; 
    logic [5:0] o_phase_ch5; 
    logic [5:0] o_phase_ch6; 
    logic [5:0] o_phase_ch7; 
    logic [5:0] o_phase_ch8;

    wire io_scl;
    wire io_sda;

    parameter c_BIT_PERIOD = 8680;

    reg [7:0] PLANK_data[0:20];
    reg [7:0] PLANK_checksum = 8'd0;

    integer k;

    initial begin
        PLANK_data[0] = 8'hAA; //header
        PLANK_data[1] = {4'b1111,4'h2};
        PLANK_data[20] = 8'h55;// Footer

        for (k = 2;k<19;k = k+ 1) begin
            PLANK_data[k] = {1'd0,1'd0,6'b110111};
        end    
    end


    PLANK PLANK_inst(
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_rx_serial(i_rx_serial),
        .i_inhibit(i_inhibit),
        .i_TR_pulse(i_TR_pulse),
        .i_attn_31p5(i_attn_31p5),
        .i_phase_180(i_phase_180),
        .o_tx_serial(o_tx_serial),
        .o_ch_power(o_ch_power),
        .o_attn_ch1(o_attn_ch1),
        .o_attn_ch2(o_attn_ch2),
        .o_attn_ch3(o_attn_ch3),
        .o_attn_ch4(o_attn_ch4),
        .o_attn_ch5(o_attn_ch5),
        .o_attn_ch6(o_attn_ch6),
        .o_attn_ch7(o_attn_ch7),
        .o_attn_ch8(o_attn_ch8),
        .o_phase_ch1(o_phase_ch1),
        .o_phase_ch2(o_phase_ch2),
        .o_phase_ch3(o_phase_ch3),
        .o_phase_ch4(o_phase_ch4),
        .o_phase_ch5(o_phase_ch5),
        .o_phase_ch6(o_phase_ch6),
        .o_phase_ch7(o_phase_ch7),
        .o_phase_ch8(o_phase_ch8),
        .o_TR_Pulse(o_TR_Pulse),
        .io_scl(io_scl),
        .io_sda(io_sda)
    );

    task UART_WRITE;
        input[7:0] in_data;
        integer i;
        begin
            i_rx_serial <= 1'b0;
            #(c_BIT_PERIOD);
            for (i=0;i<8;i=i+1) begin
                i_rx_serial = in_data[i];
                #(c_BIT_PERIOD);
            end
            i_rx_serial = 1'b1;
            #(c_BIT_PERIOD);
        end
    endtask 

    task  send_Plank;
        integer i,m;
        begin 
            PLANK_checksum = 8'd0;
            for (i=1;i<19;i=i+1) begin
                PLANK_checksum = PLANK_checksum ^ PLANK_data[i];
            end
            PLANK_data[19] = PLANK_checksum;
            foreach(PLANK_data[m]) begin
                UART_WRITE(PLANK_data[m]);
            end
        end
    endtask 

    initial begin
        i_rst = 0;
        #50;
        i_rst = 1;
        #100;
        $display("Time started sending feedback %t", $time);
        #100;
        i_attn_31p5 = 1'b1;
        i_phase_180 = 1'b1;
        i_TR_pulse = 1'b1;
        i_inhibit = 1'b1;
        #50;
        send_Plank;
        #400
        $stop;
       
    end

    always
        #5 i_clk = ~i_clk;


endmodule