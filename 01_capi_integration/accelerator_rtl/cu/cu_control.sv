// -----------------------------------------------------------------------------
//
//		"ACCEL-GRAPH Shared Memory Accelerator Project"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi atmughrabi@gmail.com/atmughra@ncsu.edu
// File   : cu_control.sv
// Create : 2019-09-26 15:18:39
// Revise : 2019-12-06 10:30:13
// Editor : sublime text3, tab size (4)
// -----------------------------------------------------------------------------

import GLOBALS_AFU_PKG::*;
import CAPI_PKG::*;
import WED_PKG::*;
import AFU_PKG::*;
import CU_PKG::*;


module cu_control #(parameter NUM_REQUESTS = 2) (
	input  logic              clock                 , // Clock
	input  logic              rstn                  ,
	input  logic              enabled_in            ,
	input  WEDInterface       wed_request_in        ,
	input  ResponseBufferLine read_response_in      ,
	input  ResponseBufferLine prefetch_response_in  ,
	input  ResponseBufferLine write_response_in     ,
	input  ReadWriteDataLine  read_data_0_in        ,
	input  ReadWriteDataLine  read_data_1_in        ,
	input  BufferStatus       read_buffer_status    ,
	input  BufferStatus       prefetch_buffer_status,
	input  BufferStatus       write_buffer_status   ,
	input  logic [0:63]       algorithm_requests    ,
	output logic [0:63]       algorithm_status      ,
	output logic              algorithm_done        ,
	output logic [0:63]       algorithm_running     ,
	output CommandBufferLine  read_command_out      ,
	output CommandBufferLine  prefetch_command_out  ,
	output CommandBufferLine  write_command_out     ,
	output ReadWriteDataLine  write_data_0_out      ,
	output ReadWriteDataLine  write_data_1_out
);

	// vertex control variables

	//output latched
	CommandBufferLine write_command_out_latched;
	ReadWriteDataLine write_data_0_out_latched ;
	ReadWriteDataLine write_data_1_out_latched ;
	CommandBufferLine read_command_out_latched ;

	//input lateched
	WEDInterface       wed_request_in_latched  ;
	ResponseBufferLine read_response_in_latched;

	ResponseBufferLine write_response_in_latched  ;
	ReadWriteDataLine  read_data_0_in_latched     ;
	ReadWriteDataLine  read_data_1_in_latched     ;
	ReadWriteDataLine  read_data_0_out            ;
	ReadWriteDataLine  read_data_1_out            ;
	ReadWriteDataLine  write_data_0_in            ;
	ReadWriteDataLine  write_data_1_in            ;
	BufferStatus       write_data_in_buffer_status;

	logic [                 0:63] algorithm_status_latched  ;
	logic [                 0:63] algorithm_requests_latched;
	logic                         done_algorithm            ;
	logic [0:(ARRAY_SIZE_BITS-1)] write_job_counter_done    ;
	logic [0:(ARRAY_SIZE_BITS-1)] read_job_counter_done     ;

	logic enabled         ;
	logic enabled_instants;
	logic cu_ready        ;


	assign prefetch_command_out = 0;
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
			enabled_instants <= 0;
		end else begin
			enabled_instants <= enabled && cu_ready;
		end
	end

////////////////////////////////////////////////////////////////////////////
//Done signal
////////////////////////////////////////////////////////////////////////////a

	assign done_algorithm = wed_request_in_latched.valid && (wed_request_in_latched.wed.size_send == read_job_counter_done) && (wed_request_in_latched.wed.size_recive == write_job_counter_done);

	assign cu_ready = (|algorithm_requests_latched);

	always_comb begin
		algorithm_status_latched = 0;
		if(wed_request_in_latched.valid)begin
			algorithm_status_latched = {write_job_counter_done,read_job_counter_done};
		end
	end

////////////////////////////////////////////////////////////////////////////
//Drive output
////////////////////////////////////////////////////////////////////////////


	// drive outputs
	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			write_command_out <= 0;
			write_data_0_out  <= 0;
			write_data_1_out  <= 0;
			read_command_out  <= 0;
			algorithm_status  <= 0;
			algorithm_running <= 0;
			algorithm_done    <= 0;
		end else begin
			if(enabled)begin
				write_command_out <= write_command_out_latched;
				write_data_0_out  <= write_data_0_out_latched;
				write_data_1_out  <= write_data_1_out_latched;
				read_command_out  <= read_command_out_latched;
				algorithm_status  <= algorithm_status_latched;
				algorithm_done    <= done_algorithm;
				algorithm_running <= cu_ready;
			end
		end
	end

////////////////////////////////////////////////////////////////////////////
//Drive input
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			wed_request_in_latched     <= 0;
			read_response_in_latched   <= 0;
			write_response_in_latched  <= 0;
			read_data_0_in_latched     <= 0;
			read_data_1_in_latched     <= 0;
			algorithm_requests_latched <= 0;

		end else begin
			if(enabled)begin
				wed_request_in_latched    <= wed_request_in;
				read_response_in_latched  <= read_response_in;
				write_response_in_latched <= write_response_in;
				read_data_0_in_latched    <= read_data_0_in;
				read_data_1_in_latched    <= read_data_1_in;

				if((|algorithm_requests))
					algorithm_requests_latched <= algorithm_requests;
			end
		end
	end


////////////////////////////////////////////////////////////////////////////
//READ Engine
////////////////////////////////////////////////////////////////////////////

	cu_data_read_engine_control cu_data_read_engine_control_instant (
		.clock                      (clock                      ),
		.rstn                       (rstn                       ),
		.enabled_in                 (enabled_instants           ),
		.wed_request_in             (wed_request_in_latched     ),
		.read_response_in           (read_response_in_latched   ),
		.read_data_0_in             (read_data_0_in_latched     ),
		.read_data_1_in             (read_data_1_in_latched     ),
		.read_command_buffer_status (read_buffer_status         ),
		.read_data_out_buffer_status(write_data_in_buffer_status),
		.read_command_out           (read_command_out_latched   ),
		.read_data_0_out            (read_data_0_out            ),
		.read_data_1_out            (read_data_1_out            ),
		.read_job_counter_done      (read_job_counter_done      )
	);

////////////////////////////////////////////////////////////////////////////
//WRITE Engine
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock) begin
		write_data_0_in <= read_data_0_out;
	end

	assign write_data_1_in = read_data_1_out;

	cu_data_write_engine_control cu_data_write_engine_control_instant (
		.clock                      (clock                      ),
		.rstn                       (rstn                       ),
		.enabled_in                 (enabled_instants           ),
		.wed_request_in             (wed_request_in_latched     ),
		.write_response_in          (write_response_in_latched  ),
		.write_data_0_in            (write_data_0_in            ),
		.write_data_1_in            (write_data_1_in            ),
		.write_command_buffer_status(write_buffer_status        ),
		.write_data_in_buffer_status(write_data_in_buffer_status),
		.write_command_out          (write_command_out_latched  ),
		.write_data_0_out           (write_data_0_out_latched   ),
		.write_data_1_out           (write_data_1_out_latched   ),
		.write_job_counter_done     (write_job_counter_done     )
	);


endmodule