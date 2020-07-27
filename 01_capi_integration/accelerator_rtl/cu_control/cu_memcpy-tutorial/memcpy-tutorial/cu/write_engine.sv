import GLOBALS_AFU_PKG::*;
import GLOBALS_CU_PKG::*;
import CAPI_PKG::*;
import WED_PKG::*;
import AFU_PKG::*;
import CU_PKG::*;

module write_engine #(parameter CU_WRITE_CONTROL_ID = DATA_WRITE_CONTROL_ID) (
	input  logic                         clock                      , // Clock
	input  logic                         rstn                       ,
	input  logic                         write_enabled_in           ,
	input  WEDInterface                  wed_request_in             ,
	input  ResponseBufferLine            write_response_in          ,
	input  ReadWriteDataLine             read_data_0_in             ,
	input  ReadWriteDataLine             read_data_1_in             ,
	output ReadWriteDataLine             write_data_0_out           ,
	output ReadWriteDataLine             write_data_1_out           ,
	input  BufferStatus                  write_command_buffer_status,
	output CommandBufferLine             write_command_out          ,
	output logic [0:(ARRAY_SIZE_BITS-1)] write_job_counter_done
);


	WEDInterface       wed_request_in_latched   ;
	ResponseBufferLine write_response_in_latched;
	ReadWriteDataLine  read_data_0_in_latched   ;
	ReadWriteDataLine  read_data_0_in_latched_S2;
	ReadWriteDataLine  read_data_1_in_latched   ;

	ReadWriteDataLine             write_data_0_out_latched           ;
	ReadWriteDataLine             write_data_1_out_latched           ;
	BufferStatus                  write_command_buffer_status_latched;
	CommandBufferLine             write_command_out_latched          ;
	logic [0:(ARRAY_SIZE_BITS-1)] write_job_counter_done_latched     ;
	CommandTagLine                cmd                                ;
	logic                         enabled_in                         ;

	// assign write_data_0_out_latched  = 0;
	// assign write_data_1_out_latched  = 0;
	// assign write_command_out_latched = 0;
	////////////////////////////////////////////////////////////////////////////
	//drive input logic
	////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			enabled_in <= 0;
		end else begin
			enabled_in <= write_enabled_in;
		end
	end

	// drive input
	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			wed_request_in_latched.valid              <= 0;
			write_response_in_latched.valid           <= 0;
			read_data_0_in_latched.valid              <= 0;
			read_data_0_in_latched_S2.valid           <= 0;
			read_data_1_in_latched.valid              <= 0;
			write_command_buffer_status_latched       <= 0;
			write_command_buffer_status_latched.empty <= 1;
		end else begin
			if(enabled_in) begin
				wed_request_in_latched.valid        <= wed_request_in.valid;
				write_response_in_latched.valid     <= write_response_in.valid;
				read_data_0_in_latched.valid        <= read_data_0_in.valid;
				read_data_0_in_latched_S2.valid     <= read_data_0_in_latched.valid;
				read_data_1_in_latched.valid        <= read_data_1_in.valid ;
				write_command_buffer_status_latched <= write_command_buffer_status;
			end
		end
	end

	// drive input
	always_ff @(posedge clock) begin
		wed_request_in_latched.payload    <= wed_request_in.payload;
		write_response_in_latched.payload <= write_response_in.payload;
		read_data_0_in_latched.payload    <= read_data_0_in.payload;
		read_data_0_in_latched_S2.payload <= read_data_0_in_latched.payload;
		read_data_1_in_latched.payload    <= read_data_1_in.payload ;
	end


	////////////////////////////////////////////////////////////////////////////
	//drive out logic
	////////////////////////////////////////////////////////////////////////////
	// assign write_command_out_latched      = 0;
	// assign write_job_counter_done_latched = 0;

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			write_command_out.valid <= 0;
			write_data_0_out.valid  <= 0;
			write_data_1_out.valid  <= 0;
			write_job_counter_done  <= 0;
		end else begin
			if(enabled_in) begin
				write_command_out.valid <= write_command_out_latched.valid;
				write_data_0_out.valid  <= write_data_0_out_latched.valid;
				write_data_1_out.valid  <= write_data_1_out_latched.valid ;
				write_job_counter_done  <= write_job_counter_done_latched;
			end
		end
	end

	always_ff @(posedge clock) begin
		write_command_out.payload <= write_command_out_latched.payload;
		write_data_0_out.payload  <= write_data_0_out_latched.payload;
		write_data_1_out.payload  <= write_data_1_out_latched.payload ;
	end

	////////////////////////////////////////////////////////////////////////////
	//response tracking logic
	////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn)
			write_job_counter_done_latched <= 0;
		else begin
			if (write_response_in_latched.valid) begin
				write_job_counter_done_latched <= write_job_counter_done_latched + write_response_in_latched.payload.cmd.real_size;
			end
		end
	end

	////////////////////////////////////////////////////////////////////////////
	//write state machine
	////////////////////////////////////////////////////////////////////////////
	// read_data_0_in_latched_S2
	// 	read_data_1_in_latched

	// write_command_out_latched
	// write_data_0_out_latched
	// write_data_1_out_latched

	always_comb begin
		cmd                  = 0;
		cmd.array_struct     = WRITE_DATA;
		cmd.cacheline_offset = read_data_0_in_latched_S2.payload.cmd.cacheline_offset;
		cmd.address_offset   = read_data_0_in_latched_S2.payload.cmd.address_offset;
		cmd.real_size        = read_data_0_in_latched_S2.payload.cmd.real_size;
		cmd.real_size_bytes  = read_data_0_in_latched_S2.payload.cmd.real_size_bytes;
		cmd.cu_id_x          = CU_WRITE_CONTROL_ID;
		cmd.cu_id_y          = CU_WRITE_CONTROL_ID;
		cmd.cmd_type         = CMD_WRITE;
		cmd.abt              = STRICT;
	end


	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			write_data_0_out_latched.valid  <= 0;
			write_data_1_out_latched.valid  <= 0;
			write_command_out_latched.valid <= 0;
		end else begin
			if(read_data_0_in_latched_S2.valid && wed_request_in_latched.valid && enabled_in) begin
				write_data_0_out_latched.valid  <= 1;
				write_data_1_out_latched.valid  <= 1;
				write_command_out_latched.valid <= 1;
			end else begin
				write_data_0_out_latched.valid  <= 0;
				write_data_1_out_latched.valid  <= 0;
				write_command_out_latched.valid <= 0;
			end
		end
	end


	always_ff @(posedge clock) begin
		write_command_out_latched.payload.command <= WRITE_NA;
		write_command_out_latched.payload.size    <= cmd_size_calculate(read_data_0_in_latched_S2.payload.cmd.real_size);
		write_command_out_latched.payload.abt     <= STRICT;
		write_command_out_latched.payload.address <= wed_request_in_latched.payload.wed.array_receive + read_data_0_in_latched_S2.payload.cmd.address_offset;

		write_command_out_latched.payload.cmd <= cmd;

		write_data_0_out_latched.payload.cmd <= cmd;
		write_data_1_out_latched.payload.cmd <= cmd;

		write_data_0_out_latched.payload.data <= read_data_0_in_latched_S2.payload.data;
		write_data_1_out_latched.payload.data <= read_data_1_in_latched.payload.data;
	end


endmodule 