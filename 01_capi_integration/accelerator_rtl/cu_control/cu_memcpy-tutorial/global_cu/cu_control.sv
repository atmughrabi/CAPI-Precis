// -----------------------------------------------------------------------------
//
//    "CAPIPrecis Shared Memory Accelerator Project"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi atmughrabi@gmail.com/atmughra@ncsu.edu
// File   : cu_control.sv
// Create : 2019-12-08 01:39:09
// Revise : 2019-12-18 20:42:50
// Editor : sublime text3, tab size (4)
// -----------------------------------------------------------------------------


import GLOBALS_AFU_PKG::*;
// import GLOBALS_CU_PKG::*;
import CAPI_PKG::*;
import WED_PKG::*;
import AFU_PKG::*;
import CU_PKG::*;

module cu_control #(parameter NUM_READ_REQUESTS = 2) (
	input  logic              clock                       , // Clock
	input  logic              rstn_in                     ,
	input  logic              enabled_in                  ,
	input  WEDInterface       wed_request_in              ,
	input  ResponseBufferLine read_response_in            ,
	input  ResponseBufferLine prefetch_read_response_in   ,
	input  ResponseBufferLine prefetch_write_response_in  ,
	input  ResponseBufferLine write_response_in           ,
	input  ReadWriteDataLine  read_data_0_in              ,
	input  ReadWriteDataLine  read_data_1_in              ,
	input  BufferStatus       read_buffer_status          ,
	input  BufferStatus       prefetch_read_buffer_status ,
	input  BufferStatus       prefetch_write_buffer_status,
	input  BufferStatus       write_buffer_status         ,
	input  cu_configure_type  cu_configure                ,
	output cu_return_type     cu_return                   ,
	output logic              cu_done                     ,
	output logic [0:63]       cu_status                   ,
	output CommandBufferLine  read_command_out            ,
	output CommandBufferLine  prefetch_read_command_out   ,
	output CommandBufferLine  prefetch_write_command_out  ,
	output CommandBufferLine  write_command_out           ,
	output ReadWriteDataLine  write_data_0_out            ,
	output ReadWriteDataLine  write_data_1_out
);


	logic [0:63] cu_configure_1_latched;
	logic [0:63] cu_configure_2_latched;
	logic [0:63] cu_configure_3_latched;
	logic [0:63] cu_configure_4_latched;

	assign read_command_out           = 0;
	assign prefetch_read_command_out  = 0;
	assign prefetch_write_command_out = 0;
	assign write_command_out          = 0;
	assign write_data_0_out           = 0;
	assign write_data_1_out           = 0;

////////////////////////////////////////////////////////////////////////////
//enable logic
////////////////////////////////////////////////////////////////////////////

	// drive outputs
	always_ff @(posedge clock or negedge rstn_in) begin
		if(~rstn_in) begin
			cu_return.var1 <= 0; //CU_RETURN
			cu_return.var2 <= 0;  //CU_RETURN_2
			cu_done        <= 0;
		end else begin
			if(enabled_in)begin
				cu_return.var1 <= wed_request_in.payload.wed.size_send;
				cu_return.var2 <= wed_request_in.payload.wed.size_recive;
				cu_done        <= wed_request_in.valid;
			end
		end
	end

	always_ff @(posedge clock or negedge rstn_in) begin
		if(~rstn_in) begin
			cu_configure_1_latched <= 0;
			cu_configure_2_latched <= 0;
			cu_configure_3_latched <= 0;
			cu_configure_4_latched <= 0;
		end else begin
			if(enabled_in)begin
				if((|cu_configure.var1))
					cu_configure_1_latched <= cu_configure.var1;

				if((|cu_configure.var2))
					cu_configure_2_latched <= cu_configure.var2;

				if((|cu_configure.var3))
					cu_configure_3_latched <= cu_configure.var3;

				if((|cu_configure.var4))
					cu_configure_4_latched <= cu_configure.var4;
			end
		end
	end

	always_ff @(posedge clock or negedge rstn_in) begin
		if(~rstn_in) begin
			cu_status <= 0;
		end else begin
			if(enabled_in)begin
				cu_status <= (cu_configure_1_latched);
			end
		end
	end



endmodule