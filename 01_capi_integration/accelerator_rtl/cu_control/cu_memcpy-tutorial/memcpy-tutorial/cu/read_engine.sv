import GLOBALS_AFU_PKG::*;
import GLOBALS_CU_PKG::*;
import CAPI_PKG::*;
import WED_PKG::*;
import AFU_PKG::*;
import CU_PKG::*;

module read_engine #(parameter CU_READ_CONTROL_ID = DATA_READ_CONTROL_ID) (
	input  logic                         clock                      , // Clock
	input  logic                         rstn                       ,
	input  logic                         read_enabled_in            ,
	input  WEDInterface                  wed_request_in             ,
	input  ResponseBufferLine            read_response_in           ,
	input  BufferStatus                  read_command_buffer_status ,
	input  BufferStatus                  write_command_buffer_status,
	output CommandBufferLine             read_command_out           ,
	output logic [0:(ARRAY_SIZE_BITS-1)] read_job_counter_done
);

	logic              enabled_in                         ;
	WEDInterface       wed_request_in_latched             ;
	WEDInterface       wed_request_in_driver              ;
	ResponseBufferLine read_response_in_latched           ;
	BufferStatus       read_command_buffer_status_latched ;
	BufferStatus       write_command_buffer_status_latched;

	CommandBufferLine             read_command_out_latched     ;
	logic [0:(ARRAY_SIZE_BITS-1)] read_job_counter_done_latched;


	logic        cmd_setup    ;
	logic        send_cmd_read;
	logic [0:63] next_offset  ;

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
			wed_request_in_latched.valid              <= 0;
			read_response_in_latched.valid            <= 0;
			read_command_buffer_status_latched        <= 0;
			read_command_buffer_status_latched.empty  <= 1;
			write_command_buffer_status_latched       <= 0;
			write_command_buffer_status_latched.empty <= 1;
		end else begin
			if(enabled_in) begin
				wed_request_in_latched.valid        <= wed_request_in.valid;
				read_response_in_latched.valid      <= read_response_in.valid;
				read_command_buffer_status_latched  <= read_command_buffer_status;
				write_command_buffer_status_latched <= write_command_buffer_status;
			end
		end
	end

	// drive input
	always_ff @(posedge clock) begin
		wed_request_in_latched.payload   <= wed_request_in.payload;
		read_response_in_latched.payload <= read_response_in.payload;
	end


////////////////////////////////////////////////////////////////////////////
//drive out logic
////////////////////////////////////////////////////////////////////////////
	// assign read_command_out_latched      = 0;
	// assign read_job_counter_done_latched = 0;

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			read_command_out.valid <= 0;
			read_job_counter_done  <= 0;
		end else begin
			if(enabled_in) begin
				read_command_out.valid <= read_command_out_latched.valid;
				read_job_counter_done  <= read_job_counter_done_latched;
			end
		end
	end

	always_ff @(posedge clock) begin
		read_command_out.payload <= read_command_out_latched.payload;
	end

////////////////////////////////////////////////////////////////////////////
//read state machine
////////////////////////////////////////////////////////////////////////////

	read_state current_state, next_state;

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn)
			current_state <= READ_STREAM_RESET;
		else begin
			if(enabled_in)
				current_state <= next_state;
		end
	end// always_ff @(posedge clock)

	always_comb begin
		next_state = current_state;
		case (current_state)
			READ_STREAM_RESET : begin
				next_state = READ_STREAM_IDLE;
			end
			READ_STREAM_IDLE : begin
				if(wed_request_in_latched.valid && enabled_in)
					next_state = READ_STREAM_SET;
				else
					next_state = READ_STREAM_IDLE;
			end
			READ_STREAM_SET : begin
				next_state = READ_STREAM_START;
			end
			READ_STREAM_START : begin
				next_state = READ_STREAM_REQ;
			end
			READ_STREAM_REQ : begin
				if(|wed_request_in_driver.payload.wed.size_send)
					next_state = READ_STREAM_REQ;
				else
					next_state = READ_STREAM_FINAL;
			end
			READ_STREAM_FINAL : begin
				next_state = READ_STREAM_FINAL;
			end
		endcase
	end

	always_ff @(posedge clock) begin
		case (current_state)
			READ_STREAM_RESET : begin
				cmd_setup     <= 0;
				send_cmd_read <= 0;
			end
			READ_STREAM_IDLE : begin
				cmd_setup <= 0;
			end
			READ_STREAM_SET : begin
				cmd_setup <= 1;
			end
			READ_STREAM_START : begin
				cmd_setup     <= 0;
				send_cmd_read <= 1;
			end
			READ_STREAM_REQ : begin

			end
			READ_STREAM_FINAL : begin
				send_cmd_read <= 0;
			end
		endcase
	end

