import CAPI::*;

typedef enum {
  AFU_START,
  WAITING_FOR_REQUEST,
  REQUEST_STRIPES,
  WAITING_FOR_STRIPES,
  WRITE_PARITY,
  DONE
} state;

typedef struct {
  longint unsigned size;
  pointer_t stripe1;
  pointer_t stripe2;
  pointer_t parity;
} parity_request;

typedef enum logic [0:7] {
  REQUEST_READ,
  STRIPE1_READ,
  STRIPE2_READ,
  PARITY_WRITE,
  DONE_WRITE
} request_tag;

function logic [0:63] swap_endianness(logic [0:63] in);
  return {in[56:63], in[48:55], in[40:47], in[32:39], in[24:31], in[16:23],
          in[8:15], in[0:7]};
endfunction

module parity_workelement (
  input logic clock,
  input logic enabled,
  input logic reset,
  input pointer_t wed,
  input BufferInterfaceInput buffer_in,
  input ResponseInterface response,
  output CommandInterfaceOutput command_out,
  output BufferInterfaceOutput buffer_out
);

  state current_state;
  parity_request request;
  logic [0:1023] stripe1_data;
  logic [0:1023] stripe2_data;
  logic [0:1023] parity_data;
  logic stripe_received;
  logic [0:511] write_buffer;
  longint unsigned offset;

  shift_register #(512) write_shift (
    .clock(clock),
    .in(write_buffer),
    .out(buffer_out.read_data));

  assign command_out.abt = 0,
         command_out.context_handle = 0,
         buffer_out.read_latency = 1,
         command_out.command_parity = ~^command_out.command,
         command_out.address_parity = ~^command_out.address,
         command_out.tag_parity = ~^command_out.tag,
         buffer_out.read_parity = ~^buffer_out.read_data,
         parity_data = stripe1_data ^ stripe2_data;

  always_ff @ (posedge clock) begin
    if (reset) begin
      current_state <= AFU_START;
    end else if (enabled) begin
      case(current_state)
        AFU_START: begin
          command_out.command <= READ_CL_NA;
          command_out.tag <= REQUEST_READ;
          command_out.size <= 32;
          command_out.address <= wed;
          command_out.valid <= 1;
          current_state = WAITING_FOR_REQUEST;
          offset <= 0;
        end
        WAITING_FOR_REQUEST: begin
          command_out.valid <= 0;
          if (buffer_in.write_valid &&
              buffer_in.write_tag == REQUEST_READ &&
              buffer_in.write_address == 0) begin
            request.size <= swap_endianness(buffer_in.write_data[0:63]);
            request.stripe1 <= swap_endianness(buffer_in.write_data[64:127]);
            request.stripe2 <= swap_endianness(buffer_in.write_data[128:191]);
            request.parity <= swap_endianness(buffer_in.write_data[192:255]);
          end
          if (response.valid && response.tag == REQUEST_READ) begin
            current_state <= REQUEST_STRIPES;
          end
        end
        REQUEST_STRIPES: begin
          command_out.valid <= 1;
          command_out.size = 128;
          command_out.command <= READ_CL_NA;
          if (command_out.tag == REQUEST_READ) begin
            command_out.tag <= STRIPE1_READ;
            command_out.address <= request.stripe1 + offset;
          end else begin
            command_out.tag <= STRIPE2_READ;
            command_out.address <= request.stripe2 + offset;
            current_state <= WAITING_FOR_STRIPES;
          end
        end
        WAITING_FOR_STRIPES: begin
          command_out.valid <= 0;
          if (buffer_in.write_valid) begin
            case(buffer_in.write_tag)
              STRIPE1_READ: begin
                if (buffer_in.write_address == 0) begin
                  stripe1_data[0:511] <= buffer_in.write_data;
                end else begin
                  stripe1_data[512:1023] <= buffer_in.write_data;
                end
              end
              STRIPE2_READ: begin
                if (buffer_in.write_address == 0) begin
                  stripe2_data[0:511] <= buffer_in.write_data;
                end else begin
                  stripe2_data[512:1023] <= buffer_in.write_data;
                end
              end
            endcase
          end
          if (response.valid) begin
            if (response.tag == STRIPE1_READ ||
                response.tag == STRIPE2_READ) begin
              if (stripe_received) begin
                current_state <= WRITE_PARITY;
              end else begin
                stripe_received <= 1;
              end
            end
          end
        end
        WRITE_PARITY: begin
          if (command_out.tag != PARITY_WRITE) begin
            command_out.command <= WRITE_NA;
            command_out.address <= request.parity + offset;
            command_out.tag <= PARITY_WRITE;
            command_out.valid <= 1;
          end else begin
            command_out.valid <= 0;
            // Read half depending on address
            if (buffer_in.read_address == 0)  begin
              write_buffer <= parity_data[0:511];
            end else begin
              write_buffer <= parity_data[512:1023];
            end
            // Handle response
            if (response.valid &&
                response.tag == PARITY_WRITE) begin
                if (offset + 128 < request.size) begin
                  offset <= offset + 128;
                  current_state <= REQUEST_STRIPES;
                end else begin
                  current_state <= DONE;
                end
            end
          end
        end
        DONE: begin
          if (command_out.tag != DONE_WRITE) begin
            command_out.tag <= DONE_WRITE;
            command_out.size <= 1;
            command_out.address <= wed + 32;
            command_out.valid <= 1;
            write_buffer[256:263] <= 1;
          end else begin
            command_out.valid <= 0;
          end
        end
      endcase
    end
  end

endmodule
