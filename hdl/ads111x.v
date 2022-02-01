//=============================================================
// 	Engineer:				Brian Sune
//	File:					ads111x.v
//	Date (YYYY,MM,DD):		2022/1
//	Aim:					ADS111x - 16-bit ADC
//	
//=============================================================

module ads111x #(
	// System clock frequency in MHz
	parameter system_clk_freq = 200,
	// I2C bps
	parameter i2c_clk_setup_bps = 200000,
	// I2C high-speed bps
	parameter i2c_clk_normal_bps = 1000000,
	// slave address
	parameter ads111x_a = 2'b00,
	parameter ads111x_series = 5
)(
	
	input			sys_clk,
	input 			sys_nrst,
	
	// read / write = 1 / 0
	input			i2c_rw,
	input			i2c_start,
	output			ready,
	output			done,
	
	// ==========================================
	input	[2 : 0]		adc_ptr,
	
	input	[15 : 0]	adc_thr,
	
	// ==========================================
	input				adc_status_w,
	input	[2 : 0]		adc_mux_w,
	input	[2 : 0]		adc_pga_w,
	input				adc_op_m_w,
	
	input	[2 : 0]		adc_dr_w,
	input				adc_cmp_mod_w,
	input				adc_cmp_pol_w,
	input				adc_cmp_lat_w,
	input	[1 : 0]		adc_cmp_que_w,
	
	// ==========================================
	output				adc_status_r,
	output	[2 : 0]		adc_mux_r,
	output	[2 : 0]		adc_pga_r,
	output				adc_op_m_r,
	
	output	[2 : 0]		adc_dr_r,
	output				adc_cmp_mod_r,
	output				adc_cmp_pol_r,
	output				adc_cmp_lat_r,
	output	[1 : 0]		adc_cmp_que_r,
	
	// ==========================================
	output	[15 : 0]	adc_conv_r,
	output	[15 : 0]	adc_lo_trh_r,
	output	[15 : 0]	adc_hi_trh_r,
	
	// Physical Layer Interface
	output			scl,
	inout			sda
);
	
	
	// =========================================================
	//	Write Explain
	// =========================================================
	//
	//		P1 P0 | 0 0			Conversion Register
	//		P1 P0 | 0 1			Config Register
	//		P1 P0 | 1 0			Lo Threshold Register
	//		P1 P0 | 1 1			Hi Threshold Register
	//
	//		Apply to raw data and Lo Hi Threshold
	//
	//        Address           Control          ADC             ADC
	// 	 |S|1 0 0 1 0 A A 0|0 0 0 0 0 0 P P|D D D D D D D D|D D D D D D D D|
	// 	 | |          1 0  |            1 0|1 1 1 1 1 1 9 8|7 6 5 4 3 2 1 0|
	// 	 | |               |               |5 4 3 2 1 0    |               |
	//
	//        Address           Control          ADC             ADC
	// 	 |S|1 0 0 1 0 A A 0|0 0 0 0 0 0 0 1|O M M M P P P M|D D D C C C C C|
	// 	 | |          1 0  |               |1 2 1 0 2 1 0  |2 1 0 M P L Q Q|
	// 	 | |               |               |               |            1 0|
	// 	
	// =========================================================
	
	// =========================================================
	//	Read Explain
	// =========================================================
	//
	//         Address           Control          ADC             ADC
	// 	 |S|1 0 0 1 0 A A 0|0 0 0 0 0 0 P P|D D D D D D D D|D D D D D D D D|
	// 	 | |          1 0  |            1 0|1 1 1 1 1 1 9 8|7 6 5 4 3 2 1 0|
	// 	 | |               |               |5 4 3 2 1 0    |               |
	// 	
	// =========================================================
	
	// =========================================================
	// local parameter
	// =========================================================
	localparam clock_cnt_setup = (system_clk_freq * 1000000) / i2c_clk_setup_bps / 5;
	localparam limit_setup1 = clock_cnt_setup;
	localparam limit_setup2 = clock_cnt_setup*2;
	localparam limit_setup3 = clock_cnt_setup*3;
	localparam limit_setup4 = clock_cnt_setup*4;
	localparam limit_setup5 = (clock_cnt_setup*5) - 1;
	
	localparam clock_cnt_general = (system_clk_freq * 1000000) / i2c_clk_normal_bps / 5;
	localparam limit_general1 = clock_cnt_general;
	localparam limit_general2 = clock_cnt_general*2;
	localparam limit_general3 = clock_cnt_general*3;
	localparam limit_general4 = clock_cnt_general*4;
	localparam limit_general5 = (clock_cnt_general*5) - 1;
	
	// high-speed mode
	localparam dac_hsm = (i2c_clk_normal_bps > 400000) ? 1'b1 : 1'b0;
	
	// 7 bit slave address
	localparam ads111x_saddr = {5'b1001_0, ads111x_a};
	
	localparam	wr_start_bit1		= 0,
				wr_high_speed_mode	= wr_start_bit1 + 1,
				wr_start_bit2		= wr_high_speed_mode + 1,
				wr_slave_addr		= wr_start_bit2 + 1,
				
				w_pointer			= wr_slave_addr + 1,
				
				wr_data_byte0		= w_pointer + 1,
				wr_data_byte1		= wr_data_byte0 + 1,
				
				wr_pre_check		= wr_data_byte1 + 1,
				wr_contd_check		= wr_pre_check + 1,
				
				wr_stop_bit			= wr_contd_check + 1,
				wr_end_pulse		= wr_stop_bit + 1,
				wr_end_return		= wr_end_pulse + 1,
				// --------------------------------------------
				wr_data_bit0		= wr_end_return + 1,
				wr_data_bit1		= wr_data_bit0 + 1,
				wr_data_bit2		= wr_data_bit1 + 1,
				wr_data_bit3		= wr_data_bit2 + 1,
				wr_data_bit4		= wr_data_bit3 + 1,
				wr_data_bit5		= wr_data_bit4 + 1,
				wr_data_bit6		= wr_data_bit5 + 1,
				wr_data_bit7		= wr_data_bit6 + 1,
				// --------------------------------------------
				r_ack_set			= wr_data_bit7 + 1,
				// --------------------------------------------
				w_ack_get			= r_ack_set + 1,
				w_ack_check			= w_ack_get + 1;
	// =========================================================
	
	reg		[5 : 0]		next_stage;
	reg		[5 : 0]		store_stage;
	
	reg		[23 : 0]	sclk_cnt;
	
	reg		[23 : 0]	sclk_limit1;
	reg		[23 : 0]	sclk_limit2;
	reg		[23 : 0]	sclk_limit3;
	reg		[23 : 0]	sclk_limit4;
	reg		[23 : 0]	sclk_limit5;
	
	reg		[7 : 0]		tmp_r;
	reg		[15 : 0]	buff_r;
	reg		[7 : 0]		data_r		[2 : 0];
	
	// ======================================
	reg		[2 : 0]		adc_ptr_r;
	
	reg		[15 : 0]	adc_conv_r_r;
	reg		[15 : 0]	adc_lo_trh_r_r;
	reg		[15 : 0]	adc_hi_trh_r_r;
	
	reg					adc_status_r_r;
	reg		[2 : 0]		adc_mux_r_r;
	reg		[2 : 0]		adc_pga_r_r;
	reg					adc_op_m_r_r;
	
	reg		[2 : 0]		adc_dr_r_r;
	reg					adc_cmp_mod_r_r;
	reg					adc_cmp_pol_r_r;
	reg					adc_cmp_lat_r_r;
	reg		[1 : 0]		adc_cmp_que_r_r;
	// ======================================
	
	// ======================================
	reg					scl_r;
	reg					sda_r;
	
	reg					ack_r;
	reg					done_r;
	reg					io_sel_r;
	
	reg					ready_r;
	
	reg					wr_latch;
	reg					rd_latch;
	
	reg					addr_w;
	// ======================================
	
	// =========================================================
	// Signal feed out
	// =========================================================
	assign done				= done_r;
	
	assign adc_conv_r		= adc_conv_r_r;
	assign adc_lo_trh_r		= adc_lo_trh_r_r;
	assign adc_hi_trh_r		= adc_hi_trh_r_r;
	
	// -----------------------------------------------------------------------------
	assign {	adc_status_r, adc_mux_r, adc_pga_r, adc_op_m_r,
				adc_dr_r, adc_cmp_mod_r, adc_cmp_pol_r,
				adc_cmp_lat_r, adc_cmp_que_r
			} = {	adc_status_r_r, adc_mux_r_r, adc_pga_r_r, adc_op_m_r_r,
				adc_dr_r_r, adc_cmp_mod_r_r, adc_cmp_pol_r_r,
				adc_cmp_lat_r_r, adc_cmp_que_r_r
			};
	// -----------------------------------------------------------------------------
	
	assign scl				= scl_r;
	assign ready			= ready_r;
	
	//sda data bidirectional
	assign sda = io_sel_r ? sda_r : 1'bz;
	
	
	wire				adc_status_c;
	wire	[2 : 0]		adc_mux_c;
	wire	[2 : 0]		adc_pga_c;
	wire				adc_op_m_c;
	
	wire				adc_cmp_mod_c;
	wire	[2 : 0]		adc_dr_c;
	wire				adc_cmp_pol_c;
	wire				adc_cmp_lat_c;
	wire	[1 : 0]		adc_cmp_que_c;
	
	generate
		if(ads111x_series == 3)begin : ADS1113_ctrl
			
			assign adc_status_c = adc_status_w;
			assign adc_mux_c = 3'b000;
			assign adc_pga_c = adc_pga_w;
			assign adc_op_m_c = adc_op_m_w;
			
			assign adc_dr_c = adc_dr_w;
			assign adc_cmp_mod_c = 1'b0;
			assign adc_cmp_mod_c = 1'b0;
			assign adc_cmp_pol_c = 1'b0;
			assign adc_cmp_lat_c = 1'b0;
			assign adc_cmp_que_c = 2'b00;
			
		end else if(ads111x_series == 4)begin : ADS1114_ctrl
			
			assign adc_status_c = adc_status_w;
			assign adc_mux_c = 3'b000;
			assign adc_pga_c = adc_pga_w;
			assign adc_op_m_c = adc_op_m_w;
			
			assign adc_dr_c = adc_dr_w;
			assign adc_cmp_mod_c = adc_cmp_mod_w;
			assign adc_cmp_pol_c = adc_cmp_pol_w;
			assign adc_cmp_lat_c = adc_cmp_lat_w;
			assign adc_cmp_que_c = adc_cmp_que_w;
			
		end else if(ads111x_series == 5)begin : ADS1115_ctrl
			
			assign adc_status_c = adc_status_w;
			assign adc_mux_c = adc_mux_w;
			assign adc_pga_c = adc_pga_w;
			assign adc_op_m_c = adc_op_m_w;
			
			assign adc_dr_c = adc_dr_w;
			assign adc_cmp_mod_c = adc_cmp_mod_w;
			assign adc_cmp_pol_c = adc_cmp_pol_w;
			assign adc_cmp_lat_c = adc_cmp_lat_w;
			assign adc_cmp_que_c = adc_cmp_que_w;
			
		end else begin
			illegal_parameter_condition_triggered_will_instantiate_an non_existing_module();
		end
	endgenerate
	
	always@(posedge sys_clk or negedge sys_nrst)begin
		if(!sys_nrst)begin
			
			adc_ptr_r <= 3'b000;
			
			data_r[0] <= 8'h00;
			data_r[1] <= 8'h00;
			data_r[2] <= 8'h00;
		end else if(
			( (next_stage == wr_start_bit1 & !i2c_rw) || 
			(next_stage == wr_contd_check & (!i2c_rw & wr_latch)) ) & i2c_start
		)begin
			
			adc_ptr_r <= adc_ptr;
			
			data_r[0] <= {6'b0000_00, adc_ptr[1:0]};
			
			if(adc_ptr[1:0] == 2'b01)begin
				data_r[1] <= {adc_status_c, adc_mux_c, adc_pga_c, adc_op_m_c};
				data_r[2] <= {adc_dr_c, adc_cmp_mod_c, adc_cmp_pol_c, adc_cmp_lat_c, adc_cmp_que_c};
			end else if(adc_ptr[1:0] > 2'b01)begin
				data_r[1] <= adc_thr[8+:8];
				data_r[2] <= adc_thr[0+:8];
			end else begin
				data_r[1] <= 8'h00;
				data_r[2] <= 8'h00;
			end
		end
	end
	
	always@(posedge sys_clk or negedge sys_nrst)begin
		if(!sys_nrst)begin
			
			adc_conv_r_r	<= 16'h0000;
			adc_lo_trh_r_r	<= 16'h8000;
			adc_hi_trh_r_r	<= 16'h7FFF;
			
			{
				adc_status_r_r, adc_mux_r_r, adc_pga_r_r, adc_op_m_r_r,
				adc_dr_r_r, adc_cmp_mod_r_r, adc_cmp_pol_r_r,
				adc_cmp_lat_r_r, adc_cmp_que_r_r
			} <= 16'h8583;
			
		end else if(next_stage == wr_contd_check & rd_latch)begin
			case(adc_ptr_r[1:0])
				2'b00: adc_conv_r_r <= buff_r;
				
				2'b01: begin
					{
						adc_status_r_r, adc_mux_r_r, adc_pga_r_r, adc_op_m_r_r,
						adc_dr_r_r, adc_cmp_mod_r_r, adc_cmp_pol_r_r,
						adc_cmp_lat_r_r, adc_cmp_que_r_r
					} <= buff_r;
				end
				
				2'b10: adc_lo_trh_r_r <= buff_r;
				2'b11: adc_hi_trh_r_r <= buff_r;
			endcase
		end
	end
	
	always@(posedge sys_clk or negedge sys_nrst)begin
		
		if(!sys_nrst)begin
			
			next_stage <= 'd0;
			store_stage <= 'd0;
			sclk_cnt <= 'd0;
			
			sclk_limit1 <= limit_setup1;
			sclk_limit2 <= limit_setup2;
			sclk_limit3 <= limit_setup3;
			sclk_limit4 <= limit_setup4;
			sclk_limit5 <= limit_setup5;
			
			tmp_r <= 8'd0;
			buff_r <= 16'd0;
			
			scl_r <= 1'b1;
			sda_r <= 1'b1;
			
			ack_r <= 1'b1;
			done_r <= 1'b0;
			io_sel_r <= 1'b1;
			
			ready_r <= 1'b1;
			
			wr_latch <= 1'b0;
			rd_latch <= 1'b0;
			
			addr_w <= 1'b0;
			
		end else begin
			
			//I2C data write 
			if(i2c_start | (wr_latch ^ rd_latch))begin
				case(next_stage)
					//send IIC start signal
					wr_start_bit1, wr_start_bit2: begin
						
						if(sclk_cnt == 0)
							if(!(wr_latch | rd_latch))begin
								wr_latch <= !i2c_rw;
								rd_latch <= i2c_rw;
							end
							ready_r <= 1'b0;
						
						io_sel_r <= 1'b1;
						
						if(sclk_cnt == 0)
							scl_r <= 1'b1;
						else if(sclk_cnt == sclk_limit4)
							scl_r <= 1'b0;
						
						if(sclk_cnt == 0)
							sda_r <= 1'b1;
						else if(sclk_cnt == sclk_limit1)
							sda_r <= 1'b0;
						
						if(sclk_cnt == sclk_limit5)begin
							sclk_cnt <= 'd0;
							
							if(dac_hsm & next_stage != wr_start_bit2)begin
								next_stage <= wr_high_speed_mode;
							end else begin
								next_stage <= wr_slave_addr;
							end
						end else begin
							sclk_cnt <= sclk_cnt + 1'b1;
						end
					end
					
					wr_high_speed_mode: begin
						tmp_r <= 8'b0000_1000;
						
						if(sclk_cnt == sclk_limit1)begin
							sclk_cnt <= 'd0;
							next_stage <= wr_data_bit0;
						end else begin
							sclk_cnt <= sclk_cnt + 1'b1;
						end
						
						store_stage <= wr_start_bit2;
						addr_w <= 1'b1;
					end
					
					wr_slave_addr: begin
						tmp_r <= {ads111x_saddr, (!wr_latch | rd_latch)};
						
						if(sclk_cnt == sclk_limit1)begin
							sclk_cnt <= 'd0;
							next_stage <= wr_data_bit0;
						end else begin
							sclk_cnt <= sclk_cnt + 1'b1;
						end
						
						if(wr_latch)
							store_stage <= w_pointer;
						else
							store_stage <= wr_data_byte0;
						addr_w <= 1'b1;
					end
					
					w_pointer: begin
						tmp_r <= data_r[0];
						next_stage <= wr_data_bit0;
						
						if(data_r[0][1 : 0] == 2'b00 || adc_ptr_r[2])begin
							store_stage <= wr_pre_check;
						end else begin
							store_stage <= wr_data_byte0;
						end
					end
					
					wr_data_byte0: begin
						tmp_r <= data_r[1];
						next_stage <= wr_data_bit0;
						store_stage <= wr_data_byte1;
					end
					
					wr_data_byte1: begin
						tmp_r <= data_r[2];
						next_stage <= wr_data_bit0;
						store_stage <= wr_pre_check;
						
						if(rd_latch)begin
							buff_r <= {buff_r[0+:8], tmp_r};
						end
					end
					
					wr_pre_check: begin
						next_stage <= wr_contd_check;
						ready_r <= 1'b1;
						
						// pass 2nd rd data to reg
						if(rd_latch)
							buff_r <= {buff_r[0+:8], tmp_r};
					end
					
					wr_contd_check: begin
						ready_r <= 1'b0;
						
						if( ((!i2c_rw & wr_latch) | (i2c_rw & rd_latch)) & i2c_start )begin
							next_stage <= wr_start_bit2;
						end else begin
							next_stage <= wr_stop_bit;
						end
					end
					
					wr_stop_bit: begin
						io_sel_r <= 1'b1;
						
						if(sclk_cnt == 0)
							scl_r <= 1'b0;
						//scl first change from low to high 
						else if(sclk_cnt == sclk_limit1)
							scl_r <= 1'b1;
						
						if(sclk_cnt == 0)
							sda_r <= 1'b0;
						//sda low to high 
						else if(sclk_cnt == sclk_limit4)
							sda_r <= 1'b1;
						
						if(sclk_cnt == sclk_limit5)begin
							sclk_cnt <= 'd0;
							
							sclk_limit1 <= limit_setup1;
							sclk_limit2 <= clock_cnt_setup << 1;
							sclk_limit3 <= (clock_cnt_setup << 1) + clock_cnt_setup;
							sclk_limit4 <= clock_cnt_setup << 2;
							sclk_limit5 <= (clock_cnt_setup << 2) + clock_cnt_setup;
							
							next_stage <= wr_end_pulse;
						end else
							sclk_cnt <= sclk_cnt + 1'b1;
					end
					
					wr_end_pulse: begin
						if(sclk_cnt == sclk_limit1)begin
							sclk_cnt <= 'd0;
							done_r <= 1'b1;
							next_stage <= next_stage + 'd1;
						end else begin
							sclk_cnt <= sclk_cnt + 1'b1;
						end
					end
					
					wr_end_return: begin
						done_r <= 1'b0;
						ready_r <= 1'b1;
						next_stage <= 'd0;
						wr_latch <= 1'b0;
						rd_latch <= 1'b0;
					end
					
					//send Device Addr/Word Addr/Write Data
					wr_data_bit0, wr_data_bit1,
					wr_data_bit2, wr_data_bit3,
					wr_data_bit4, wr_data_bit5,
					wr_data_bit6, wr_data_bit7: begin
						
						sda_r <= tmp_r[wr_data_bit7-next_stage];
						
						if(wr_latch | addr_w)
							io_sel_r <= 1'b1;
						else
							io_sel_r <= 1'b0;
						
						if( (sclk_cnt == sclk_limit2) && rd_latch)
							tmp_r[wr_data_bit7-next_stage] <= sda;
						
						if(sclk_cnt == 0)
							scl_r <= 1'b0;
						else if(sclk_cnt == sclk_limit1)
							scl_r <= 1'b1;
						else if(sclk_cnt == sclk_limit3)
							scl_r <= 1'b0;
						
						if(sclk_cnt == sclk_limit5)begin
							sclk_cnt <= 'd0;
							
							if(next_stage == wr_data_bit7)
								if(wr_latch | addr_w)
									next_stage <= w_ack_get;
								else
									next_stage <= r_ack_set;
							else
								next_stage <= next_stage + 1;
							
						end else begin
							sclk_cnt <= sclk_cnt + 1'b1;
						end
					end
					
					r_ack_set: begin
						io_sel_r <= 1'b1;
						sda_r <= 1'b0;
						
						if(sclk_cnt == 0)
							scl_r <= 1'b0;
						else if(sclk_cnt == sclk_limit1)
							scl_r <= 1'b1;
						else if(sclk_cnt == sclk_limit3)
							scl_r <= 1'b0;
						
						if(sclk_cnt == sclk_limit5)begin
							sclk_cnt <= 'd0;
							next_stage <= store_stage;
						end else begin
							sclk_cnt <= sclk_cnt + 1'b1;
						end
					end
					
					w_ack_get: begin
						io_sel_r <= 1'b0;
						
						if(sclk_cnt == sclk_limit2)begin
							ack_r <= sda;
						end
						
						if(sclk_cnt == 0)
							scl_r <= 1'b0;
						else if(sclk_cnt == sclk_limit1)
							scl_r <= 1'b1;
						else if(sclk_cnt == sclk_limit3)
							scl_r <= 1'b0;
						
						if(sclk_cnt == sclk_limit5)begin
							sclk_cnt <= 'd0;
							next_stage <= w_ack_check;
							addr_w <= 1'b0;
						end else begin
							sclk_cnt <= sclk_cnt + 1'b1;
						end
					end
					
					w_ack_check: begin
						if(ack_r != 0 && store_stage != wr_start_bit2)begin
							next_stage <= 'd0;
							ready_r <= 1'b1;
						end else begin
							next_stage <= store_stage;
							
							if(dac_hsm)begin
								sclk_limit1 <= limit_general1;
								sclk_limit2 <= limit_general2;
								sclk_limit3 <= limit_general3;
								sclk_limit4 <= limit_general4;
								sclk_limit5 <= limit_general5;
							end
						end
					end
				endcase
				
			end
		end
	end
	
endmodule
