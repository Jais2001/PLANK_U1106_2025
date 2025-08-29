`timescale 1ns/1ps

module tmp117_tb();
    bit i_clk = 0;
    bit i_rst;

    bit i_rx_serial;

    bit i_attn_31p5;
    bit i_phase_180;
    bit i_TR_pulse;
    bit i_inhibit;

    bit i_SPI_MISO;

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
    
    logic [15:0] w_temp_data_GND;
    logic [15:0] w_temp_data_VCC;
    logic w_temp_ready_GND;
    logic w_temp_ready_VCC;

    logic o_SPI_Clk;
    logic o_SPI_MOSI;
    logic o_CS;
    
    pullup(io_scl);
    pullup(io_sda);
    
    localparam Power_Up_Time = 160_000_000; 
    
    // TMP117 sensor temperature values
    logic [15:0] sensor_TB_temp_values [0:1];
    
    PLANK DUT(
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
        .io_sda(io_sda),
        .i_SPI_MISO(i_SPI_MISO),
        .o_SPI_Clk(o_SPI_Clk),
        .o_SPI_MOSI(o_SPI_MOSI),
        .o_CS(o_CS)
    );
    
    initial begin
        i_rst = 0;
        #100;  // Reset pulse
        i_rst = 1;
        sensor_TB_temp_values[0] = 16'h1234; // 36.41°C
        sensor_TB_temp_values[1] = 16'h2345; // 70.53°C
    end
    
    // TMP117 GND Address - Fixed SCL connection
    i2c_slave_model #(.I2C_ADR(7'b1001000)) TMP_GND(
        .scl(io_scl), 
        .sda(io_sda),
        .temperature(sensor_TB_temp_values[0])
    );
    
    // TMP117 VCC Address - Fixed SCL connection  
    i2c_slave_model #(.I2C_ADR(7'b1001001)) TMP_VCC(
        .scl(io_scl),  
        .sda(io_sda),
        .temperature(sensor_TB_temp_values[1])
    );

    spi_slave spi_slave_inst(
        .i_rst(i_rst),
        .i_SPI_MOSI(o_SPI_MOSI),
        .o_SPI_MISO(i_SPI_MISO),
        .i_sclk(o_SPI_Clk),
        .i_CS(o_CS)
    );
    
    // Clock generation
    always #5 i_clk = ~i_clk;  // 100MHz clock (10ns period)
    
    // Main test sequence
    initial begin
        i_rst = 0;
        #100;  // Reset pulse
        i_rst = 1;
        
        // Wait for power-up
        #Power_Up_Time;
        $display("Power-up complete at time %t", $time);
        
        repeat(10) begin
            @(posedge DUT.w_temp_ready_GND);
            $display("Time: %t, GND Temp: Expected=%h, Read=%h", 
                     $time, sensor_TB_temp_values[0][14:7], w_temp_data_GND[14:7]);
            
            @(posedge DUT.w_temp_ready_VCC);  
            $display("Time: %t, VCC Temp: Expected=%h, Read=%h", 
                     $time, sensor_TB_temp_values[1][14:7], w_temp_data_VCC[14:7]);
                     
            // Update temperatures for next cycle
            sensor_TB_temp_values[0] = sensor_TB_temp_values[0] + 16'h0080; // +1°C
            sensor_TB_temp_values[1] = sensor_TB_temp_values[1] + 16'h0100; // +2°C
            
            #100; // Wait 1ms between updates
        end
        
        $display("Test completed successfully!");
        $stop;
    end
    
    initial begin
        #500_000_000; // 500ms timeout
        $display("ERROR: Test timeout!");
        $stop;
    end
    
endmodule