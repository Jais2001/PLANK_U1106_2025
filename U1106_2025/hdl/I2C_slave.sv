// Include the provided I2C slave model
`timescale 1ns / 10ps

module i2c_slave_model (scl, sda, temperature);

	//
	// parameters
	//
	parameter I2C_ADR = 7'b001_0000;

	//
	// input && outpus
	//
	input scl;
	inout sda;

    input wire [15:0] temperature;

	//
	// Variable declaration
	//
	wire debug = 1'b1;

	reg [15:0] mem [7:0]; // initiate memory
	reg [7:0] mem_adr;   // memory address
	reg [7:0] mem_do;    // memory data output

	reg sta, d_sta;
	reg sto, d_sto;

	reg [7:0] sr;        // 8bit shift register
	reg       rw;        // read/write direction

	wire      my_adr;    // my address called ??
	wire      i2c_reset; // i2c-statemachine reset
	reg [2:0] bit_cnt;   // 3bit downcounter
	wire      acc_done;  // 8bits transfered
	reg       ld;        // load downcounter

	reg       sda_o;     // sda-drive level
	wire      sda_dly;   // delayed version of sda

    reg count = 1'b0;

	// statemachine declaration
	parameter idle        = 3'b000;
	parameter slave_ack   = 3'b001;
	parameter get_mem_adr = 3'b010;
	parameter gma_ack     = 3'b011;
	parameter data1       = 3'b100;
    parameter data2       = 3'b101;
	parameter data_ack    = 3'b110;
    parameter nack        = 3'b111;

	reg [2:0] state; // synopsys enum_state

    reg comp = 0;

	//
	// module body
	//
	initial
	begin
	   sda_o = 1'b1;
	   state = idle;
       
       mem[0] = 16'h0000; // Temperature register (updated from input)
       mem[1] = 16'h0960; // Configuration register - continuous conversion
       mem[2] = 16'h8000; // High limit register
       mem[3] = 16'h7FFF; // Low limit register
       mem[7] = 16'h0000; // Offset register
	end

	// generate shift register and update temperature register
	always @(posedge scl) begin
      mem[0] <= temperature; // Continuously update temperature register
	  sr <= #1 {sr[6:0],sda};
    end

	//detect my_address
	assign my_adr = (sr[7:1] == I2C_ADR);
	// FIXME: This should not be a generic assign, but rather
	// qualified on address transfer phase and probably reset by stop

	//generate bit-counter
	always @(posedge scl)
	  if(ld)
	    bit_cnt <= #1 3'b111;
	  else
	    bit_cnt <= #1 bit_cnt - 3'h1;

	//generate access done signal
	assign acc_done = !(|bit_cnt);

	// generate delayed version of sda
	// this model assumes a hold time for sda after the falling edge of scl.
	// According to the Phillips i2c spec, there s/b a 0 ns hold time for sda
	// with regards to scl. If the data changes coincident with the clock, the
	// acknowledge is missed
	// Fix by Michael Sosnoski
	assign #1 sda_dly = sda;


	//detect start condition
	always @(negedge sda)
	  if(scl)
	    begin
	        sta   <= #1 1'b1;
		    d_sta <= #1 1'b0;
		    sto   <= #1 1'b0;
	    if(debug)
	        $display("DEBUG i2c_slave (addr:%h); start condition detected at %t", I2C_ADR, $time);
	    end
	  else
	    sta <= #1 1'b0;

	always @(posedge scl)
	  d_sta <= #1 sta;

	// detect stop condition
	always @(posedge sda)
	  if(scl)
	    begin
	       sta <= #1 1'b0;
	       sto <= #1 1'b1;

	       if(debug)
	         $display("DEBUG i2c_slave (addr:%h); stop condition detected at %t", I2C_ADR, $time);
	    end
	  else
	    sto <= #1 1'b0;

	//generate i2c_reset signal
	assign i2c_reset = sta || sto;

	// generate statemachine
	always @(negedge scl or posedge sto)
	  if (sto || (sta && !d_sta) )
	    begin
	        state <= #1 idle; // reset statemachine

	        sda_o <= #1 1'b1;
	        ld    <= #1 1'b1;
	    end
	  else
	    begin
	        // initial settings
	        sda_o <= #1 1'b1;
	        ld    <= #1 1'b0;

	        case(state) // synopsys full_case parallel_case
	            idle: // idle state
	              if (acc_done && my_adr)
	                begin
	                    state <= #1 slave_ack;
	                    rw <= #1 sr[0];
	                    sda_o <= #1 1'b0; // generate i2c_ack

	                    #2;
	                    if(debug && rw)
	                      $display("DEBUG i2c_slave (addr:%h); command byte received (read) at %t", I2C_ADR, $time);
	                    if(debug && !rw)
	                      $display("DEBUG i2c_slave (addr:%h); command byte received (write) at %t", I2C_ADR, $time);

	                    if(rw)
	                      begin
	                          mem_do <= #1 mem[mem_adr][15:8]; 

	                          if(debug)
	                            begin
	                                #2 $display("DEBUG i2c_slave (addr:%h); data block read %x from address %x (1)", I2C_ADR, mem_do, mem_adr);
	                                #2 $display("DEBUG i2c_slave (addr:%h); memcheck [0]=%x, [1]=%x, [2]=%x", I2C_ADR, mem[4'h0], mem[4'h1], mem[4'h2]);
	                            end
	                      end
	                end
                    else if (acc_done && !my_adr) begin
                        state <= #1nack;
                    end

	            slave_ack:
	              begin
	                  if(rw)
	                    begin
	                        state <= #1 data1;
	                        sda_o <= #1 mem_do[7];
	                    end
	                  else
	                    state <= #1 get_mem_adr;

	                  ld    <= #1 1'b1;
	              end

	            get_mem_adr: // wait for memory address
	              if(acc_done)
	                begin
	                    state <= #1 gma_ack;
	                    mem_adr <= #1 sr; // store memory address
	                    sda_o <= #1 !(sr <= 15); // generate i2c_ack, for valid address

	                    if(debug)
	                      #1 $display("DEBUG i2c_slave (addr:%h); address received. adr=%x, ack=%b", I2C_ADR, sr, sda_o);
	                end

	            gma_ack:
	              begin
	                  state <= #1 data1;
	                  ld    <= #1 1'b1;
	              end

	            data1: // receive or drive data
	              begin
                      count <= 1'b1;
	                  if(rw)
	                    sda_o <= #1 mem_do[7];

	                  if(acc_done)
	                    begin
	                        state <= #1 data_ack;
	                        //mem_adr <= #2 mem_adr + 8'h1;
	                        sda_o <= #1 (rw && (mem_adr <= 15) ); // send ack on write, receive ack on read

	                        if(rw)
	                        begin
	                            #3 mem_do <= mem[mem_adr][7:0];
                                //comp <= 1'b1;
                                
	                            if(debug)
	                              #5 $display("DEBUG i2c_slave (addr:%h); data1 block read1 %x from address %x (2)", I2C_ADR, mem_do, mem_adr);
	                        end

	                        if(!rw)
	                          begin
	                              mem[ mem_adr[3:0] ][15:8] <= #1 sr; // store data in memory//////////////////////////

	                              if(debug)
	                                #2 $display("DEBUG i2c_slave (addr:%h); data block write %x to address %x", I2C_ADR, sr, mem_adr);
	                          end
	                    end
	              end

                data2: // receive or drive data
	            begin
                    count <= 1'b0;
	                if(rw)
	                  sda_o <= #1 mem_do[7];
	                if(acc_done)
	                begin
	                    state <= #1 data_ack;
	                    //mem_adr <= #2 mem_adr + 8'h1;
	                    sda_o <= #1 (rw && (mem_adr <= 15) ); // send ack on write, receive ack on read 
	                    if(!rw)
	                    begin
	                        mem[ mem_adr[3:0] ][7:0] <= #1 sr; // store data in memory//////////////////////////
	                        if(debug)
	                          #2 $display("DEBUG i2c_slave (addr:%h); data2 block write %x to address %x", I2C_ADR, sr, mem_adr);
	                    end
                        if (sto == 1) begin
                            sda_o <= 1'b0;
                        end
	                end
	            end

	            data_ack:
	            begin
	                ld <= #1 1'b1;
	                if(rw)
	                    if(sr[0]) // read operation && master send NACK
	                    begin
	                        state <= #1 idle;
	                        sda_o <= #1 1'b1;
	                    end
	                    else
	                    begin
                            if (count == 1'b1) begin
	                            state <= #1 data2;
	                            sda_o <= #1 mem_do[7];
                            end
                            else begin
                                state <= #1 idle;
	                        //sda_o <= #1 mem_do[7];
                            end
	                    end
	                else
	                begin
                        if(count == 1'b1) begin
                            state <= #1 data2;
	                        sda_o <= #1 1'b1;
                        end
                        else begin
                            state <= #1 idle;
	                    //sda_o <= #1 1'b1;
                        end
                    end
                    //if(comp == 1 && acc_done) begin
                    //    state <= #1 nack;
                    //end
	            end

                nack: // neg ack
	            begin
                    ld    <= #1 1'b1;
                   state <= idle;
	            end
	        endcase
	    end

	// read data from memory
	always @(posedge scl)
	  if(!acc_done && rw)
	    mem_do <= #1 {mem_do[6:0], 1'b1}; // insert 1'b1 for host ack generation

	// generate tri-states
	assign sda = sda_o ? 1'bz : 1'b0;


	//
	// Timing checks
	//

	wire tst_sto = sto;
	wire tst_sta = sta;

	specify
	  specparam normal_scl_low  = 4700,
	            normal_scl_high = 4000,
	            normal_tsu_sta  = 4700,
	            normal_thd_sta  = 4000,
	            normal_tsu_sto  = 4000,
	            normal_tbuf     = 4700,

	            fast_scl_low  = 1300,
	            fast_scl_high =  600,
	            fast_tsu_sta  = 1300,
	            fast_thd_sta  =  600,
	            fast_tsu_sto  =  600,
	            fast_tbuf     = 1300;

	//   $width(negedge scl, normal_scl_low);  // scl low time
	//   $width(posedge scl, normal_scl_high); // scl high time

	//   $setup(posedge scl, negedge sda &&& scl, normal_tsu_sta); // setup start
	//   $setup(negedge sda &&& scl, negedge scl, normal_thd_sta); // hold start
	//   $setup(posedge scl, posedge sda &&& scl, normal_tsu_sto); // setup stop

	//   $setup(posedge tst_sta, posedge tst_sto, normal_tbuf); // stop to start time
	endspecify

endmodule