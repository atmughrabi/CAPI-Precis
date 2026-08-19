import GLOBALS_AFU_PKG::*;
import GLOBALS_CU_PKG::*;
import CAPI_PKG::*;
import WED_PKG::*;
import AFU_PKG::*;
import CU_PKG::*;

module cu_matrix_multiply_control #(
    parameter int ENGINE_X = 0,
    parameter int ENGINE_Y = 0,
    parameter int X_STRIDE = 1,
    parameter int Y_STRIDE = 1,
    parameter logic [0:7] CU_ID_X = MATRIX_A_B_CONTROL_ID,
    parameter logic [0:7] CU_ID_Y = MATRIX_A_B_CONTROL_ID
) (
    input  logic              clock                ,
    input  logic              rstn                 ,
    input  logic              enabled_in           ,
    input  WEDInterface       wed_request_in       ,
    input  logic [0:63]       cu_configure_2       ,
    input  logic [0:63]       cu_configure_3       ,
    input  logic [0:63]       cu_configure_4       ,
    input  ResponseBufferLine read_response_in     ,
    input  ReadWriteDataLine  read_data_0_in       ,
    input  ReadWriteDataLine  read_data_1_in       ,
    input  BufferStatus       read_buffer_status   ,
    input  logic              read_command_grant   ,
    input  ResponseBufferLine write_response_in    ,
    input  BufferStatus       write_buffer_status  ,
    input  logic              write_command_grant  ,
    output CommandBufferLine  read_command_out     ,
    output CommandBufferLine  write_command_out    ,
    output ReadWriteDataLine  write_data_0_out     ,
    output ReadWriteDataLine  write_data_1_out     ,
    output logic              done_out             ,
    output logic [0:63]       completed_writes_out ,
    output logic [0:63]       multiply_terms_out
);

    typedef enum logic [0:3] {
        MATRIX_IDLE,
        MATRIX_C_COMMAND,
        MATRIX_C_WAIT,
        MATRIX_A_COMMAND,
        MATRIX_A_WAIT,
        MATRIX_B_COMMAND,
        MATRIX_B_WAIT,
        MATRIX_WRITE_COMMAND,
        MATRIX_WRITE_WAIT,
        MATRIX_DONE
    } matrix_state;

    matrix_state state;

    logic [0:63] matrix_n;
    logic [0:63] tile_size;
    logic [0:63] matrix_a_address;
    logic [0:63] matrix_b_address;
    logic [0:63] matrix_c_address;
    logic [0:63] i_start;
    logic [0:63] j_start;
    logic [0:63] k_start;
    logic [0:63] i_end;
    logic [0:63] j_end;
    logic [0:63] k_end;
    logic [0:63] current_i;
    logic [0:63] current_j;
    logic [0:63] current_k;
    logic [0:31] accumulator;
    logic [0:31] matrix_a_value;
    logic [0:31] read_value;
    logic        read_data_seen;
    logic        read_response_seen;

    logic                  incoming_data_valid;
    logic [0:31]           incoming_data;
    logic                  incoming_response_valid;
    array_struct_type      expected_read_type;
    logic [0:63]           current_scalar_address;
    logic [0:7]            incoming_word_offset;

    function automatic logic [0:63] clipped_end(
        input logic [0:63] start_index,
        input logic [0:63] extent,
        input logic [0:63] limit
    );
        logic [0:63] candidate;
        candidate = start_index + extent;
        return (candidate < limit) ? candidate : limit;
    endfunction

    function automatic logic [0:63] element_address(
        input logic [0:63] base,
        input logic [0:63] row,
        input logic [0:63] column,
        input logic [0:63] width
    );
        return base + (((row * width) + column) << $clog2(DATA_SIZE_READ));
    endfunction

    function automatic CommandBufferLine make_read_command(
        input logic [0:63] address,
        input array_struct_type array_type
    );
        CommandBufferLine line;
        line = 0;
        line.valid = 1;
        line.payload.command = READ_CL_NA;
        line.payload.address = address & ADDRESS_DATA_READ_ALIGN_MASK;
        line.payload.size = CACHELINE_SIZE;
        line.payload.abt = STRICT;
        line.payload.cmd.cu_id_x = CU_ID_X;
        line.payload.cmd.cu_id_y = CU_ID_Y;
        line.payload.cmd.array_struct = array_type;
        line.payload.cmd.cmd_type = CMD_READ;
        line.payload.cmd.real_size = 1;
        line.payload.cmd.real_size_bytes = DATA_SIZE_READ;
        line.payload.cmd.cacheline_offset =
            (address & ADDRESS_DATA_READ_MOD_MASK) >> $clog2(DATA_SIZE_READ);
        line.payload.cmd.address_offset = address;
        line.payload.cmd.size = CACHELINE_SIZE;
        line.payload.cmd.abt = STRICT;
        return line;
    endfunction

    function automatic CommandBufferLine make_write_command(
        input logic [0:63] address
    );
        CommandBufferLine line;
        line = 0;
        line.valid = 1;
        line.payload.command = WRITE_NA;
        line.payload.address = address;
        line.payload.size = DATA_SIZE_WRITE;
        line.payload.abt = STRICT;
        line.payload.cmd.cu_id_x = CU_ID_X;
        line.payload.cmd.cu_id_y = CU_ID_Y;
        line.payload.cmd.array_struct = MATRIX_C_DATA_WRITE;
        line.payload.cmd.cmd_type = CMD_WRITE;
        line.payload.cmd.real_size = 1;
        line.payload.cmd.real_size_bytes = DATA_SIZE_WRITE;
        line.payload.cmd.cacheline_offset =
            (address & ADDRESS_DATA_WRITE_MOD_MASK) >> $clog2(DATA_SIZE_WRITE);
        line.payload.cmd.address_offset = address;
        line.payload.cmd.size = DATA_SIZE_WRITE;
        line.payload.cmd.abt = STRICT;
        return line;
    endfunction

    function automatic ReadWriteDataLine make_write_data(
        input logic [0:63] address,
        input logic [0:31] value,
        input logic upper_half
    );
        ReadWriteDataLine line;
        logic [0:7] word_offset;
        logic [0:4] half_offset;

        line = 0;
        line.valid = 1;
        line.payload.cmd = make_write_command(address).payload.cmd;
        word_offset =
            (address & ADDRESS_DATA_WRITE_MOD_MASK) >> $clog2(DATA_SIZE_WRITE);
        half_offset = word_offset[3:7];
        if(upper_half == word_offset[3])
            line.payload.data[half_offset * DATA_SIZE_WRITE_BITS +: DATA_SIZE_WRITE_BITS] =
                swap_endianness_data_write(value);
        return line;
    endfunction

    always_comb begin
        expected_read_type = STRUCT_INVALID;
        current_scalar_address = 0;
        case(state)
            MATRIX_C_WAIT: begin
                expected_read_type = MATRIX_C_DATA_READ;
                current_scalar_address =
                    element_address(matrix_c_address, current_i, current_j, matrix_n);
            end
            MATRIX_A_WAIT: begin
                expected_read_type = MATRIX_A_DATA_READ;
                current_scalar_address =
                    element_address(matrix_a_address, current_i, current_k, matrix_n);
            end
            MATRIX_B_WAIT: begin
                expected_read_type = MATRIX_B_DATA_READ;
                current_scalar_address =
                    element_address(matrix_b_address, current_j, current_k, matrix_n);
            end
            default: begin
                expected_read_type = STRUCT_INVALID;
                current_scalar_address = 0;
            end
        endcase

        incoming_word_offset =
            (current_scalar_address & ADDRESS_DATA_READ_MOD_MASK) >>
            $clog2(DATA_SIZE_READ);
        incoming_data_valid = 0;
        incoming_data = 0;
        if(
            read_data_0_in.valid &&
            read_data_0_in.payload.cmd.cu_id_x == CU_ID_X &&
            read_data_0_in.payload.cmd.cu_id_y == CU_ID_Y &&
            read_data_0_in.payload.cmd.array_struct == expected_read_type &&
            ~incoming_word_offset[3]
        ) begin
            incoming_data_valid = 1;
            incoming_data = swap_endianness_data_read(
                read_data_0_in.payload.data[
                    incoming_word_offset[3:7] * DATA_SIZE_READ_BITS +:
                    DATA_SIZE_READ_BITS
                ]
            );
        end else if(
            read_data_1_in.valid &&
            read_data_1_in.payload.cmd.cu_id_x == CU_ID_X &&
            read_data_1_in.payload.cmd.cu_id_y == CU_ID_Y &&
            read_data_1_in.payload.cmd.array_struct == expected_read_type &&
            incoming_word_offset[3]
        ) begin
            incoming_data_valid = 1;
            incoming_data = swap_endianness_data_read(
                read_data_1_in.payload.data[
                    incoming_word_offset[3:7] * DATA_SIZE_READ_BITS +:
                    DATA_SIZE_READ_BITS
                ]
            );
        end

        incoming_response_valid =
            read_response_in.valid &&
            read_response_in.payload.cmd.cu_id_x == CU_ID_X &&
            read_response_in.payload.cmd.cu_id_y == CU_ID_Y &&
            read_response_in.payload.response == DONE &&
            read_response_in.payload.cmd.array_struct == expected_read_type;
    end

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            state <= MATRIX_IDLE;
            matrix_n <= 0;
            tile_size <= 0;
            matrix_a_address <= 0;
            matrix_b_address <= 0;
            matrix_c_address <= 0;
            i_start <= 0;
            j_start <= 0;
            k_start <= 0;
            i_end <= 0;
            j_end <= 0;
            k_end <= 0;
            current_i <= 0;
            current_j <= 0;
            current_k <= 0;
            accumulator <= 0;
            matrix_a_value <= 0;
            read_value <= 0;
            read_data_seen <= 0;
            read_response_seen <= 0;
            read_command_out <= 0;
            write_command_out <= 0;
            write_data_0_out <= 0;
            write_data_1_out <= 0;
            done_out <= 0;
            completed_writes_out <= 0;
            multiply_terms_out <= 0;
        end else begin
            read_command_out.valid <= 0;
            write_command_out.valid <= 0;
            write_data_0_out.valid <= 0;
            write_data_1_out.valid <= 0;

            case(state)
                MATRIX_IDLE: begin
                    done_out <= 0;
                    completed_writes_out <= 0;
                    multiply_terms_out <= 0;
                    if(
                        enabled_in &&
                        wed_request_in.valid &&
                        cu_configure_2[63] &&
                        cu_configure_3[63] &&
                        cu_configure_4[63]
                    ) begin
                        matrix_n <= wed_request_in.payload.wed.size_n;
                        tile_size <= wed_request_in.payload.wed.size_tile;
                        matrix_a_address <= wed_request_in.payload.wed.Matrix_A;
                        matrix_b_address <= wed_request_in.payload.wed.Matrix_B;
                        matrix_c_address <= wed_request_in.payload.wed.Matrix_C;
                        i_start <= cu_configure_2[0:62] + ENGINE_X;
                        j_start <= cu_configure_3[0:62] + ENGINE_Y;
                        k_start <= cu_configure_4[0:62];
                        i_end <= clipped_end(
                            cu_configure_2[0:62],
                            wed_request_in.payload.wed.size_tile,
                            wed_request_in.payload.wed.size_n
                        );
                        j_end <= clipped_end(
                            cu_configure_3[0:62],
                            wed_request_in.payload.wed.size_tile,
                            wed_request_in.payload.wed.size_n
                        );
                        k_end <= clipped_end(
                            cu_configure_4[0:62],
                            wed_request_in.payload.wed.size_tile,
                            wed_request_in.payload.wed.size_n
                        );
                        current_i <= cu_configure_2[0:62] + ENGINE_X;
                        current_j <= cu_configure_3[0:62] + ENGINE_Y;
                        current_k <= cu_configure_4[0:62];
                        if(
                            ~(|wed_request_in.payload.wed.size_n) ||
                            ~(|wed_request_in.payload.wed.size_tile) ||
                            cu_configure_2[0:62] + ENGINE_X >=
                                clipped_end(
                                    cu_configure_2[0:62],
                                    wed_request_in.payload.wed.size_tile,
                                    wed_request_in.payload.wed.size_n
                                ) ||
                            cu_configure_3[0:62] + ENGINE_Y >=
                                clipped_end(
                                    cu_configure_3[0:62],
                                    wed_request_in.payload.wed.size_tile,
                                    wed_request_in.payload.wed.size_n
                                ) ||
                            cu_configure_4[0:62] >= wed_request_in.payload.wed.size_n
                        )
                            state <= MATRIX_DONE;
                        else
                            state <= MATRIX_C_COMMAND;
                    end
                end

                MATRIX_C_COMMAND: begin
                    if(read_command_grant) begin
                        read_data_seen <= 0;
                        read_response_seen <= 0;
                        state <= MATRIX_C_WAIT;
                    end else if(~read_buffer_status.alfull) begin
                        read_command_out <= make_read_command(
                            element_address(matrix_c_address, current_i, current_j, matrix_n),
                            MATRIX_C_DATA_READ
                        );
                    end
                end

                MATRIX_C_WAIT: begin
                    if(incoming_data_valid) begin
                        read_value <= incoming_data;
                        read_data_seen <= 1;
                    end
                    if(incoming_response_valid)
                        read_response_seen <= 1;
                    if(
                        (read_data_seen || incoming_data_valid) &&
                        (read_response_seen || incoming_response_valid)
                    ) begin
                        accumulator <= incoming_data_valid ? incoming_data : read_value;
                        current_k <= k_start;
                        state <= MATRIX_A_COMMAND;
                    end
                end

                MATRIX_A_COMMAND: begin
                    if(read_command_grant) begin
                        read_data_seen <= 0;
                        read_response_seen <= 0;
                        state <= MATRIX_A_WAIT;
                    end else if(~read_buffer_status.alfull) begin
                        read_command_out <= make_read_command(
                            element_address(matrix_a_address, current_i, current_k, matrix_n),
                            MATRIX_A_DATA_READ
                        );
                    end
                end

                MATRIX_A_WAIT: begin
                    if(incoming_data_valid) begin
                        read_value <= incoming_data;
                        read_data_seen <= 1;
                    end
                    if(incoming_response_valid)
                        read_response_seen <= 1;
                    if(
                        (read_data_seen || incoming_data_valid) &&
                        (read_response_seen || incoming_response_valid)
                    ) begin
                        matrix_a_value <= incoming_data_valid ? incoming_data : read_value;
                        state <= MATRIX_B_COMMAND;
                    end
                end

                MATRIX_B_COMMAND: begin
                    if(read_command_grant) begin
                        read_data_seen <= 0;
                        read_response_seen <= 0;
                        state <= MATRIX_B_WAIT;
                    end else if(~read_buffer_status.alfull) begin
                        read_command_out <= make_read_command(
                            element_address(matrix_b_address, current_j, current_k, matrix_n),
                            MATRIX_B_DATA_READ
                        );
                    end
                end

                MATRIX_B_WAIT: begin
                    if(incoming_data_valid) begin
                        read_value <= incoming_data;
                        read_data_seen <= 1;
                    end
                    if(incoming_response_valid)
                        read_response_seen <= 1;
                    if(
                        (read_data_seen || incoming_data_valid) &&
                        (read_response_seen || incoming_response_valid)
                    ) begin
                        accumulator <= accumulator +
                            (matrix_a_value *
                             (incoming_data_valid ? incoming_data : read_value));
                        multiply_terms_out <= multiply_terms_out + 1;
                        if(current_k + 1 < k_end) begin
                            current_k <= current_k + 1;
                            state <= MATRIX_A_COMMAND;
                        end else begin
                            state <= MATRIX_WRITE_COMMAND;
                        end
                    end
                end

                MATRIX_WRITE_COMMAND: begin
                    if(write_command_grant) begin
                        state <= MATRIX_WRITE_WAIT;
                    end else if(~write_buffer_status.alfull) begin
                        write_command_out <= make_write_command(
                            element_address(matrix_c_address, current_i, current_j, matrix_n)
                        );
                        write_data_0_out <= make_write_data(
                            element_address(matrix_c_address, current_i, current_j, matrix_n),
                            accumulator,
                            0
                        );
                        write_data_1_out <= make_write_data(
                            element_address(matrix_c_address, current_i, current_j, matrix_n),
                            accumulator,
                            1
                        );
                    end
                end

                MATRIX_WRITE_WAIT: begin
                    if(
                        write_response_in.valid &&
                        write_response_in.payload.cmd.cu_id_x == CU_ID_X &&
                        write_response_in.payload.cmd.cu_id_y == CU_ID_Y &&
                        write_response_in.payload.response == DONE &&
                        write_response_in.payload.cmd.array_struct ==
                            MATRIX_C_DATA_WRITE
                    ) begin
                        completed_writes_out <= completed_writes_out + 1;
                        if(current_j + Y_STRIDE < j_end) begin
                            current_j <= current_j + Y_STRIDE;
                            current_k <= k_start;
                            state <= MATRIX_C_COMMAND;
                        end else if(current_i + X_STRIDE < i_end) begin
                            current_i <= current_i + X_STRIDE;
                            current_j <= j_start;
                            current_k <= k_start;
                            state <= MATRIX_C_COMMAND;
                        end else begin
                            state <= MATRIX_DONE;
                        end
                    end
                end

                MATRIX_DONE: begin
                    done_out <= 1;
                end

                default: begin
                    state <= MATRIX_IDLE;
                end
            endcase
        end
    end

endmodule
