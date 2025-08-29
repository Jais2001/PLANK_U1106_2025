module spi_slave
(
    input wire i_rst,
    input wire i_SPI_MOSI,
    output wire o_SPI_MISO,
    input wire i_sclk,
    input wire i_CS
);

reg r_SPI_MISO;
reg[15:0] r_data_send = 16'h0BC0;
reg[3:0] r_send_cnt;
reg[7:0] r_received_data;
reg[2:0] r_receive_cnt;

reg[7:0] r_Chnnl_get_data[8:0];
reg r_start;
reg[2:0] r_jst_inc;

reg[2:0] send_MISO;
localparam SM_Setup = 3'd0;
localparam SM_Dummy_start = 3'd1;
localparam SM_Start = 3'd2;

assign o_SPI_MISO = r_SPI_MISO;

initial begin
    r_Chnnl_get_data[0] = 8'h86;
    r_Chnnl_get_data[1] = 8'h8e;
    r_Chnnl_get_data[2] = 8'h96;
    r_Chnnl_get_data[3] = 8'h9e;
    r_Chnnl_get_data[4] = 8'hc6;
    r_Chnnl_get_data[5] = 8'hce;
    r_Chnnl_get_data[6] = 8'hd6;
    r_Chnnl_get_data[7] = 8'hde;
    r_Chnnl_get_data[8] = 8'hee;
    r_Chnnl_get_data[9] = 8'hf6;
end

// to send data from slave - MISO - Mode 0
always @(negedge i_sclk or negedge i_rst) begin
    if (~i_rst) begin
        send_MISO <= SM_Setup;
        r_jst_inc <= 3'd0;
        r_SPI_MISO <= 1'b0;
        r_send_cnt <= 4'd0;
    end else begin
        case (send_MISO)
            SM_Setup: begin
                send_MISO <= SM_Setup;
                if (r_start) begin
                    send_MISO <= SM_Start;
                    r_jst_inc <= 0;
                end
            end
            SM_Dummy_start : begin
                if (~i_CS) begin
                    if (r_jst_inc < 3'd7) begin
                        r_jst_inc <= r_jst_inc + 1'd1;
                    end else begin
                        r_jst_inc <= 3'd0;
                        send_MISO <= SM_Start;
                    end
                end
            end
            SM_Start : begin
                if (~i_CS) begin
                    r_SPI_MISO <= r_data_send[15 - r_send_cnt];
                    if (r_send_cnt < 4'd15) begin
                        r_send_cnt <= r_send_cnt + 1'b1;
                    end else begin
                        r_send_cnt <= 4'd0;
                        send_MISO <= SM_Setup;
                        $display("Data trnsmitted from Slave");
                    end
                end
            end
            default: begin
                send_MISO <= SM_Setup;
            end
    endcase
    end
end

// to get data from master - MOSI - Mode 0
always @(posedge i_sclk or negedge i_rst) begin
    if (~i_rst) begin
        r_receive_cnt <= 3'd7;
        r_received_data <= 8'd0;
        r_start <= 1'b0;
    end else begin
        if (~i_CS) begin
            r_received_data[r_receive_cnt] <= i_SPI_MOSI;
            if (r_receive_cnt > 3'd0) begin
                r_receive_cnt <= r_receive_cnt - 1'b1;
            end else begin
                r_receive_cnt <= 3'd7;
                r_received_data <= 8'd0;
                r_start <= 1'b0;
                // $display("Received data from Master %h",r_received_data);
                if (r_received_data == r_Chnnl_get_data[0] || r_received_data == r_Chnnl_get_data[1] || 
                    r_received_data == r_Chnnl_get_data[2] || r_received_data == r_Chnnl_get_data[3] || 
                    r_received_data == r_Chnnl_get_data[4] || r_received_data == r_Chnnl_get_data[5] || 
                    r_received_data == r_Chnnl_get_data[6] || r_received_data == r_Chnnl_get_data[7] || 
                    r_received_data == r_Chnnl_get_data[8] || r_received_data == r_Chnnl_get_data[9])
                begin
                    r_start <= 1'b1;
                    $display("Received data from Master %h",r_received_data);
                end
                // $display("Received data from Master %h",r_received_data);
            end
        end else begin
            r_receive_cnt <= 3'd7;
            r_received_data <= 8'd0;
        end
        // r_start <= 1'b0;
        // if (r_received_data inside {r_Chnnl_get_data[0], r_Chnnl_get_data[1], r_Chnnl_get_data[2], 
        //                    r_Chnnl_get_data[3], r_Chnnl_get_data[4], r_Chnnl_get_data[5],
        //                    r_Chnnl_get_data[6], r_Chnnl_get_data[7], r_Chnnl_get_data[8], 
        //                    r_Chnnl_get_data[9]}) 
        // begin
        //     r_start <= 1'b1;
        // end
    end
end

endmodule