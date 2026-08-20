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

	BufferStatus                  write_command_buffer_status_latched;
	logic [0:(ARRAY_SIZE_BITS-1)] write_job_counter_done_latched     ;
	CommandTagLine                cmd                                ;
	logic                         enabled_in                         ;

	typedef struct packed {
		CommandBufferLine command;
		ReadWriteDataLine data_0 ;
		ReadWriteDataLine data_1 ;
	} WriteTuple;

	localparam int WRITE_TUPLE_DEPTH      = WRITE_ENGINE_BUFFER_SIZE;
	localparam int WRITE_TUPLE_ADDR_BITS  = $clog2(WRITE_TUPLE_DEPTH);
	localparam int WRITE_TUPLE_COUNT_BITS = $clog2(WRITE_TUPLE_DEPTH + 1);

	WriteTuple write_tuple_queue [0:(WRITE_TUPLE_DEPTH-1)];
	WriteTuple incoming_write_tuple                         ;
	logic [0:(WRITE_TUPLE_ADDR_BITS-1)]  tuple_write_pointer;
	logic [0:(WRITE_TUPLE_ADDR_BITS-1)]  tuple_read_pointer ;
	logic [0:(WRITE_TUPLE_COUNT_BITS-1)] tuple_count        ;
	logic                                  enqueue_write      ;
	logic                                  dequeue_write      ;

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

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			write_command_out.valid <= 0;
			write_data_0_out.valid  <= 0;
			write_data_1_out.valid  <= 0;
			write_job_counter_done  <= 0;
		end else begin
			if(enabled_in) begin
				write_command_out.valid <= dequeue_write;
				write_data_0_out.valid  <= dequeue_write;
				write_data_1_out.valid  <= dequeue_write;
				write_job_counter_done  <= write_job_counter_done_latched;
				if(dequeue_write) begin
					write_command_out.payload <= write_tuple_queue[tuple_read_pointer].command.payload;
					write_data_0_out.payload  <= write_tuple_queue[tuple_read_pointer].data_0.payload;
					write_data_1_out.payload  <= write_tuple_queue[tuple_read_pointer].data_1.payload;
				end
			end
		end
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

	always_comb begin
		incoming_write_tuple = 0;

		incoming_write_tuple.command.valid           = 1;
		incoming_write_tuple.command.payload.command = WRITE_NA;
		incoming_write_tuple.command.payload.size    =
			cmd_size_calculate(read_data_0_in_latched_S2.payload.cmd.real_size);
		incoming_write_tuple.command.payload.abt     = STRICT;
		incoming_write_tuple.command.payload.address =
			wed_request_in_latched.payload.wed.array_receive +
			read_data_0_in_latched_S2.payload.cmd.address_offset;
		incoming_write_tuple.command.payload.cmd     = cmd;

		incoming_write_tuple.data_0.valid        = 1;
		incoming_write_tuple.data_0.payload.cmd  = cmd;
		incoming_write_tuple.data_0.payload.data =
			read_data_0_in_latched_S2.payload.data;

		incoming_write_tuple.data_1.valid        = 1;
		incoming_write_tuple.data_1.payload.cmd  = cmd;
		incoming_write_tuple.data_1.payload.data =
			read_data_1_in_latched.payload.data;
	end

	assign enqueue_write =
		read_data_0_in_latched_S2.valid &&
		read_data_1_in_latched.valid &&
		wed_request_in_latched.valid &&
		enabled_in;
	assign dequeue_write =
		enabled_in &&
		(|tuple_count) &&
		~write_command_buffer_status_latched.alfull;

	always_ff @(posedge clock or negedge rstn) begin
		if(~rstn) begin
			tuple_write_pointer <= 0;
			tuple_read_pointer  <= 0;
			tuple_count         <= 0;
		end else begin
			if(enqueue_write) begin
				write_tuple_queue[tuple_write_pointer] <= incoming_write_tuple;
				tuple_write_pointer <= tuple_write_pointer + 1'b1;
			end
			if(dequeue_write)
				tuple_read_pointer <= tuple_read_pointer + 1'b1;

			case({enqueue_write, dequeue_write})
				2'b10: tuple_count <= tuple_count + 1'b1;
				2'b01: tuple_count <= tuple_count - 1'b1;
				default: tuple_count <= tuple_count;
			endcase
		end
	end


endmodule 