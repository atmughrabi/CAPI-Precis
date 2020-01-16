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
	input  logic                         clock                         , // Clock
	input  logic                         rstn                          ,
	input  logic                         read_enabled_in               ,
	input  logic                         prefetch_enabled_in           ,
	input  WEDInterface                  wed_request_in                ,
	input  logic [                 0:63] cu_configure                  ,
	input  ResponseBufferLine            read_response_in              ,
	input  ReadWriteDataLine             read_data_0_in                ,
	input  ReadWriteDataLine             read_data_1_in                ,
	input  BufferStatus                  read_command_buffer_status    ,
	input  BufferStatus                  read_data_out_buffer_status   ,
	input  ResponseBufferLine            prefetch_response_in          ,
	input  BufferStatus                  prefetch_command_buffer_status,
	output CommandBufferLine             prefetch_command_out          ,
	output CommandBufferLine             read_command_out              ,
	output ReadWriteDataLine             read_data_0_out               ,
	output ReadWriteDataLine             read_data_1_out               ,
	output logic [0:(ARRAY_SIZE_BITS-1)] read_job_counter_done
);

	assign prefetch_command_out = 0;

	//output latched
	CommandBufferLine read_command_out_latched;

	//input lateched
	WEDInterface                  wed_request_in_latched       ;
	ResponseBufferLine            read_response_in_latched     ;
	ReadWriteDataLine             read_data_0_in_latched       ;
	ReadWriteDataLine             read_data_1_in_latched       ;
	logic [                 0:63] cu_configure_latched         ;
	logic                         send_to_write_engine         ;
	logic [0:(ARRAY_SIZE_BITS-1)] read_job_counter_done_latched;
	logic [0:(ARRAY_SIZE_BITS-1)] read_job_resp_done_latched   ;
	logic [0:(ARRAY_SIZE_BITS-1)] read_job_send_done_latched   ;
	logic                         enabled                      ;
	logic                         enabled_cmd                  ;
	logic [                 0:63] next_offest                  ;
	logic                         start_read                   ;


	CommandBufferLine             prefetch_command_out_latched ;
	WEDInterface                  wed_prefetch_in_latched      ;
	logic [0:(ARRAY_SIZE_BITS-1)] prefetch_counter_resp_latched;
	logic [0:(ARRAY_SIZE_BITS-1)] prefetch_counter_send_latched;
	logic [                 0:63] next_prefetch_offest         ;
	logic                         enabled_prefetch             ;
	logic                         start_prefetch               ;
	logic                         done_prefetch                ;
	logic                         do_prefetch                  ;

////////////////////////////////////////////////////////////////////////////
//enable logic
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			enabled <= 0;
		end else begin
			enabled <= read_enabled_in;
		end
	end

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			enabled_cmd      <= 0;
			enabled_prefetch <= 0;
		end else begin
			enabled_cmd      <= enabled;
			enabled_prefetch <= prefetch_enabled_in;
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
			if(enabled_cmd)begin
				read_response_in_latched <= read_response_in;
				read_data_0_in_latched   <= read_data_0_in;
				read_data_1_in_latched   <= read_data_1_in;
			end
		end
	end


	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			cu_configure_latched <= 0;
		end else begin
			if(enabled) begin
				if((|cu_configure))
					cu_configure_latched <= cu_configure;
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

	assign send_to_write_engine = (~read_data_out_buffer_status.alfull && cu_configure_latched[22]) ||  cu_configure_latched[21] || ~(cu_configure_latched[22] || cu_configure_latched[21]);
	assign start_read           = wed_request_in_latched.valid && ~read_command_buffer_status.alfull && send_to_write_engine && (|wed_request_in_latched.wed.size_send) && ~start_prefetch && done_prefetch && enabled_cmd;

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			wed_request_in_latched   <= 0;
			read_command_out_latched <= 0;
			next_offest              <= 0;
		end
		else begin
			if(~wed_request_in_latched.valid && enabled_cmd)
				wed_request_in_latched <= wed_request_in;

			if (start_read) begin

				if(wed_request_in_latched.wed.size_send >= CACHELINE_ARRAY_NUM)begin
					wed_request_in_latched.wed.size_send   <= wed_request_in_latched.wed.size_send - CACHELINE_ARRAY_NUM;
					read_command_out_latched.cmd.real_size <= CACHELINE_ARRAY_NUM;

					if (cu_configure_latched[3]) begin
						read_command_out_latched.command <= READ_CL_S;
						read_command_out_latched.size    <= 12'h080;
					end else begin
						read_command_out_latched.size    <= cmd_size_calculate(wed_request_in_latched.wed.size_send);
						read_command_out_latched.command <= READ_CL_NA;
					end

				end else if (wed_request_in_latched.wed.size_send < CACHELINE_ARRAY_NUM) begin
					wed_request_in_latched.wed.size_send   <= 0;
					read_command_out_latched.cmd.real_size <= wed_request_in_latched.wed.size_send;

					if (cu_configure_latched[3]) begin
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

				read_command_out_latched.cmd.abt <= map_CABT(cu_configure_latched[0:2]);
				read_command_out_latched.abt     <= map_CABT(cu_configure_latched[0:2]);



				read_command_out_latched.valid <= 1'b1;

				read_command_out_latched.address <= wed_request_in_latched.wed.array_send + next_offest;

				next_offest <= next_offest + CACHELINE_SIZE;

			end else begin
				read_command_out_latched <= 0;
			end
		end
	end


