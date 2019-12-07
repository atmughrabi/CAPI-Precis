// -----------------------------------------------------------------------------
//
//		"ACCEL-GRAPH Shared Memory Accelerator Project"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi atmughrabi@gmail.com/atmughra@ncsu.edu
// File   : cu_data_write_engine_control.sv
// Create : 2019-11-18 16:55:32
// Revise : 2019-12-06 22:25:38
// Editor : sublime text3, tab size (4)
// -----------------------------------------------------------------------------

import GLOBALS_AFU_PKG::*;
import CAPI_PKG::*;
import WED_PKG::*;
import AFU_PKG::*;
import CU_PKG::*;
import CREDIT_PKG::*;

module cu_data_write_engine_control #(parameter CU_WRITE_CONTROL_ID = DATA_WRITE_CONTROL_ID) (
	input  logic                         clock                      , // Clock
	input  logic                         rstn                       ,
	input  logic                         enabled_in                 ,
	input  WEDInterface                  wed_request_in             ,
	input  ResponseBufferLine            write_response_in          ,
	input  ReadWriteDataLine             write_data_0_in            ,
	input  ReadWriteDataLine             write_data_1_in            ,
	input  BufferStatus                  write_command_buffer_status,
	output BufferStatus                  write_data_in_buffer_status,
	output CommandBufferLine             write_command_out          ,
	output ReadWriteDataLine             write_data_0_out           ,
	output ReadWriteDataLine             write_data_1_out           ,
	output logic [0:(ARRAY_SIZE_BITS-1)] write_job_counter_done
);


	BufferStatus write_data_in_0_buffer_status;
	BufferStatus write_data_in_1_buffer_status;

	logic             enabled                  ;
	ReadWriteDataLine write_data_0_out_latched ;
	ReadWriteDataLine write_data_1_out_latched ;
	CommandBufferLine write_command_out_latched;
	WEDInterface      wed_request_in_latched   ;
	ReadWriteDataLine write_data_0_out_buffer  ;
	ReadWriteDataLine write_data_1_out_buffer  ;
	logic             write_data_buffer_pop    ;
	CommandTagLine    cmd                      ;

	assign write_data_in_buffer_status = write_data_in_0_buffer_status;

////////////////////////////////////////////////////////////////////////////
//drive outputs
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			write_data_0_out  <= 0;
			write_data_1_out  <= 0;
			write_command_out <= 0;
		end else begin
			if(enabled) begin
				write_data_0_out  <= write_data_0_out_latched;
				write_data_1_out  <= write_data_1_out_latched;
				write_command_out <= write_command_out_latched;
			end
		end
	end

////////////////////////////////////////////////////////////////////////////
//drive inputs
////////////////////////////////////////////////////////////////////////////


	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			wed_request_in_latched <= 0;
		end else begin
			if(enabled) begin
				wed_request_in_latched <= wed_request_in;
			end
		end
	end

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


////////////////////////////////////////////////////////////////////////////
//response tracking logic
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn)
			write_job_counter_done <= 0;
		else begin
			if (write_response_in.valid) begin
				write_job_counter_done <= write_job_counter_done + write_response_in.cmd.real_size;
			end
		end
	end