////////////////////////////////////////////////////////////////////////////
//response tracking logic
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn)
			read_job_counter_done_latched <= 0;
		else begin
			if (read_response_in_latched.valid) begin
				read_job_counter_done_latched <= read_job_counter_done_latched + read_response_in_latched.payload.cmd.real_size;
			end
		end
	end

////////////////////////////////////////////////////////////////////////////
//read command driver
////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			read_command_out_latched <= 0;
			next_offset              <= 0;
			wed_request_in_driver    <= 0;
		end else begin

			if(cmd_setup)
				wed_request_in_driver <= wed_request_in_latched;

			if (~read_command_buffer_status_latched.alfull && ~write_command_buffer_status_latched.alfull && (|wed_request_in_driver.payload.wed.size_send) && send_cmd_read)begin

				if(wed_request_in_driver.payload.wed.size_send > CACHELINE_ARRAY_NUM)begin
					wed_request_in_driver.payload.wed.size_send          <= wed_request_in_driver.payload.wed.size_send - CACHELINE_ARRAY_NUM;
					read_command_out_latched.payload.cmd.real_size       <= CACHELINE_ARRAY_NUM;
					read_command_out_latched.payload.cmd.real_size_bytes <= 12'h080;

					read_command_out_latched.payload.size    <= 12'h080;
					read_command_out_latched.payload.command <= READ_CL_NA;
				end else if (wed_request_in_driver.payload.wed.size_send <= CACHELINE_ARRAY_NUM) begin
					wed_request_in_driver.payload.wed.size_send          <= 0;
					read_command_out_latched.payload.cmd.real_size       <= wed_request_in_driver.payload.wed.size_send;
					read_command_out_latched.payload.cmd.real_size_bytes <= cmd_size_calculate(wed_request_in_driver.payload.wed.size_send);

					read_command_out_latched.payload.size    <= cmd_size_calculate(wed_request_in_driver.payload.wed.size_send);
					read_command_out_latched.payload.command <= READ_PNA;
				end

				read_command_out_latched.payload.cmd.cu_id_x          <= CU_READ_CONTROL_ID;
				read_command_out_latched.payload.cmd.cu_id_y          <= CU_READ_CONTROL_ID;
				read_command_out_latched.payload.cmd.cmd_type         <= CMD_READ;
				read_command_out_latched.payload.cmd.cacheline_offset <= 0;
				read_command_out_latched.payload.cmd.address_offset   <= next_offset;
				read_command_out_latched.payload.cmd.array_struct     <= READ_DATA;
				read_command_out_latched.payload.cmd.abt              <= STRICT;

				read_command_out_latched.valid           <= 1'b1;
				read_command_out_latched.payload.abt     <= STRICT; // cmd order
				read_command_out_latched.payload.address <= wed_request_in_driver.payload.wed.array_send + next_offset;
				next_offset                              <= next_offset + CACHELINE_SIZE;

			end else begin
				read_command_out_latched <= 0;
			end
		end
	end


endmodule 