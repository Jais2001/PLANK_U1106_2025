module max11642(
    input wire i_clk,
    input wire i_rst,
    input wire i_SPI_MISO,

    output wire o_SPI_Clk,
    output wire o_SPI_MOSI,
    output wire o_CS,
    output wire o_ADC_valid,
    output wire[79:0] o_ADC_data
);

    reg r_CS;
    reg[7:0] r_TX_Byte;
    reg r_TX_DV;
    reg r_TX_Ready;
    reg r_RX_DV;
    reg[7:0] r_RX_Byte;

    reg r_ADC_valid;
    reg[79:0] r_ADC_data;

    localparam CONVRSN = 1'b1;
    localparam SETUP = 2'b01;
    localparam AVG = 3'b001;
    localparam RST = 4'b0001;

    localparam NO_SCAN = 2'b11;

    localparam Power_up_time = 13'd7000; // 70us power time
    reg[12:0] r_power_up_counter;

    reg[3:0] r_Chnnl[0:9];

    reg[7:0] r_send_ADC_data;
    reg[15:0] r_ADC_data_buff;
    reg[1:0] r_ADC_count;

    reg r_start_scan;
    reg [3:0] chnl_cnt;

    initial begin
        r_Chnnl[0] = 4'd0;
        r_Chnnl[1] = 4'd1;
        r_Chnnl[2] = 4'd2;
        r_Chnnl[3] = 4'd3;
        r_Chnnl[4] = 4'd8;
        r_Chnnl[5] = 4'd9;
        r_Chnnl[6] = 4'd10;
        r_Chnnl[7] = 4'd11;
        r_Chnnl[8] = 4'd13;
        r_Chnnl[9] = 4'd14;
    end

    reg[3:0] SM_ADC;
    reg [3:0] SM_ADC_nxt;
    localparam SM_power_up = 4'd0;
    localparam SM_CS_Low = 4'd1;
    localparam SM_Start_SCLK = 4'd2;
    localparam SM_Send_MOSI = 4'd3;
    localparam SM_Get_MISO = 4'd4;
    localparam SM_Set_SCLK_2 = 4'd5;
    localparam SM_Send_Data = 4'd6;
    localparam SM_CS_High = 4'd7;
    localparam SM_Setup_ADC = 4'd8;
    localparam SM_Start_Scan = 4'd9;
    localparam SM_Send_wait = 4'd10;
    localparam SM_Incrmnt_chnnl = 4'd11;
    localparam SM_Clear_ADC = 4'd12;
    
    SPI_Master #(
        .SPI_MODE(0),// CPOL=0, CPHA=0
        .CLKS_PER_HALF_BIT(13) // 3.8 MHz SPI clock for 100 MHz FPGA clock
    )SPI_Master_inst(
        .i_Rst_L(i_rst),
        .i_Clk(i_clk),
        .i_TX_Byte(r_TX_Byte), 
        .i_TX_DV(r_TX_DV), 
        .o_TX_Ready(r_TX_Ready), 
        .o_RX_DV(r_RX_DV),
        .o_RX_Byte(r_RX_Byte),
        .o_SPI_Clk(o_SPI_Clk),
        .i_SPI_MISO(i_SPI_MISO),
        .o_SPI_MOSI(o_SPI_MOSI)
    );

    always @(posedge i_clk or negedge i_rst) begin
        if (~i_rst) begin
            SM_ADC <= SM_power_up;
            r_power_up_counter  <= 13'd0;
            r_CS <= 1'b1;
            chnl_cnt <= 4'd0;
            r_start_scan <= 1'd0;
            r_ADC_count <= 2'd0;
            r_ADC_data <= 80'd0;
            r_ADC_data_buff <= 16'd0;
            SM_ADC_nxt <= 4'd9;
            r_ADC_valid <= 1'd0;
            r_send_ADC_data <= 8'd0;
        end else begin
            r_TX_DV <= 1'b0;
            r_ADC_valid <= 1'd0;
            case (SM_ADC)
                SM_power_up : begin
                    if (r_power_up_counter < Power_up_time) begin
                        r_power_up_counter <= r_power_up_counter + 1'd1;
                        SM_ADC <= SM_power_up;
                    end else begin
                        r_power_up_counter  <= 13'd0;
                        SM_ADC <= SM_Setup_ADC;
                    end
                end
                SM_CS_Low : begin
                    r_CS <= 1'b0;
                    SM_ADC <= SM_Start_SCLK;
                end
                SM_Start_SCLK : begin
                    if (r_TX_Ready) begin
                        r_TX_DV <= 1'b1;
                        r_TX_Byte <= r_send_ADC_data;
                        SM_ADC <= SM_Send_wait;
                    end
                end
                SM_Send_wait : begin
                    SM_ADC <= SM_Send_MOSI;
                end
                SM_Send_MOSI : begin
                    SM_ADC <= SM_Send_MOSI;
                    if (r_TX_Ready) begin
                        SM_ADC <= SM_CS_High;
                    end
                end
                SM_Get_MISO : begin
                    SM_ADC <= SM_Get_MISO;
                    if (r_RX_DV) begin
                        r_ADC_data_buff <= (r_ADC_data_buff<<8)| r_RX_Byte;
                        r_ADC_count <= r_ADC_count + 1'd1;
                        SM_ADC  <= SM_Set_SCLK_2;
                    end
                end
                SM_Set_SCLK_2 : begin
                    if (r_ADC_count < 2'd2) begin
                        if (r_TX_Ready) begin
                            r_TX_DV <= 1'b1;
                            SM_ADC <= SM_Get_MISO;
                        end
                    end
                    else begin
                        SM_ADC <= SM_Send_Data;
                        r_ADC_count <= 2'd0;
                    end
                end
                SM_Send_Data : begin
                    r_CS <= 1'b1;
                    // r_ADC_valid <= 1'd1;
                    r_ADC_data <= (r_ADC_data << 8) | r_ADC_data_buff[11:4];
                    SM_ADC   <= SM_Incrmnt_chnnl;
                end
                SM_Incrmnt_chnnl : begin
                    if (chnl_cnt < 4'd9) begin
                        chnl_cnt <= chnl_cnt + 1;
                        SM_ADC   <= SM_Start_Scan;
                    end else begin
                        r_ADC_valid <= 1'd1;
                        SM_ADC   <= SM_Clear_ADC;
                        chnl_cnt <= 4'd0;
                    end
                end
                SM_Clear_ADC : begin
                    SM_ADC   <= SM_Start_Scan;
                    r_ADC_data <= 80'd0;
                end
                SM_CS_High : begin
                    SM_ADC <= SM_ADC_nxt;
                    if (r_start_scan) begin
                        r_CS <= 1'b0;
                    end else begin
                        r_CS <= 1'b1;
                    end
                end
                SM_Setup_ADC : begin
                    SM_ADC <= SM_CS_Low;
                    r_start_scan <= 1'd0;
                    r_send_ADC_data <= {SETUP,2'b11,2'b10,2'b00}; // clock mode -> Extrnl and Vltge -> Intrnl
                    SM_ADC_nxt  <= SM_Start_Scan;
                end
                SM_Start_Scan : begin
                    SM_ADC <= SM_CS_Low;
                    r_ADC_data_buff <= 16'd0;
                    r_start_scan <= 1'b1;
                    r_send_ADC_data <= {CONVRSN,r_Chnnl[chnl_cnt],2'b11,1'b0}; 
                    SM_ADC_nxt  <= SM_Set_SCLK_2;
                end
                default: begin
                    SM_ADC <= SM_power_up;
                end
            endcase
        end
    end

    assign o_CS = r_CS;
    assign o_ADC_valid = r_ADC_valid;
    assign o_ADC_data = r_ADC_data;
endmodule