// This Module gives out valid packet after verifying the header, footer, identifier and checksum 
module UART_packet_identifier(
    i_clk,
    i_rst_n,
    i_en,
    i_uart_rx_data,
    o_uart_rx_error,
    o_uart_rx_error_dv,
    i_uart_rx_valid,
    o_data,
    o_data_valid
);
    
    parameter HEADER = 8'hAA;

    parameter RX_PACKET_LEN = 32; // Total packet size In bytes inluding Identifier,data,checksum
    localparam RX_DATA_LEN = (RX_PACKET_LEN * 8) - 1;

    parameter IDENTIFIER_START_INDEX = 0;
    parameter IDENTIFIER_END_INDEX = 3;
    parameter IDENTIFIER = 4'hC;

    parameter CHECKSUM_END_INDEX = RX_DATA_LEN;
    parameter CHECKSUM_START_INDEX = CHECKSUM_END_INDEX - 7;

    parameter FOOTER = 8'h55;

    input wire i_clk;
    input wire i_rst_n;

    input wire i_en;

    // These signals need to come from the UART Rx module
    input wire [7:0] i_uart_rx_data;
    output wire [1:0] o_uart_rx_error;
    output wire o_uart_rx_error_dv;
    input wire i_uart_rx_valid;

    // This is the main output data. The data valid is pulsed once the data is ready
    output reg [RX_DATA_LEN : 0] o_data;
    output reg o_data_valid = 0;

    reg r_uart_rx_ready = 0; // This can be used to figure out whether the module is active or not
    reg r_rx_serial = 0; // This is to Buffer i_rx_serial

    reg [7:0] r_rx_checksum = 0;  // This will calculate the checksum as new bytes keep arriving
    reg [RX_DATA_LEN:0] r_rx_data = 0;  // This is the shift register to which data will be stored as it arrives

    reg [4:0] r_sm_rx = 0; // This is the main state machine for the incoming rx

    reg [1:0] r_uart_rx_error = 0;
    reg r_uart_rx_error_dv = 0;

    assign o_uart_rx_error = r_uart_rx_error;
    assign o_uart_rx_error_dv = r_uart_rx_error_dv; 
    // Rx state machine states
    localparam SM_HEADER_RX     = 5'd0;
    localparam SM_DATA_RX       = 5'd1;
    localparam SM_FOOTER_RX     = 5'd2;
    localparam SM_ERROR_CHECK_RX = 5'd3;

    // this is used for concatenating the received packets together
    reg [$clog2(RX_PACKET_LEN):0] r_byte_counter_rx = 0;

    reg [31:0] r_data_timeout = 0;

    // Purpose: Handle incoming RX 
    always @(posedge i_clk or negedge i_rst_n) begin
        if(i_rst_n == 1'b0) begin
            r_sm_rx                 <= SM_HEADER_RX;
            r_byte_counter_rx       <= 6'd1;
            r_uart_rx_ready         <= 1;
            o_data_valid            <= 0;
            o_data                  <= 0;
            r_uart_rx_error         <= 0;
            r_uart_rx_error_dv      <= 0;
            r_data_timeout          <= 0;
        end
        else begin
            if(i_en) begin
                // default assignments
                r_uart_rx_ready         <= 1;
                r_uart_rx_error_dv      <= 0;
                o_data_valid            <= 0;
                case (r_sm_rx)
                    SM_HEADER_RX:  begin
                        r_data_timeout          <= 0;
                        if(i_uart_rx_valid) begin
                            r_uart_rx_ready     <= 0;
                            if(i_uart_rx_data[7:0] == HEADER) begin
                                r_sm_rx <= SM_DATA_RX;
                                // clear all registers
                                r_rx_data           <= 0;
                                r_rx_checksum       <= 0;//8'hAA;
                                r_byte_counter_rx   <= 0;
                            end
                        end
                    end
                    // SM_IDENTIFIER_RX: begin
                    //     r_data_timeout          <= r_data_timeout + 1;
                    //     if(i_uart_rx_valid) begin
                    //         r_uart_rx_ready     <= 0;
                    //         // detect control packet
                    //         if(i_uart_rx_data[IDENTIFIER_END_INDEX:IDENTIFIER_START_INDEX] == IDENTIFIER) begin
                    //             r_sm_rx             <= SM_DATA_RX;
                    //             r_byte_counter_rx   <= 6'd1;
                    //             r_rx_data           <= {i_uart_rx_data[7:0],r_rx_data}>>8;
                    //             r_rx_checksum       <= r_rx_checksum ^ i_uart_rx_data[7:0];
                    //             r_data_timeout      <= 0;
                    //         end
                    //         else begin
                    //             r_sm_rx <= SM_HEADER_RX;
                    //         end
                    //     end
                    //     if(r_data_timeout > 32'd18000) begin
                    //         r_sm_rx <= SM_HEADER_RX;
                    //         r_uart_rx_error         <= 2'b11;
                    //         r_uart_rx_error_dv      <= 1;
                    //     end
                    // end
                    SM_DATA_RX: begin
                        r_data_timeout          <= r_data_timeout + 1;
                        if(i_uart_rx_valid) begin
                            r_data_timeout      <= 0;
                            r_uart_rx_ready     <= 0;
                            // Receive Checksum and go to footer check
                            if(r_byte_counter_rx >= RX_PACKET_LEN - 1) begin
                                r_sm_rx <= SM_FOOTER_RX; 
                            end
                            // Receiving Data therefore calculating footer
                            else begin
                                // last byte is checksum 
                                // checksum need not be done for the last byte
                                r_rx_checksum <= r_rx_checksum ^ i_uart_rx_data[7:0];
                            end
                            r_rx_data           <= {i_uart_rx_data[7:0],r_rx_data}>>8;
                            r_byte_counter_rx   <= r_byte_counter_rx + 1;
                        end
                        if(r_data_timeout > 32'd18000) begin
                            r_sm_rx <= SM_HEADER_RX;
                            r_uart_rx_error         <= 2'b11;
                            r_uart_rx_error_dv      <= 1;
                        end
                    end
                    SM_FOOTER_RX: begin
                        r_data_timeout          <= r_data_timeout + 1;
                        if(i_uart_rx_valid) begin
                            r_data_timeout      <= 0;
                            r_uart_rx_ready     <= 0;           
                            // check if footer is received
                            if(i_uart_rx_data[7:0] == FOOTER) begin
                                r_sm_rx <= SM_ERROR_CHECK_RX;
                            end
                            else begin
                                // footer not detected
                                r_sm_rx <= SM_HEADER_RX;    
                                r_uart_rx_error         <= 2'b10;
                                r_uart_rx_error_dv      <= 1;
                            end
                        end
                        if(r_data_timeout > 32'd18000) begin
                            r_sm_rx <= SM_HEADER_RX;
                            r_uart_rx_error         <= 2'b11;
                            r_uart_rx_error_dv      <= 1;
                        end
                    end
                    SM_ERROR_CHECK_RX: begin
                        r_sm_rx <= SM_HEADER_RX;
                        // checksum verification
                        if(r_rx_data[CHECKSUM_END_INDEX:CHECKSUM_START_INDEX] == (r_rx_checksum)) begin
                            o_data          <= r_rx_data;
                            o_data_valid    <= 1;
                        end
                        else begin
                            r_uart_rx_error         <= 2'b1;
                            r_uart_rx_error_dv      <= 1;
                        end
                    end
                    default: begin
                        r_sm_rx <= SM_HEADER_RX;
                    end
                endcase
            
            end
        end
    end

endmodule