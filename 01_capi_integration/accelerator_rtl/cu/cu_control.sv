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
// Revise : 2019-12-07 05:32:41
// Editor : sublime text3, tab size (4)
// -----------------------------------------------------------------------------

import GLOBALS_AFU_PKG::*;
import CAPI_PKG::*;
import WED_PKG::*;
import AFU_PKG::*;
import CU_PKG::*;


module cu_control #(parameter NUM_REQUESTS = 2) (
	input  logic              clock                       , // Clock
	input  logic              rstn                        ,
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
	input  logic [0:63]       algorithm_requests          ,
	output logic [0:63]       algorithm_status            ,
	output logic              algorithm_done              ,
	output logic [0:63]       algorithm_running           ,
	output CommandBufferLine  read_command_out            ,
	output CommandBufferLine  prefetch_read_command_out   ,
	output CommandBufferLine  prefetch_write_command_out  ,
	output CommandBufferLine  write_command_out           ,
	output ReadWriteDataLine  write_data_0_out            ,
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

	logic enabled               ;
	logic enabled_instants      ;
	logic enabled_prefetch_read ;
	logic enabled_prefetch_write;
	logic cu_ready              ;


	logic [                  0:8] prefetch_read_pulse              ;
	logic [                 0:63] base_address_read                ;
	logic [                 0:63] total_size_read                  ;
	logic                         total_size_read_valid            ;
	logic [                 0:63] offset_size_read                 ;
	command_type                  cu_command_type_read             ;
	afu_command_t                 transaction_type_read            ;
	trans_order_behavior_t        commmand_abt_read                ;
	ResponseBufferLine            prefetch_read_response_in_latched;
	CommandBufferLine             prefetch_read_command_out_latched;
	logic [0:(ARRAY_SIZE_BITS-1)] prefetch_read_job_counter_done   ;

	logic [                  0:8] prefetch_write_pulse              ;
	logic [                 0:63] base_address_write                ;
	logic [                 0:63] total_size_write                  ;
	logic                         total_size_write_valid            ;
	logic [                 0:63] offset_size_write                 ;
	command_type                  cu_command_type_write             ;
	afu_command_t                 transaction_type_write            ;
	trans_order_behavior_t        commmand_abt_write                ;
	ResponseBufferLine            prefetch_write_response_in_latched;
	CommandBufferLine             prefetch_write_command_out_latched;
	logic [0:(ARRAY_SIZE_BITS-1)] prefetch_write_job_counter_done   ;

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

////////////////////////////////////////////////////////////////////////////
//Prefetch Stream READ Engine
////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////
//Drive input
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			base_address_read                 <= 0;
			total_size_read                   <= 0;
			total_size_read_valid             <= 0;
			offset_size_read                  <= 0;
			cu_command_type_read              <= CMD_PREFETCH_READ;
			transaction_type_read             <= TOUCH_I;
			commmand_abt_read                 <= STRICT;
			prefetch_read_response_in_latched <= 0;

		end else begin
			if(enabled)begin
				base_address_read     <= wed_request_in_latched.wed.array_send;
				total_size_read       <= wed_request_in_latched.wed.size_send;
				total_size_read_valid <= wed_request_in_latched.valid;
				offset_size_read      <= PAGE_SIZE;
				cu_command_type_read  <= CMD_PREFETCH_READ;

				if (wed_request_in_latched.wed.afu_config[3])
					transaction_type_read <= TOUCH_S;
				else
					transaction_type_read <= TOUCH_I;

				commmand_abt_read                 <= STRICT;
				prefetch_read_response_in_latched <= prefetch_read_response_in;
			end
		end
	end

////////////////////////////////////////////////////////////////////////////
//Drive output
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			prefetch_read_command_out <= 0;
		end else begin
			if(enabled)begin
				prefetch_read_command_out <= prefetch_read_command_out_latched;
			end
		end
	end

