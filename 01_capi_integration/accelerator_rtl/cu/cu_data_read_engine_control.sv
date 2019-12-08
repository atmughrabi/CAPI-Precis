// -----------------------------------------------------------------------------
//
//		"CAPIPrecis Shared Memory Accelerator Project"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi atmughrabi@gmail.com/atmughra@ncsu.edu
// File   : cu_data_read_engine_control.sv
// Create : 2019-11-18 16:39:26
// Revise : 2019-12-07 04:48:38
// Editor : sublime text3, tab size (4)
// -----------------------------------------------------------------------------

import GLOBALS_AFU_PKG::*;
import CAPI_PKG::*;
import WED_PKG::*;
import AFU_PKG::*;
import CU_PKG::*;

module cu_data_read_engine_control #(parameter CU_READ_CONTROL_ID = DATA_READ_CONTROL_ID) (
	input  logic                         clock                      , // Clock
	input  logic                         rstn                       ,
	input  logic                         enabled_in                 ,
	input  WEDInterface                  wed_request_in             ,
	input  ResponseBufferLine            read_response_in           ,
	input  ReadWriteDataLine             read_data_0_in             ,
	input  ReadWriteDataLine             read_data_1_in             ,
	input  BufferStatus                  read_command_buffer_status ,
	input  BufferStatus                  read_data_out_buffer_status,
	output CommandBufferLine             read_command_out           ,
	output ReadWriteDataLine             read_data_0_out            ,
	output ReadWriteDataLine             read_data_1_out            ,
	output logic [0:(ARRAY_SIZE_BITS-1)] read_job_counter_done
);


	//output latched
	CommandBufferLine read_command_out_latched;

	//input lateched
	WEDInterface       wed_request_in_latched  ;
	ResponseBufferLine read_response_in_latched;
	ReadWriteDataLine  read_data_0_in_latched  ;
	ReadWriteDataLine  read_data_1_in_latched  ;

	logic [0:(ARRAY_SIZE_BITS-1)] read_job_counter_done_latched;
	logic                         enabled                      ;
	logic                         enabled_cmd                  ;
	logic [                 0:63] next_offest                  ;



////////////////////////////////////////////////////////////////////////////
//enable logic
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			enabled <= 0;
		end else begin
			enabled <= enabled_in;
		end
	end

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			enabled_cmd <= 0;
		end else begin
			enabled_cmd <= enabled;
		end
	end

////////////////////////////////////////////////////////////////////////////
//Drive output
////////////////////////////////////////////////////////////////////////////


	// drive outputs
	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			read_command_out      <= 0;
			read_job_counter_done <= 0;
			read_data_0_out       <= 0;
			read_data_1_out       <= 0;
		end else begin
			if(enabled)begin
				read_command_out      <= read_command_out_latched;
				read_job_counter_done <= read_job_counter_done_latched;
				read_data_0_out       <= read_data_0_in_latched;
				read_data_1_out       <= read_data_1_in_latched;
			end
		end
	end

////////////////////////////////////////////////////////////////////////////
//Drive input
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			read_response_in_latched <= 0;
			read_data_0_in_latched   <= 0;
			read_data_1_in_latched   <= 0;
		end else begin
			if(enabled)begin
				read_response_in_latched <= read_response_in;
				read_data_0_in_latched   <= read_data_0_in;
				read_data_1_in_latched   <= read_data_1_in;
			end
		end
	end

////////////////////////////////////////////////////////////////////////////
//response tracking logic
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn)
			read_job_counter_done_latched <= 0;
		else begin
			if (read_response_in_latched.valid) begin
				read_job_counter_done_latched <= read_job_counter_done_latched + read_response_in_latched.cmd.real_size;
			end
		end
	end

////////////////////////////////////////////////////////////////////////////
//read commands sending logic
////////////////////////////////////////////////////////////////////////////


	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			wed_request_in_latched   <= 0;
			read_command_out_latched <= 0;
			next_offest              <= 0;
		end
		else begin
			if(~wed_request_in_latched.valid && enabled_cmd)
				wed_request_in_latched <= wed_request_in;

			if (wed_request_in_latched.valid && ~read_command_buffer_status.alfull && ~read_data_out_buffer_status.alfull && (|wed_request_in_latched.wed.size_send) && enabled_cmd) begin

				if(wed_request_in_latched.wed.size_send >= CACHELINE_ARRAY_NUM)begin
					wed_request_in_latched.wed.size_send   <= wed_request_in_latched.wed.size_send - CACHELINE_ARRAY_NUM;
					read_command_out_latched.cmd.real_size <= CACHELINE_ARRAY_NUM;

					if (wed_request_in_latched.wed.afu_config[3]) begin
						read_command_out_latched.command <= READ_CL_S;
						read_command_out_latched.size    <= 12'h080;
					end else begin
						read_command_out_latched.size    <= cmd_size_calculate(wed_request_in_latched.wed.size_send);
						read_command_out_latched.command <= READ_CL_NA;
					end

				end else if (wed_request_in_latched.wed.size_send < CACHELINE_ARRAY_NUM) begin
					wed_request_in_latched.wed.size_send   <= 0;
					read_command_out_latched.cmd.real_size <= wed_request_in_latched.wed.size_send;

					if (wed_request_in_latched.wed.afu_config[3]) begin
						read_command_out_latched.command <= READ_CL_S;
						read_command_out_latched.size    <= 12'h080;
					end else begin
						read_command_out_latched.size    <= cmd_size_calculate(wed_request_in_latched.wed.size_send);
						read_command_out_latched.command <= READ_PNA;
					end

				end

				read_command_out_latched.cmd.cu_id            <= CU_READ_CONTROL_ID;
				read_command_out_latched.cmd.cmd_type         <= CMD_READ;
				read_command_out_latched.cmd.cacheline_offest <= 0;
				read_command_out_latched.cmd.address_offest   <= next_offest;
				read_command_out_latched.cmd.array_struct     <= READ_DATA;

				read_command_out_latched.cmd.abt <= map_CABT(wed_request_in_latched.wed.afu_config[0:2]);
				read_command_out_latched.abt     <= map_CABT(wed_request_in_latched.wed.afu_config[0:2]);



				read_command_out_latched.valid <= 1'b1;

				read_command_out_latched.address <= wed_request_in_latched.wed.array_send + next_offest;

				next_offest <= next_offest + CACHELINE_SIZE;

			end else begin
				read_command_out_latched <= 0;
			end
		end
	end





endmodule