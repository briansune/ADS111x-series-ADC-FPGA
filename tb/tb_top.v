// ==================================================================
// 	Engineer:				Brian Sune
//	File:					tb_ads111x.v
//	Date (YYYY,MM,DD):		2022/1
//	Aim:					test bench
// ==================================================================

`timescale 1ns / 1ps

module tb_top;
	
	reg				clk, clk2, nrst;
	
	// IIC Physcial
	wire			i2c_scl;
	wire			i2c_sda;
	
	reg				i2c_sda_io;
	reg				i2c_sda_o;
	
	// bidirectional IO
	assign i2c_sda = i2c_sda_io ? i2c_sda_o : 1'bz;
	
	// 200 MHz system clock
	always begin
		#41.667 clk = ~clk;
	end
	
	always begin
		#2.5 clk2 = ~clk2;
	end
	
	top DUT(
		
		.sys_clk		(clk),
		.sys_nrst		(nrst),
		
		.scl			(i2c_scl),
		.sda			(i2c_sda)
	);
	
	reg		[5 : 0]		iic_fsm;
	reg		[3 : 0]		iic_cnt;
	
	reg		[1 : 0]		iic_sda_rec;
	reg		[1 : 0]		iic_scl_rec;
	
	reg		[7 : 0]		iic_data		[8 : 0];
	
	reg		[7 : 0]		iic_mask;
	
	reg		[7 : 0]		iic_addr;
	reg		[3 : 0]		iic_pointer;
	reg					iic_read_latch;
	reg					iic_write_latch;
	
	localparam slave_address_r = 8'b1001_0001;
	localparam slave_address_w = 8'b1001_0000;
	localparam slave_address_hs = 8'b0000_1000;
	
	always@(posedge clk2 or negedge nrst)begin
		if(!nrst)begin
			iic_fsm <= 'd0;
			iic_cnt <= -'d1;
			i2c_sda_io <= 'd0;
			i2c_sda_o <= 1'b0;
			
			iic_read_latch <= 'd0;
			iic_write_latch <= 'd0;
			
			iic_pointer <= -'d1;
			iic_addr <= 'd0;
			iic_mask <= 'h80;
			
			iic_data[0] <= 'h00;
			
			iic_data[1] <= $random() % 256;
			iic_data[2] <= $random() % 256;
			
			iic_data[3] <= 'h43;
			iic_data[4] <= 'h21;
			
			iic_data[5] <= 'h55;
			iic_data[6] <= 'hAA;
			
			iic_data[7] <= 'h7F;
			iic_data[8] <= 'h3C;
			
		end else begin
			
			iic_scl_rec[1] <= iic_scl_rec[0];
			iic_scl_rec[0] <= i2c_scl;
			
			iic_sda_rec[1] <= iic_sda_rec[0];
			iic_sda_rec[0] <= i2c_sda;
			
			case(iic_fsm)
				0: begin
					if(
						iic_sda_rec[1] & !iic_sda_rec[0] &
						iic_scl_rec[1] & iic_scl_rec[0]
					)begin
						iic_fsm <= 1;
					end
					i2c_sda_io <= 'd0;
					iic_pointer <= -'d1;
				end
				
				1: begin
					// stop condition
					if(
						!iic_sda_rec[1] & iic_sda_rec[0] &
						iic_scl_rec[1] & iic_scl_rec[0] &
						!iic_read_latch
					)begin
						iic_fsm <= 0;
						i2c_sda_io <= 'd0;
						iic_cnt <= -'d1;
					
					end else if(
						iic_sda_rec[1] & !iic_sda_rec[0] &
						iic_scl_rec[1] & iic_scl_rec[0] &
						!iic_read_latch
					)begin
						
						i2c_sda_io <= 'd0;
						iic_cnt <= -'d1;
						
					end else if(!iic_scl_rec[1] & iic_scl_rec[0])begin
						iic_cnt <= iic_cnt + 1;
						
						if(iic_cnt > 7)begin
							iic_cnt <= 'd0;
						end
						
						if(iic_cnt == 8)begin
							iic_mask <= 'h80;
						end else begin
							iic_mask <= iic_mask >> 1;
						end
						
						if((iic_cnt < 7 || iic_cnt == 'hF) & !iic_read_latch)begin
							iic_addr <= {iic_addr[6:0], i2c_sda};
						end
						
						if(iic_cnt == 8 && iic_write_latch | iic_read_latch )begin
							iic_pointer <= iic_pointer + 1;
						end
					end
					
					if(iic_cnt == 8 && iic_addr == slave_address_r & !(iic_scl_rec))begin
						iic_read_latch <= 1'b1;
					end
					
					if(iic_cnt == 8 && iic_addr == slave_address_w & !(iic_scl_rec))begin
						iic_write_latch <= 1'b1;
					end
					
					if(iic_read_latch & (iic_cnt < 8))begin
						i2c_sda_o <= iic_data[ ((iic_data[0][1:0]<<1) + 1 + iic_pointer) ][7-iic_cnt[2:0]];
					end
					
					if(
						iic_read_latch & (iic_pointer == 2) & (iic_cnt == 8) & !(|iic_scl_rec)
					)begin
						iic_read_latch <= 1'd0;
						iic_addr <= 'd0;
						i2c_sda_io <= 'd0;
						iic_pointer <= -'d1;
						i2c_sda_o <= 1'b0;
					end
					
					if( (iic_cnt == 8 & (&iic_scl_rec) & !iic_read_latch) | 
						(iic_read_latch & (iic_cnt < 7 | ( (iic_cnt == 7) & (&iic_scl_rec) ) ) )
						// (iic_addr == slave_address_hs)
					)begin
						i2c_sda_io <= 'd1;
					end else begin
						i2c_sda_io <= 'd0;
					end
				end
				
			endcase
		end
	end
	
	initial begin
		
		fork begin
			
			#100 clk <= 1'b0;
			clk2 <= 1'b0;
			nrst <= 1'b0;
			
			#50 nrst <= 1'b1;
			
		end join
	end
	
endmodule
// ==================================================================
// EOL
// ==================================================================
