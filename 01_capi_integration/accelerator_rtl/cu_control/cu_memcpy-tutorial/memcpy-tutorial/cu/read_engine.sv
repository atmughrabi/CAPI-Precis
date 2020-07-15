import GLOBALS_AFU_PKG::*;
import GLOBALS_CU_PKG::*;
import CAPI_PKG::*;
import WED_PKG::*;
import AFU_PKG::*;
import CU_PKG::*;

module read_engine #(parameter CU_READ_CONTROL_ID = DATA_READ_CONTROL_ID) (
	input  logic                         clock                     , // Clock
	input  logic                         rstn                      ,
	input  logic                         read_enabled_in           ,
	input  WEDInterface                  wed_request_in            ,
	input  ResponseBufferLine            read_response_in          ,
	input  ReadWriteDataLine             read_data_0_in            ,
	input  ReadWriteDataLine             read_data_1_in            ,
	input  BufferStatus                  read_command_buffer_status,
	output CommandBufferLine             read_command_out          ,
	output logic [0:(ARRAY_SIZE_BITS-1)] read_job_counter_done
);

	logic              enabled_in                        ;
	WEDInterface       wed_request_in_latched            ;
	ResponseBufferLine read_response_in_latched          ;
	ReadWriteDataLine  read_data_0_in_latched            ;
	ReadWriteDataLine  read_data_1_in_latched            ;
	BufferStatus       read_command_buffer_status_latched;

	CommandBufferLine             read_command_out_latched     ;
	logic [0:(ARRAY_SIZE_BITS-1)] read_job_counter_done_latched;

////////////////////////////////////////////////////////////////////////////
//drive input logic
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			enabled_in <= 0;
		end else begin
			enabled_in <= read_enabled_in;
		end
	end

	// drive input
	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			wed_request_in_latched.valid             <= 0;
			read_response_in_latched.valid           <= 0;
			read_data_0_in_latched.valid             <= 0;
			read_data_1_in_latched.valid             <= 0;
			read_command_buffer_status_latched       <= 0;
			read_command_buffer_status_latched.empty <= 1;
		end else begin
			if(enabled_in) begin
				wed_request_in_latched.valid       <= wed_request_in.valid;
				read_response_in_latched.valid     <= read_response_in.valid;
				read_data_0_in_latched.valid       <= read_data_0_in.valid;
				read_data_1_in_latched.valid       <= read_data_1_in.valid;
				read_command_buffer_status_latched <= read_command_buffer_status;
			end
		end
	end

	// drive input
	always_ff @(posedge clock) begin
		wed_request_in_latched.payload   <= wed_request_in.payload;
		read_response_in_latched.payload <= read_response_in.payload;
		read_data_0_in_latched.payload   <= read_data_0_in.payload;
		read_data_1_in_latched.payload   <= read_data_1_in.payload;
	end


////////////////////////////////////////////////////////////////////////////
//drive out logic
////////////////////////////////////////////////////////////////////////////
	assign read_command_out_latched      = 0;
	assign read_job_counter_done_latched = 0;

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			read_command_out.valid <= 0;
			read_job_counter_done  <= 0;
		end else begin
			read_command_out.valid <= read_command_out_latched.valid;
			read_job_counter_done  <= read_job_counter_done_latched;
		end
	end

	always_ff @(posedge clock) begin
		read_command_out.payload <= read_command_out_latched.payload;
	end

////////////////////////////////////////////////////////////////////////////
//read state machine
////////////////////////////////////////////////////////////////////////////






endmodule 