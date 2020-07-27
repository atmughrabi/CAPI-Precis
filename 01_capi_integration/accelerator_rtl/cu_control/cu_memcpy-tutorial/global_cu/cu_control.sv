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
import GLOBALS_CU_PKG::*;
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


	ResponseBufferLine            read_response_in_latched      ;
	ReadWriteDataLine             read_data_0_in_latched        ;
	ReadWriteDataLine             read_data_1_in_latched        ;
	CommandBufferLine             read_command_out_latched      ;
	logic [0:(ARRAY_SIZE_BITS-1)] read_job_counter_done_internal;
	logic                         cu_done_internal              ;


	ResponseBufferLine            write_response_in_latched      ;
	ReadWriteDataLine             write_data_0_out_latched       ;
	ReadWriteDataLine             write_data_1_out_latched       ;
	CommandBufferLine             write_command_out_latched      ;
	logic [0:(ARRAY_SIZE_BITS-1)] write_job_counter_done_internal;

	WEDInterface wed_request_in_latched;


	logic read_engine_enable ;
	logic write_engine_enable;

	logic cu_done_read ;
	logic cu_done_write;

	// assign read_command_out           = 0;
	assign prefetch_read_command_out  = 0;
	assign prefetch_write_command_out = 0;
	// assign write_command_out          = 0;
	// assign write_data_0_out           = 0;
	// assign write_data_1_out           = 0;

// write_job_counter_done_internal
	assign cu_done_read  = (read_job_counter_done_internal == wed_request_in.payload.wed.size_recive) && read_engine_enable;
	assign cu_done_write = (write_job_counter_done_internal == wed_request_in.payload.wed.size_send) && write_engine_enable;
	assign cu_done_internal = cu_done_read && cu_done_write;
////////////////////////////////////////////////////////////////////////////
//enable logic
////////////////////////////////////////////////////////////////////////////

	// drive outputs
	always_ff @(posedge clock or negedge rstn_in) begin
		if(~rstn_in) begin
			cu_return.var1 <= 0;  //CU_RETURN
			cu_return.var2 <= 0;  //CU_RETURN_2
			cu_done        <= 0;
		end else begin
			if(enabled_in)begin
				cu_return.var1 <= read_job_counter_done_internal; // running/final value
				cu_return.var2 <= write_job_counter_done_internal; // running value
				cu_done        <= cu_done_internal; // var1 => cxl_mmio_read64((*afu), CU_RETURN_DONE, (uint64_t *) & (afu_status->cu_return_done));
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
			cu_status           <= 0;
			read_engine_enable  <= 0;
			write_engine_enable <= 0;
		end else begin
			if(enabled_in)begin
				cu_status           <= (cu_configure_1_latched);
				read_engine_enable  <= (|cu_configure_1_latched) && wed_request_in_latched.valid ;
				write_engine_enable <= (|cu_configure_1_latched) && wed_request_in_latched.valid ;
			end
		end
	end

////////////////////////////////////////////////////////////////////////////
//drive input logic
////////////////////////////////////////////////////////////////////////////


	// drive input
	always_ff @(posedge clock or negedge rstn_in) begin
		if(~rstn_in) begin
			wed_request_in_latched.valid    <= 0; //CU_RETURN
			read_response_in_latched.valid  <= 0;
			write_response_in_latched.valid <= 0;
			read_data_0_in_latched.valid    <= 0;
			read_data_1_in_latched.valid    <= 0;
		end else begin
			if(enabled_in) begin
				wed_request_in_latched.valid    <= wed_request_in.valid;
				read_response_in_latched.valid  <= read_response_in.valid;
				write_response_in_latched.valid <= write_response_in.valid;
				read_data_0_in_latched.valid    <= read_data_0_in.valid;
				read_data_1_in_latched.valid    <= read_data_1_in.valid;
			end
		end
	end

	// drive input
	always_ff @(posedge clock) begin
		wed_request_in_latched.payload    <= wed_request_in.payload;
		read_response_in_latched.payload  <= read_response_in.payload;
		write_response_in_latched.payload <= write_response_in.payload;
		read_data_0_in_latched.payload    <= read_data_0_in.payload;
		read_data_1_in_latched.payload    <= read_data_1_in.payload;
	end


////////////////////////////////////////////////////////////////////////////
//drive out logic
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn_in) begin
		if(~rstn_in) begin
			read_command_out.valid  <= 0;
			write_command_out.valid <= 0;
			write_data_0_out.valid  <= 0;
			write_data_1_out.valid  <= 0;
		end else begin
			if(enabled_in) begin
				read_command_out.valid  <= read_command_out_latched.valid;
				write_command_out.valid <= write_command_out_latched.valid;
				write_data_0_out.valid  <= write_data_0_out_latched.valid;
				write_data_1_out.valid  <= write_data_1_out_latched.valid;
			end
		end
	end

	always_ff @(posedge clock) begin
		read_command_out.payload  <= read_command_out_latched.payload;
		write_command_out.payload <= write_command_out_latched.payload;
		write_data_0_out.payload  <= write_data_0_out_latched.payload;
		write_data_1_out.payload  <= write_data_1_out_latched.payload;
	end

////////////////////////////////////////////////////////////////////////////
//read engine
////////////////////////////////////////////////////////////////////////////

	read_engine #(.CU_READ_CONTROL_ID(DATA_READ_CONTROL_ID)) read_engine_instant (
		.clock                      (clock                         ),
		.rstn                       (rstn_in                       ),
		.read_enabled_in            (read_engine_enable            ),
		.wed_request_in             (wed_request_in_latched        ),
		.read_response_in           (read_response_in_latched      ),
		.read_command_buffer_status (read_buffer_status            ),
		.write_command_buffer_status(write_buffer_status           ),
		.read_command_out           (read_command_out_latched      ),
		.read_job_counter_done      (read_job_counter_done_internal)
	);


////////////////////////////////////////////////////////////////////////////
//write engine
////////////////////////////////////////////////////////////////////////////

	write_engine #(.CU_WRITE_CONTROL_ID(DATA_WRITE_CONTROL_ID)) write_engine_instant (
		.clock                      (clock                          ),
		.rstn                       (rstn_in                        ),
		.write_enabled_in           (write_engine_enable            ),
		.wed_request_in             (wed_request_in                 ),
		.write_response_in          (write_response_in_latched      ),
		.read_data_0_in             (read_data_0_in_latched         ),
		.read_data_1_in             (read_data_1_in_latched         ),
		.write_data_0_out           (write_data_0_out_latched       ),
		.write_data_1_out           (write_data_1_out_latched       ),
		.write_command_buffer_status(write_buffer_status            ),
		.write_command_out          (write_command_out_latched      ),
		.write_job_counter_done     (write_job_counter_done_internal)
	);



endmodule