////////////////////////////////////////////////////////////////////////////
//edge_data_send
////////////////////////////////////////////////////////////////////////////

	always_comb begin
		cmd                  = 0;
		cmd.array_struct     = WRITE_DATA;
		cmd.cacheline_offest = write_data_0_out_buffer.cmd.cacheline_offest;
		cmd.address_offest   = write_data_0_out_buffer.cmd.address_offest;
		cmd.real_size        = write_data_0_out_buffer.cmd.real_size;
		cmd.cu_id            = CU_WRITE_CONTROL_ID;
		cmd.cmd_type         = CMD_WRITE;
		cmd.abt              = STRICT;
	end


	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			write_command_out_latched <= 0;
			write_data_0_out_latched  <= 0;
			write_data_1_out_latched  <= 0;
		end else begin
			if (write_data_0_out_buffer.valid && write_data_1_out_buffer.valid && enabled) begin
				write_command_out_latched.valid <= write_data_0_out_buffer.valid;

				write_command_out_latched.address <= wed_request_in_latched.wed.array_receive + write_data_0_out_buffer.cmd.address_offest;
				write_command_out_latched.size    <= cmd_size_calculate(write_data_0_out_buffer.cmd.real_size);
				write_command_out_latched.cmd     <= cmd;


				write_data_0_out_latched.valid <= write_data_0_out_buffer.valid;
				write_data_0_out_latched.cmd   <= cmd;
				write_data_0_out_latched.data  <= write_data_0_out_buffer.data ;

				write_data_1_out_latched.valid <= write_data_1_out_buffer.valid;
				write_data_1_out_latched.cmd   <= cmd;
				write_data_1_out_latched.data  <= write_data_1_out_buffer.data ;

				write_data_1_out_latched.cmd.abt  <= map_CABT(wed_request_in_latched.wed.afu_config[5:7]);
				write_data_0_out_latched.cmd.abt  <= map_CABT(wed_request_in_latched.wed.afu_config[5:7]);
				write_command_out_latched.cmd.abt <= map_CABT(wed_request_in_latched.wed.afu_config[5:7]);
				write_command_out_latched.abt     <= map_CABT(wed_request_in_latched.wed.afu_config[5:7]);

				if (wed_request_in_latched.wed.afu_config[9]) begin
					write_command_out_latched.command <= WRITE_MS;
				end else begin
					write_command_out_latched.command <= WRITE_NA;
				end

			end else begin
				write_command_out_latched <= 0;
				write_data_0_out_latched  <= 0;
				write_data_1_out_latched  <= 0;
			end
		end
	end


////////////////////////////////////////////////////////////////////////////
//Buffers CU Write DATA
////////////////////////////////////////////////////////////////////////////

	assign write_data_buffer_pop = ~write_command_buffer_status.alfull && ~write_data_in_1_buffer_status.empty && ~write_data_in_0_buffer_status.empty;

	fifo #(
		.WIDTH   ($bits(ReadWriteDataLine)    ),
		.DEPTH   (WRITE_ENGINE_BUFFER_SIZE    ),
		.HEADROOM(WRITE_ENGINE_BUFFER_HEADROOM)
	) cu_write_data_0_buffer_fifo_instant (
		.clock   (clock                               ),
		.rstn    (rstn                                ),
		
		.push    (write_data_0_in.valid               ),
		.data_in (write_data_0_in                     ),
		.full    (write_data_in_0_buffer_status.full  ),
		.alFull  (write_data_in_0_buffer_status.alfull),
		
		.pop     (write_data_buffer_pop               ),
		.valid   (write_data_in_0_buffer_status.valid ),
		.data_out(write_data_0_out_buffer             ),
		.empty   (write_data_in_0_buffer_status.empty )
	);


	fifo #(
		.WIDTH   ($bits(ReadWriteDataLine)    ),
		.DEPTH   (WRITE_ENGINE_BUFFER_SIZE    ),
		.HEADROOM(WRITE_ENGINE_BUFFER_HEADROOM)
	) cu_write_data_1_buffer_fifo_instant (
		.clock   (clock                               ),
		.rstn    (rstn                                ),
		
		.push    (write_data_1_in.valid               ),
		.data_in (write_data_1_in                     ),
		.full    (write_data_in_1_buffer_status.full  ),
		.alFull  (write_data_in_1_buffer_status.alfull),
		
		.pop     (write_data_buffer_pop               ),
		.valid   (write_data_in_1_buffer_status.valid ),
		.data_out(write_data_1_out_buffer             ),
		.empty   (write_data_in_1_buffer_status.empty )
	);


endmodule