`timescale 1ns / 1ps

module top(
	input			sys_clk,
	input 			sys_nrst,
	
	// Physical Layer Interface
	output			scl,
	inout			sda
);
	
	wire glb_clk;
	wire glb_nrst;
	
	sys_pll sys_pll_inst0(
		.clk_out1		(glb_clk),
		.locked			(glb_nrst),
		.clk_in1		(sys_clk)
	);
	
	reg i2c_rw;
	reg i2c_start;
	
	reg [2:0] adc_ptr;
	reg [15:0] adc_cfg;
	
	initial begin
		adc_cfg = 16'h8583;
	end
	
	wire i2c_rdy;
	wire i2c_done;
	
	wire [15 : 0] adc_conv;
	
	ads111x #(
		.system_clk_freq	(200),
		.i2c_clk_setup_bps	(400000),
		.i2c_clk_normal_bps	(3400000),
		.ads111x_a			(2'b00),
		.ads111x_series		(5)
	)ads111x_inst0(
		
		.sys_clk		(glb_clk),
		.sys_nrst		(glb_nrst),
		
		.scl			(scl),
		.sda			(sda),
		
		.i2c_rw			(i2c_rw),
		.i2c_start		(i2c_start),
		.ready			(i2c_rdy),
		.done			(i2c_done),
		
		.adc_ptr		(adc_ptr),
		
		.adc_thr		('d0),
		.adc_status_w	( adc_cfg[15] ),
		.adc_mux_w		( adc_cfg[14:12] ),
		.adc_pga_w		( adc_cfg[11:9] ),
		.adc_op_m_w		( adc_cfg[8] ),
		
		.adc_dr_w		( adc_cfg[7:5] ),
		.adc_cmp_mod_w	( adc_cfg[4] ),
		.adc_cmp_pol_w	( adc_cfg[3] ),
		.adc_cmp_lat_w	( adc_cfg[2] ),
		.adc_cmp_que_w	( adc_cfg[1:0] ),
		
		.adc_conv_r		(adc_conv)
	);
	
	reg		[7 : 0]		fsm_state;
	
	
	always@(posedge glb_clk or negedge glb_nrst)begin
		if(!glb_nrst)begin
			fsm_state <= 'd0;
			
			i2c_rw <= 'd0;
			i2c_start <= 'd0;
			adc_ptr <= 'd0;
			
		end else begin
			case(fsm_state)
				0: begin
					
					if(i2c_rdy)begin
						fsm_state <= fsm_state + 'd1;
						i2c_rw <= 1'b0;
						i2c_start <= 1'b1;
						adc_ptr <= 3'b001;
						adc_cfg <= 16'b1100_0100_1110_0011;
					end
				end
				
				1,3: begin
					if(!i2c_rdy)begin
						i2c_start <= 'd0;
						fsm_state <= fsm_state + 'd1;
					end
				end
				
				2: begin
					if(i2c_done)begin
						fsm_state <= fsm_state + 'd1;
						i2c_rw <= 1'b0;
						i2c_start <= 1'b1;
						adc_ptr <= 3'b000;
					end
				end
				
				4: begin
					if(i2c_done)begin
						fsm_state <= fsm_state + 'd1;
						i2c_rw <= 1'b1;
						i2c_start <= 1'b1;
					end
				end
				
				5: begin
					i2c_start <= 'd0;
					fsm_state <= fsm_state + 'd1;
				end
				
				6: begin
					i2c_rw <= 1'b1;
					i2c_start <= 1'b1;
					
					if(i2c_rdy)begin
						fsm_state <= fsm_state + 'd1;
					end
				end
				
				7: begin
					i2c_start <= 'd0;
					fsm_state <= fsm_state - 'd1;
				end
			endcase
		end
	end
	
	
endmodule
