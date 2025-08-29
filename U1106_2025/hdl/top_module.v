module PLANK(
    input wire i_clk,
    input wire i_rst,
    input wire i_rx_serial,

    input wire i_inhibit,
    input wire i_TR_pulse,
    input wire i_attn_31p5,
    input wire i_phase_180,

    output wire o_tx_serial,

    output wire[7:0] o_ch_power,
    output wire[5:0] o_attn_ch1,
    output wire[5:0] o_attn_ch2,
    output wire[5:0] o_attn_ch3,
    output wire[5:0] o_attn_ch4,
    output wire[5:0] o_attn_ch5,
    output wire[5:0] o_attn_ch6,
    output wire[5:0] o_attn_ch7,
    output wire[5:0] o_attn_ch8,

    output wire[5:0] o_phase_ch1,
    output wire[5:0] o_phase_ch2,
    output wire[5:0] o_phase_ch3,
    output wire[5:0] o_phase_ch4,
    output wire[5:0] o_phase_ch5,
    output wire[5:0] o_phase_ch6,
    output wire[5:0] o_phase_ch7,
    output wire[5:0] o_phase_ch8,

    output wire o_TR_Pulse,

    //TMP117
    inout wire io_scl,
    inout wire io_sda,

    //ADC
    input wire i_SPI_MISO,
    output wire o_SPI_Clk,
    output wire o_SPI_MOSI,
    output wire o_CS
);

    // Set Parameter CLKS_PER_BIT as follows:
    // CLKS_PER_BIT = (Frequency of i_Clock)/(Frequency of UART)
    // Example: 100 MHz Clock, 115200 baud UART
    // (100000000)/(115200) = 868

    localparam CLOCK_FREQ = 100000000;
    localparam BAUD_RATE = 115200;
    localparam CLKS_PER_BIT = CLOCK_FREQ/BAUD_RATE;

    reg [7:0] r_ch_power;
    reg [5:0] r_attn_ch1;
    reg [5:0] r_attn_ch2;
    reg [5:0] r_attn_ch3;
    reg [5:0] r_attn_ch4;
    reg [5:0] r_attn_ch5;
    reg [5:0] r_attn_ch6;
    reg [5:0] r_attn_ch7;
    reg [5:0] r_attn_ch8;
    reg [5:0] r_phase_ch1;
    reg [5:0] r_phase_ch2;
    reg [5:0] r_phase_ch3;
    reg [5:0] r_phase_ch4;
    reg [5:0] r_phase_ch5;
    reg [5:0] r_phase_ch6;
    reg [5:0] r_phase_ch7;
    reg [5:0] r_phase_ch8;
    reg       r_tx_rx_sel;
    reg [1:0] r_band_sel;

    reg r_soft_inhibit;

    wire w_rst_n;

    wire [7:0] w_uart_rx_data;
    wire w_uart_rx_error;
    wire w_uart_rx_valid;

    reg[7:0] r_uart_rx_data;
    reg r_uart_rx_valid;

    wire w_uart_tx_active;
    reg r_uart_tx_valid = 0;
    reg [7:0] r_uart_tx_data = 0;
    wire w_uart_tx_done;
    wire w_tx_serial;

    wire[15:0] w_temp_data_GND;
    wire[15:0] w_temp_data_VCC;
    wire w_temp_ready_GND;
    wire w_temp_ready_VCC;

    reg [23:0] r_VCC_GND_Temp;
    reg r_VCC_GND_Temp_valid;
    reg [23:0] r_buff_send_Uart;

    reg[23:0] r_FDB_Chnnl;
    reg r_FDBCK_pending;

    reg r_ADC_valid;
    reg r_ADC_buff_Valid;
    reg r_ADC_pending;
    reg r_temp_pending;
    reg[79:0] r_ADC_data;
    reg[87:0] r_ADC_set_data;
    reg[87:0] r_ADC_buff_set_data;
    reg[87:0] r_buff_send_ADC;

    assign w_rst_n = i_rst;


    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) uart_rx_inst
    (
        .i_Clock (i_clk),
        .i_Rx_Serial (i_rx_serial),
        .o_Rx_DV (w_uart_rx_valid),
        .o_Rx_Byte (w_uart_rx_data)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) uart_tx_inst 
    (
        .i_Clock (i_clk),
        .i_Tx_DV (r_uart_tx_valid),
        .i_Tx_Byte (r_uart_tx_data),
        .o_Tx_Active (w_uart_tx_active),
        .o_Tx_Serial (o_tx_serial),
        .o_Tx_Done (w_uart_tx_done)
    );

    tmp117 tmp117_inst (
        .i_clk(i_clk),
        .i_rst(w_rst_n),
        .io_scl(io_scl),
        .io_sda(io_sda),
        .o_temp_data_GND(w_temp_data_GND),
        .o_temp_data_VCC(w_temp_data_VCC),
        .o_temp_ready_GND(w_temp_ready_GND),
        .o_temp_ready_VCC(w_temp_ready_VCC)
    );

    max11642 max11642_inst(
        .i_clk(i_clk),
        .i_rst(w_rst_n),
        .i_SPI_MISO(i_SPI_MISO),
        .o_SPI_Clk(o_SPI_Clk),
        .o_SPI_MOSI(o_SPI_MOSI),
        .o_CS(o_CS),
        .o_ADC_valid(r_ADC_valid),
        .o_ADC_data(r_ADC_data)
    );

    always @(posedge i_clk or negedge w_rst_n) begin
        if (w_rst_n == 1'b0) begin
            r_uart_rx_data <= 0;
            r_uart_rx_valid <= 0;
        end else begin
            r_uart_rx_data <= w_uart_rx_data;
            r_uart_rx_valid <= w_uart_rx_valid;
        end
    end

    // Variables for the PLANK packet identifier
    localparam PLANK_LENGTH = 19; // Total packet size In bytes inluding data,checksum
    wire [(PLANK_LENGTH*8) - 1 : 0] w_PLANK_data;
    wire w_PLANK_data_valid;

    // PLANK packet identifier - no need identifier
    UART_packet_identifier #(
        .RX_PACKET_LEN(PLANK_LENGTH)
    ) read_PLANK_id_inst(
        .i_clk(i_clk),
        .i_rst_n(w_rst_n),
        .i_en(1'b1),
        .i_uart_rx_data(r_uart_rx_data),
        .o_uart_rx_error(),
        .i_uart_rx_valid(r_uart_rx_valid),
        .o_data(w_PLANK_data),
        .o_data_valid(w_PLANK_data_valid)
    );

    reg r_PLANK_data_valid_buff1;
    reg r_PLANK_data_valid_buff2;
    reg r_PLANK_data_valid_buff3;
    reg r_PLANK_data_valid_buff4;
    reg r_PLANK_data_valid_buff5;

    reg[3:0] r_send_counter;

    always @(posedge i_clk or negedge w_rst_n) begin
        if (~w_rst_n) begin
            r_PLANK_data_valid_buff1 <= 0;
            r_PLANK_data_valid_buff2 <= 0;
            r_PLANK_data_valid_buff3 <= 0;
        end else begin
            r_PLANK_data_valid_buff1  <= w_PLANK_data_valid;
            r_PLANK_data_valid_buff2  <= r_PLANK_data_valid_buff1;
            r_PLANK_data_valid_buff3  <= r_PLANK_data_valid_buff2;
            r_PLANK_data_valid_buff4  <= r_PLANK_data_valid_buff3;
            r_PLANK_data_valid_buff5  <= r_PLANK_data_valid_buff4;
        end
    end

    always @(posedge i_clk or negedge w_rst_n) begin
        if (~w_rst_n) begin
            r_FDB_Chnnl <= 25'b0;
        end else begin
            if (r_PLANK_data_valid_buff2) begin
                r_FDB_Chnnl <= {r_tx_rx_sel,r_ch_power,8'hEE};
            end
        end
    end

    always @(posedge i_clk or negedge w_rst_n)begin
        if (~w_rst_n) begin
            r_ADC_set_data <= 88'd0;
        end else begin
            if (r_ADC_valid) begin
                r_ADC_set_data <= {r_ADC_data,8'hCC};
            end 
        end
    end

    always @(posedge i_clk or negedge w_rst_n) begin
        if (~w_rst_n) begin
            r_ADC_buff_Valid <= 1'b0;
        end else begin
            r_ADC_buff_Valid <= r_ADC_valid;
        end
    end

    // always @(posedge i_clk or negedge w_rst_n) begin
    //     if (~w_rst_n) begin
    //         r_VCC_GND_Temp <= 24'd0;
    //         r_VCC_GND_Temp_valid <= 1'b0;
    //     end else begin
    //         r_VCC_GND_Temp_valid <= 1'b0;
    //         if (w_temp_ready_GND) begin
    //             r_VCC_GND_Temp[15:0] <= {w_temp_data_GND[14:7],8'hDD};
    //         end else if (w_temp_ready_VCC) begin
    //             r_VCC_GND_Temp[23:16] <= w_temp_data_VCC[14:7];
    //             r_VCC_GND_Temp_valid <= 1'b1;
    //         end
    //     end
    // end

    reg[31:0] r_Watchdog_VCC;
    reg[31:0] r_Watchdog_GND;
    reg[31:0] r_Watchdog_ADC;

    reg[1:0] ST_Temp;
    localparam Temp_GND = 2'd1;
    localparam Temp_VCC = 2'd2;


    always @(posedge i_clk or negedge w_rst_n) begin
        if (~w_rst_n) begin
            ST_Temp <= Temp_GND;
            r_VCC_GND_Temp <= 24'd0;
            r_VCC_GND_Temp_valid <= 1'b0;
            r_Watchdog_VCC <= 0;
            r_Watchdog_GND <= 0;
        end else begin
            r_VCC_GND_Temp_valid <= 1'b0;

            case (ST_Temp)
                Temp_GND: begin

                    r_Watchdog_GND <= r_Watchdog_GND + 1'b1;
                    if (r_Watchdog_GND > 32'd1110000) begin
                        r_Watchdog_GND <= 0;
                        r_VCC_GND_Temp[15:0] <= {8'd0,8'hDD};
                        ST_Temp <= Temp_VCC;
                    end

                    if (w_temp_ready_GND) begin
                        r_VCC_GND_Temp[15:0] <= {w_temp_data_GND[14:7],8'hDD};
                        r_Watchdog_GND <= 0;
                        ST_Temp <= Temp_VCC;
                    end
                end
                Temp_VCC: begin

                    r_Watchdog_VCC <= r_Watchdog_VCC + 1'b1;
                    if (r_Watchdog_VCC > 32'd1110000) begin
                        r_VCC_GND_Temp[23:16] <= 8'd0;
                        r_VCC_GND_Temp_valid <= 1'b1;
                        r_Watchdog_VCC <= 0;
                        ST_Temp <= Temp_GND;
                    end

                    if (w_temp_ready_VCC) begin
                        r_VCC_GND_Temp[23:16] <= w_temp_data_VCC[14:7];
                        r_VCC_GND_Temp_valid <= 1'b1;
                        r_Watchdog_VCC <= 0;
                        ST_Temp <= Temp_GND;
                    end
                end
                default: begin
                    ST_Temp <= Temp_GND;
                end
            endcase
        end
    end

    always @(posedge i_clk or negedge w_rst_n) begin
        if (~w_rst_n) begin
            r_ch_power  <= 0;
            r_attn_ch1  <= 0;
            r_attn_ch2  <= 0;
            r_attn_ch3  <= 0;
            r_attn_ch4  <= 0;
            r_attn_ch5  <= 0;
            r_attn_ch6  <= 0;
            r_attn_ch7  <= 0;
            r_attn_ch8  <= 0;
            r_phase_ch1 <= 0;
            r_phase_ch2 <= 0;
            r_phase_ch3 <= 0;
            r_phase_ch4 <= 0;
            r_phase_ch5 <= 0;
            r_phase_ch6 <= 0;
            r_phase_ch7 <= 0;
            r_phase_ch8 <= 0;
            r_tx_rx_sel <= 0;
            r_band_sel  <= 0;
        end else begin
            if (w_PLANK_data_valid) begin
                r_tx_rx_sel         <=  w_PLANK_data[2];
                r_soft_inhibit      <=  w_PLANK_data[3];
                r_phase_ch1         <=  w_PLANK_data[13:8];
                r_attn_ch1          <=  w_PLANK_data[21:16];
                r_phase_ch2         <=  w_PLANK_data[29:24];
                r_attn_ch2          <=  w_PLANK_data[37:32];
                r_phase_ch3         <=  w_PLANK_data[45:40];
                r_attn_ch3          <=  w_PLANK_data[53:48];
                r_phase_ch4         <=  w_PLANK_data[61:56];
                r_attn_ch4          <=  w_PLANK_data[69:64];
                r_phase_ch5         <=  w_PLANK_data[77:72];
                r_attn_ch5          <=  w_PLANK_data[85:80];
                r_phase_ch6         <=  w_PLANK_data[93:88];
                r_attn_ch6          <=  w_PLANK_data[101:96];
                r_phase_ch7         <=  w_PLANK_data[109:104];
                r_attn_ch7          <=  w_PLANK_data[117:112];
                r_phase_ch8         <=  w_PLANK_data[125:120];
                r_attn_ch8          <=  w_PLANK_data[133:128];
                r_ch_power          <=  w_PLANK_data[143:136];
            end
        end
    end

    reg[2:0] PLANK_SM;
    localparam PLANK_Initial = 3'd1;
    localparam PLANK_Fdbck_Temp_send   = 3'd2;
    localparam PLANK_Temp_Send = 3'd3;
    localparam PLANK_ADC_send = 3'd4;

    always @(posedge i_clk or negedge w_rst_n) begin
        if (~w_rst_n) begin
            r_send_counter <= 4'd0;
            r_uart_tx_data      <= 0;
            r_uart_tx_valid     <= 0;
            r_buff_send_Uart  <= 0;
            r_buff_send_ADC <= 0;
            PLANK_SM <= PLANK_Initial;
            r_FDBCK_pending <= 0;
            r_temp_pending <= 0;
            r_ADC_pending <= 1'b0;
            r_Watchdog_ADC <= 0;
            r_ADC_buff_set_data <= 88'd0;
        end else begin
            r_uart_tx_valid <= 0;
            if (r_PLANK_data_valid_buff5) begin
                r_FDBCK_pending <= 1'b1;
            end

            // r_Watchdog_ADC <= r_Watchdog_ADC + 1'b1;
            // if (r_Watchdog_ADC > 32'd1110000) begin
            //     r_Watchdog_ADC <= 0;
            //     r_ADC_pending <= 1'b1;
            //     r_ADC_buff_set_data <= {80'd0,8'hCC};
            // end

            if (r_ADC_buff_Valid) begin
                r_Watchdog_ADC <= 0;
                r_ADC_pending <= 1'b1;
                r_ADC_buff_set_data <= r_ADC_set_data;
            end
            if (~w_uart_tx_active) begin
                case (PLANK_SM)
                    PLANK_Initial: begin
                        PLANK_SM <= PLANK_Initial;
                        if (r_FDBCK_pending) begin
                            PLANK_SM <= PLANK_Fdbck_Temp_send;
                            r_FDBCK_pending <= 1'b0;
                            r_buff_send_Uart <= r_FDB_Chnnl;
                        end 
                        else if (r_ADC_pending) begin
                            r_buff_send_ADC <= r_ADC_buff_set_data;
                            r_ADC_pending <= 1'b0;
                            PLANK_SM <= PLANK_ADC_send;
                        end 
                    end
                    PLANK_Fdbck_Temp_send: begin
                        if (r_send_counter < 3'd3) begin
                            r_uart_tx_valid <= 1;
                            r_uart_tx_data  <= r_buff_send_Uart[7:0];
                            r_buff_send_Uart <= (r_buff_send_Uart >> 8);
                            r_send_counter <= r_send_counter + 1;
                        end else begin
                            r_send_counter <= 0;
                            PLANK_SM <= PLANK_Initial;
                        end
                    end
                    PLANK_ADC_send : begin
                        if (r_send_counter < 4'd11) begin
                            r_uart_tx_valid <= 1;
                            r_uart_tx_data  <= r_buff_send_ADC[7:0];
                            r_buff_send_ADC <= (r_buff_send_ADC >> 8);
                            r_send_counter <= r_send_counter + 1;
                        end else begin
                            r_send_counter <= 0;
                            PLANK_SM <= PLANK_Temp_Send;
                        end
                    end
                    PLANK_Temp_Send : begin
                        PLANK_SM <= PLANK_Temp_Send;
                        if (r_VCC_GND_Temp_valid) begin
                            r_buff_send_Uart <= r_VCC_GND_Temp;
                            PLANK_SM <= PLANK_Fdbck_Temp_send;
                        end
                    end
                    default: begin
                        PLANK_SM <= PLANK_Initial;
                    end
                endcase
            end
        end
    end

    assign o_attn_ch2 = (i_inhibit & r_soft_inhibit) ? {6{i_attn_31p5}} : r_attn_ch2;
    assign o_attn_ch1 = (i_inhibit & r_soft_inhibit) ? {6{i_attn_31p5}} : r_attn_ch1;
    assign o_attn_ch3 = (i_inhibit & r_soft_inhibit) ? {6{i_attn_31p5}} : r_attn_ch3;
    assign o_attn_ch4 = (i_inhibit & r_soft_inhibit) ? {6{i_attn_31p5}} : r_attn_ch4;
    assign o_attn_ch5 = (i_inhibit & r_soft_inhibit) ? {6{i_attn_31p5}} : r_attn_ch5;
    assign o_attn_ch6 = (i_inhibit & r_soft_inhibit) ? {6{i_attn_31p5}} : r_attn_ch6;
    assign o_attn_ch7 = (i_inhibit & r_soft_inhibit) ? {6{i_attn_31p5}} : r_attn_ch7;
    assign o_attn_ch8 = (i_inhibit & r_soft_inhibit) ? {6{i_attn_31p5}} : r_attn_ch8;

    assign o_phase_ch1 = (i_inhibit & r_soft_inhibit) ? (i_phase_180<<5) : r_phase_ch1;
    assign o_phase_ch2 = (i_inhibit & r_soft_inhibit) ? (i_phase_180<<5) : r_phase_ch2;
    assign o_phase_ch3 = (i_inhibit & r_soft_inhibit) ? (i_phase_180<<5) : r_phase_ch3;
    assign o_phase_ch4 = (i_inhibit & r_soft_inhibit) ? (i_phase_180<<5) : r_phase_ch4;
    assign o_phase_ch5 = (i_inhibit & r_soft_inhibit) ? (i_phase_180<<5) : r_phase_ch5;
    assign o_phase_ch6 = (i_inhibit & r_soft_inhibit) ? (i_phase_180<<5) : r_phase_ch6;
    assign o_phase_ch7 = (i_inhibit & r_soft_inhibit) ? (i_phase_180<<5) : r_phase_ch7;
    assign o_phase_ch8 = (i_inhibit & r_soft_inhibit) ? (i_phase_180<<5) : r_phase_ch8;

    assign o_TR_Pulse  = (i_inhibit & r_soft_inhibit) ? i_TR_pulse : r_tx_rx_sel;

    assign o_ch_power = r_ch_power;


endmodule