module tmp117#(
    parameter GROUND_SLAVE_ADD = 7'b1001000,
    parameter VCC_SLAVE_ADD = 7'b1001001
) (
    input wire i_clk,
    input wire i_rst,
    inout wire io_scl,
    inout wire io_sda,

    output wire[15:0] o_temp_data_GND,
    output wire[15:0] o_temp_data_VCC,
    output wire o_temp_ready_GND,
    output wire o_temp_ready_VCC
);

    localparam Temp_Result_register = 8'h00;
    localparam Config_register = 8'h01;

    // APB interface required signals
    localparam Start_I2C = 8'hE0;
    localparam Stop_I2C = 8'hD0;
    localparam Send_ACK = 8'hC4;
    localparam Send_NACK = 8'hC0;
    localparam Clear_SI = 8'hC4;

    reg [15:0] r_temp_data[1:0];
    reg r_temp_ready[1:0];

    reg[5:0] r_sm_state;
    reg[5:0] r_sm_next_state;
    reg[5:0] r_sm_INT_next_state;

    localparam SM_power_up = 6'd1;
    localparam SM_Start_I2C = 6'd2;
    localparam SM_WAIT_INT = 6'd3; 
    localparam SM_Clear_INT = 6'd4;
    localparam SM_Load_Slave_Add = 6'd5;
    localparam SM_Config_WR_TMP117 = 6'd6;
    localparam SM_Config_MSB_TMP117 = 6'd7;
    localparam SM_Config_LSB_TMP117 = 6'd8;
    localparam SM_Read_Setup = 6'd9;
    localparam SM_Write_APB = 6'd10; 
    localparam SM_Read_Initialise = 6'd11;
    localparam SM_Read_APB = 6'd12;
    localparam SM_Read_Set = 6'd13;
    localparam SM_Read_Data = 6'd14;
    localparam SM_Send_ACK_NACK = 6'd15;
    localparam SM_STOP_I2C = 6'd16;
    localparam SM_Read_Signal = 6'd17;
    localparam SM_Read_APB_1 = 6'd18;
    localparam SM_Read_Set_1 = 6'd19;
    
    reg[19:0] r_power_up_counter;
    localparam POWER_UP_TIME = 20'd160000; // 160ms

    reg [8:0] r_APB_ADRESS[1:0];

    reg [8:0] r_PADDR;
    reg  r_PENABLE;
    reg  r_PSEL;

    reg[7:0] r_PWDATA;
    reg r_PWRITE;
    wire w_INT;

    wire[7:0] w_PRDATA;
    wire w_SCLO;
    wire w_SDAO;

    reg  r_re_wr;

    reg r_slave_cnt;
    reg[1:0] r_config_done;
    reg r_ACK;

    reg r_read;

    reg [6:0] r_slave_address[1:0];

    initial begin
        r_slave_address[0] = GROUND_SLAVE_ADD;
        r_slave_address[1] = VCC_SLAVE_ADD;
    end

    assign io_sda = !w_SDAO ? 1'b0 : 1'bz;
    assign io_scl = !w_SCLO ? 1'b0 : 1'bz;

    COREI2C_C1 COREI2C_C1_inst(
        .PADDR(r_PADDR),
        .PCLK(i_clk),
        .PENABLE(r_PENABLE),
        .PRESETN(i_rst),
        .PSEL(r_PSEL),
        .PWDATA(r_PWDATA),
        .PWRITE(r_PWRITE),
        .SCLI(io_scl),
        .SDAI(io_sda),

        .INT(w_INT),
        .PRDATA(w_PRDATA),
        .SCLO(w_SCLO),
        .SDAO(w_SDAO)
    );

    always @(posedge i_clk or negedge i_rst) begin
        if (~i_rst) begin
            r_temp_data[0] <= 16'b0;
            r_temp_ready[0] <= 1'b0;
            r_temp_data[1] <= 16'b0;
            r_temp_ready[1] <= 1'b0;
            r_PENABLE <= 1'b0;
            r_PSEL <= 1'b0;
            r_PADDR <= 9'b0;
            r_PWDATA <= 8'b0;
            r_PWRITE <= 1'b0;
            r_re_wr <= 1'b0;
            r_slave_cnt <= 1'b0;
            r_power_up_counter <= 20'b0;
            r_config_done <= 2'b0;
            r_ACK <= 1'b0;
            r_sm_next_state <= SM_Config_WR_TMP117;
            r_sm_state <= SM_power_up;
            r_sm_INT_next_state <= SM_Load_Slave_Add;
        end else begin
            r_temp_ready[0] <= 1'b0;
            r_temp_ready[1] <= 1'b0;
            r_PENABLE <= 1'b0;
            // r_PSEL <= 1'b0;
            case (r_sm_state)
                SM_power_up: begin
                    if (r_power_up_counter < POWER_UP_TIME) begin
                        r_power_up_counter <= r_power_up_counter + 1'b1;
                    end else begin
                        r_sm_state <= SM_Start_I2C;
                        r_sm_next_state <= SM_Config_WR_TMP117;
                        r_config_done <= 0;
                        r_power_up_counter <= 20'b0;
                    end
                end
                SM_WAIT_INT: begin
                    if (w_INT) begin
                        r_sm_state <= SM_Clear_INT;
                    end else begin
                        r_sm_state <= SM_WAIT_INT;
                    end
                end
                SM_Write_APB:begin
                    r_PSEL <= 1'b1;
                    r_PWRITE <= 1'b1;
                    r_PENABLE <= 1'b1;
                    r_sm_state <= SM_WAIT_INT;
                end
                SM_Read_APB:begin
                    r_PSEL <= 1'b1;
                    r_PWRITE <= 1'b0;
                    r_PENABLE <= 1'b1;
                    r_sm_state <= SM_WAIT_INT;
                end
                SM_Read_APB_1:begin
                    r_PSEL <= 1'b1;
                    r_PWRITE <= 1'b0;
                    r_PENABLE <= 1'b1;
                    r_sm_state <= r_sm_INT_next_state;
                end
                SM_Clear_INT : begin
                    r_PENABLE <= 1'b1;
                    r_PSEL <= 1'b1;
                    r_PWRITE <= 1'b1;
                    r_PADDR <= 9'h00;      // Control register
                    r_PWDATA <= Clear_SI;  // Clear SI bit
                    if (!w_INT) begin
                        r_sm_state <= SM_Read_Signal;
                    end else begin
                        r_sm_state <= SM_Clear_INT;
                    end
                end   
                SM_Read_Signal: begin
                    r_sm_state <= r_sm_INT_next_state;
                    if(r_read == 1'b1) begin
                        r_PWRITE <= 1'b0;
                        r_PENABLE <= 1'b1;
                        r_PADDR <= 9'h08;
                    end
                end  
                SM_Start_I2C: begin
                    r_PSEL <= 1'b1;
                    r_PWRITE <= 1'b1;
                    r_PADDR <= 9'b0; // Address of APB's control register
                    r_PWDATA <= Start_I2C;// Data to be written to the control register for start bit
                    r_sm_state <= SM_Write_APB;
                    r_sm_INT_next_state <= SM_Load_Slave_Add;
                end
                SM_Load_Slave_Add: begin
                    r_PSEL <= 1'b1;
                    r_PWRITE <= 1'b1;
                    r_PADDR <= 9'h08; // APB Data register
                    r_PWDATA <= {r_slave_address[r_slave_cnt],r_re_wr}; // GND slave address
                    r_sm_state <= SM_Write_APB;
                    r_sm_INT_next_state <= r_sm_next_state;
                end
                SM_Config_WR_TMP117: begin
                    r_PSEL <= 1'b1;
                    r_PWRITE <= 1'b1;
                    r_PADDR <= 9'h08; // APB Data register
                    r_PWDATA <= Config_register; // Config register address
                    r_sm_state <= SM_Write_APB;
                    r_sm_INT_next_state <= SM_Config_MSB_TMP117;
                    r_config_done <= r_config_done + 1'b1;
                end
                SM_Config_MSB_TMP117: begin
                    r_PSEL <= 1'b1;
                    r_PWRITE <= 1'b1;
                    r_PADDR <= 9'h08; // APB Data register
                    r_PWDATA <= 8'h02; // Config register data of TMP117 
                    r_sm_state <= SM_Write_APB;
                    r_sm_INT_next_state <= SM_Config_LSB_TMP117;
                end
                SM_Config_LSB_TMP117: begin // 0220 - Continuios mode with 8 average cndtn
                    r_PSEL <= 1'b1;
                    r_PWRITE <= 1'b1;
                    r_PADDR <= 9'h08; // APB Data register
                    r_PWDATA <= 8'h20; // Config register data of TMP117
                    r_sm_state <= SM_Write_APB;
                    r_sm_INT_next_state <= SM_STOP_I2C;
                end
                SM_Read_Setup: begin
                    r_PSEL <= 1'b1;
                    r_read <= 1'b0;
                    r_PWRITE <= 1'b1;
                    r_PADDR <= 9'h08; // APB Data register
                    r_PWDATA <= Temp_Result_register; // Temp result register address
                    r_sm_state <= SM_Write_APB;
                    r_sm_INT_next_state <= SM_Read_Initialise;
                end           
                SM_Read_Initialise : begin
                    r_re_wr <= 1'b1;
                    r_PSEL <= 1'b1;
                    r_PWRITE <= 1'b1;
                    r_temp_data[r_slave_cnt] <= 16'b0;
                    r_ACK <= 1'b0;
                    r_PADDR <= 9'b0; // Address of APB's control register
                    r_PWDATA <= Start_I2C; // Data to be written to the control register for start bit
                    r_sm_state <= SM_Write_APB;
                    r_sm_INT_next_state <= SM_Load_Slave_Add;
                    r_sm_next_state <= SM_Read_Set;
                end
                SM_Read_Set : begin
                    r_PSEL <= 1'b1;
                    r_re_wr <= 1'b0;
                    r_read  <= 1'b1;
                    r_PWRITE <= 1'b0; // Read operation
                    r_PADDR <= 9'h08; // APB Data register
                    r_sm_state <= SM_Read_APB;
                    r_sm_INT_next_state <= SM_Read_Data;
                end
                SM_Read_Set_1 : begin
                    r_PSEL <= 1'b1;
                    r_re_wr <= 1'b0;
                    r_read  <= 1'b1;
                    r_PWRITE <= 1'b0; // Read operation
                    r_PADDR <= 9'h08; // APB Data register
                    r_sm_state <= SM_Read_APB_1;
                    r_sm_INT_next_state <= SM_Read_Data;
                end
                SM_Read_Data : begin
                    r_temp_data[r_slave_cnt] <= (r_temp_data[r_slave_cnt] << 8) | w_PRDATA;
                    r_ACK <= r_ACK + 1'b1;
                    r_sm_state <= SM_Send_ACK_NACK;
                    r_read <= 1'b0;
                end
                SM_Send_ACK_NACK : begin
                    r_PSEL <= 1'b1;
                    r_PWRITE <= 1'b1;
                    r_PADDR <= 9'b0;
                    r_sm_state <= SM_Write_APB;
                    if (r_ACK == 1'b1) begin
                        r_PWDATA <= Send_ACK; // Data to be written to the control register for ACK
                        r_sm_INT_next_state <= SM_Read_Set_1;
                    end else begin
                        r_PWDATA <= Send_NACK; // Data to be written to the control register for NACK
                        r_temp_ready[r_slave_cnt] <= 1'b1; // Temp data is ready
                        r_sm_INT_next_state <= SM_STOP_I2C;
                    end
                end
                SM_STOP_I2C : begin
                    r_PSEL <= 1'b1;
                    r_PWRITE <= 1'b1;
                    r_PADDR <= 9'b0; // Address of APB's control register
                    r_PWDATA <= Stop_I2C; // Data to be written to the control register for stop bit
                    r_slave_cnt <= r_slave_cnt + 1'b1;
                    r_sm_state <= SM_Write_APB;
                    r_sm_INT_next_state <= SM_Start_I2C;
                    if (r_config_done < 2'd2) begin
                        r_sm_next_state <= SM_Config_WR_TMP117;
                    end else begin
                        r_sm_next_state <= SM_Read_Setup;
                    end
                end
                default: begin
                    r_sm_state <= SM_power_up;
                end
            endcase
        end
    end

    assign o_temp_data_GND = r_temp_data[0];
    assign o_temp_data_VCC = r_temp_data[1];

    assign o_temp_ready_GND = r_temp_ready[0];
    assign o_temp_ready_VCC = r_temp_ready[1];

    
endmodule