////////////////////////////////////////////////////////////////////////////
//Drive output
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			prefetch_read_pulse <= 9'h0FF;
		end else begin
			if(enabled)begin
				prefetch_read_pulse <= prefetch_read_pulse + read_command_out_latched.valid;
			end
		end
	end

	assign enabled_prefetch_read = ~(|prefetch_read_pulse);

	cu_prefetch_stream_engine_control #(.CU_PREFETCH_CONTROL_ID(PREFETCH_READ_CONTROL_ID)) cu_prefetch_read_stream_engine_control_instant (
		.clock                         (clock                            ),
		.rstn                          (rstn                             ),
		.enabled_in                    (enabled_prefetch_read            ),
		.base_address                  (base_address_read                ),
		.total_size                    (total_size_read                  ),
		.total_size_valid              (total_size_read_valid            ),
		.offset_size                   (offset_size_read                 ),
		.cu_command_type               (cu_command_type_read             ),
		.transaction_type              (transaction_type_read            ),
		.commmand_abt                  (commmand_abt_read                ),
		.prefetch_response_in          (prefetch_read_response_in_latched),
		.prefetch_command_buffer_status(prefetch_read_buffer_status      ),
		.prefetch_command_out          (prefetch_read_command_out_latched),
		.prefetch_job_counter_done     (prefetch_read_job_counter_done   )
	);


////////////////////////////////////////////////////////////////////////////
//Prefetch Stream WRITE Engine
////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////
//Drive input
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			base_address_write                 <= 0;
			total_size_write                   <= 0;
			total_size_write_valid             <= 0;
			offset_size_write                  <= 0;
			cu_command_type_write              <= CMD_PREFETCH_WRITE;
			transaction_type_write             <= TOUCH_I;
			commmand_abt_write                 <= STRICT;
			prefetch_write_response_in_latched <= 0;

		end else begin
			if(enabled)begin
				base_address_write     <= wed_request_in_latched.wed.array_receive;
				total_size_write       <= wed_request_in_latched.wed.size_recive;
				total_size_write_valid <= wed_request_in_latched.valid;
				offset_size_write      <= PAGE_SIZE;
				cu_command_type_write  <= CMD_PREFETCH_WRITE;

				if (wed_request_in_latched.wed.afu_config[9])
					transaction_type_write <= TOUCH_I;
				else
					transaction_type_write <= TOUCH_I;

				commmand_abt_write                 <= STRICT;
				prefetch_write_response_in_latched <= prefetch_write_response_in;
			end
		end
	end

////////////////////////////////////////////////////////////////////////////
//Drive output
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			prefetch_write_command_out <= 0;
		end else begin
			if(enabled)begin
				prefetch_write_command_out <= prefetch_write_command_out_latched;
			end
		end
	end

////////////////////////////////////////////////////////////////////////////
//Drive output
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			prefetch_write_pulse <= 9'h0FF;
		end else begin
			if(enabled)begin
				prefetch_write_pulse <= prefetch_write_pulse + write_command_out_latched.valid;
			end
		end
	end

	assign enabled_prefetch_write = ~(|prefetch_write_pulse);

	cu_prefetch_stream_engine_control #(.CU_PREFETCH_CONTROL_ID(PREFETCH_READ_CONTROL_ID)) cu_prefetch_write_stream_engine_control_instant (
		.clock                         (clock                             ),
		.rstn                          (rstn                              ),
		.enabled_in                    (enabled_prefetch_write            ),
		.base_address                  (base_address_write                ),
		.total_size                    (total_size_write                  ),
		.total_size_valid              (total_size_write_valid            ),
		.offset_size                   (offset_size_write                 ),
		.cu_command_type               (cu_command_type_write             ),
		.transaction_type              (transaction_type_write            ),
		.commmand_abt                  (commmand_abt_write                ),
		.prefetch_response_in          (prefetch_write_response_in_latched),
		.prefetch_command_buffer_status(prefetch_write_buffer_status      ),
		.prefetch_command_out          (prefetch_write_command_out_latched),
		.prefetch_job_counter_done     (prefetch_write_job_counter_done   )
	);

endmodule