////////////////////////////////////////////////////////////////////////////
//read prefetch sending logic
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			wed_prefetch_in_latched      <= 0;
			prefetch_command_out_latched <= 0;
			next_prefetch_offest         <= 0;
		end else begin
			if(~wed_prefetch_in_latched.valid && enabled_prefetch)
				wed_prefetch_in_latched <= wed_request_in;

			if (do_prefetch) begin

				if(wed_prefetch_in_latched.wed.size_send >= CACHELINE_ARRAY_NUM)begin
					wed_prefetch_in_latched.wed.size_send      <= wed_prefetch_in_latched.wed.size_send - CACHELINE_ARRAY_NUM;
					prefetch_command_out_latched.cmd.real_size <= CACHELINE_ARRAY_NUM;
				end else if (wed_prefetch_in_latched.wed.size_send < CACHELINE_ARRAY_NUM) begin
					wed_prefetch_in_latched.wed.size_send      <= 0;
					prefetch_command_out_latched.cmd.real_size <= wed_prefetch_in_latched.wed.size_send;
				end

				prefetch_command_out_latched.command <= TOUCH_I;
				prefetch_command_out_latched.size    <= 12'h080;

				prefetch_command_out_latched.cmd.cu_id            <= CU_READ_CONTROL_ID;
				prefetch_command_out_latched.cmd.cmd_type         <= CMD_PREFETCH_READ;
				prefetch_command_out_latched.cmd.cacheline_offest <= 0;
				prefetch_command_out_latched.cmd.address_offest   <= next_prefetch_offest;
				prefetch_command_out_latched.cmd.array_struct     <= PREFETCH_DATA;

				prefetch_command_out_latched.cmd.abt <= STRICT;
				prefetch_command_out_latched.abt     <= STRICT;


				prefetch_command_out_latched.valid <= 1'b1;

				prefetch_command_out_latched.address <= wed_prefetch_in_latched.wed.array_send  + next_prefetch_offest;

				next_prefetch_offest <= next_prefetch_offest + PAGE_SIZE;
			end else begin
				prefetch_command_out_latched <= 0;
			end
		end
	end

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			start_prefetch                <= 1;
			do_prefetch                   <= 1;
			read_job_resp_done_latched    <= 0;
			prefetch_counter_resp_latched <= 0;
			prefetch_counter_send_latched <= 0;
			read_job_send_done_latched    <= 0;
		end else begin

			read_job_send_done_latched    <= read_job_send_done_latched + read_command_out_latched.valid;
			read_job_resp_done_latched	  <= read_job_resp_done_latched + read_response_in_latched.valid;
			prefetch_counter_resp_latched <= prefetch_counter_resp_latched + prefetch_response_in.valid;
			prefetch_counter_send_latched <= prefetch_counter_send_latched + prefetch_command_out_latched.valid;

			if(prefetch_counter_send_latched >= MAX_TLB_CL_REQUESTS) begin
				do_prefetch <= 0;
			end else begin
				do_prefetch <= wed_prefetch_in_latched.valid && ~prefetch_command_buffer_status.alfull && start_prefetch && (|wed_prefetch_in_latched.wed.size_send) && enabled_prefetch;
			end

			if(prefetch_counter_send_latched == prefetch_counter_resp_latched && (|prefetch_counter_resp_latched)) begin
				start_prefetch <= 0;
			end else begin
				start_prefetch <= 1;
			end
		end
	end



endmodule