// -----------------------------------------------------------------------------
//
//      "ACCEL-GRAPH Shared Memory Accelerator Project"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi atmughrabi@gmail.com/atmughra@ncsu.edu
// File   : cu_matrix_C_job_control.sv
// Create : 2019-09-26 15:19:30
// Revise : 2019-11-08 10:50:37
// Editor : sublime text3, tab size (4)
// -----------------------------------------------------------------------------

import GLOBALS_AFU_PKG::*;
import GLOBALS_CU_PKG::*;
import CAPI_PKG::*;
import WED_PKG::*;
import AFU_PKG::*;
import CU_PKG::*;

module cu_matrix_C_job_control (
    input  logic              clock                   , // Clock
    input  logic              rstn                    ,
    input  logic              enabled_in              ,
    input  logic [0:63]       cu_configure_2          ,
    input  logic [0:63]       cu_configure_3          ,
    input  WEDInterface       wed_request_in          ,
    input  ResponseBufferLine read_response_in        ,
    input  ReadWriteDataLine  read_data_0_in          ,
    input  ReadWriteDataLine  read_data_1_in          ,
    input  BufferStatus       read_buffer_status      ,
    input  logic              matrix_C_request        ,
    input  logic              read_command_bus_grant  ,
    output logic              read_command_bus_request,
    output CommandBufferLine  read_command_out        ,
    output MatrixCInterface   matrix_C_job_out
);


    logic read_command_bus_grant_latched  ;
    logic read_command_bus_request_latched;
    // logic        read_command_bus_grant_latched_S2  ;
    // logic        read_command_bus_request_latched_S2;
    BufferStatus matrix_C_buffer_status    ;
    BufferStatus read_buffer_status_latched;

    logic [0:CACHELINE_INT_COUNTER_BITS] shift_limit_0           ;
    logic [0:CACHELINE_INT_COUNTER_BITS] shift_limit_1           ;
    logic                                shift_limit_clear       ;
    logic [0:CACHELINE_INT_COUNTER_BITS] shift_counter           ;
    logic                                start_shift_hf_0        ;
    logic                                start_shift_hf_1        ;
    logic                                switch_shift_hf         ;
    logic                                push_shift              ;
    logic [0:(CACHELINE_SIZE_BITS_HF-1)] reg_MATRIX_C_DATA_READ_0;
    logic [0:(CACHELINE_SIZE_BITS_HF-1)] reg_MATRIX_C_DATA_READ_1;

    logic clear_data_ready        ;
    logic fill_matrix_C_job_buffer;
    logic zero_pass               ;

    //output latched
    MatrixCInterface  matrix_C_latched        ;
    CommandBufferLine read_command_out_latched;
    // CommandBufferLine read_command_out_latched_S2;

    //input lateched
    WEDInterface       wed_request_in_latched  ;
    ResponseBufferLine read_response_in_latched;
    ReadWriteDataLine  read_data_0_in_latched  ;
    ReadWriteDataLine  read_data_1_in_latched  ;

    logic matrix_C_request_latched;

    CommandBufferLine read_command_matrix_C_job_latched   ;
    CommandBufferLine read_command_matrix_C_job_latched_S2;
    BufferStatus      read_buffer_status_internal         ;

    BufferStatus     matrix_C_buffer_burst_status;
    logic            matrix_C_buffer_burst_pop   ;
    MatrixCInterface matrix_C_burst_variable     ;

    // internal registers to track logic
    // Read/write commands require the size to be a power of 2 (1, 2, 4, 8, 16, 32,64, 128).
    logic                             send_request_ready          ;
    logic [                     0:63] matrix_C_next_offset        ;
    logic [    0:(ARRAY_SIZE_BITS-1)] matrix_C_num_counter_jj_dec ;
    logic [    0:(ARRAY_SIZE_BITS-1)] matrix_C_num_counter_ii_dec ;
    logic [    0:(ARRAY_SIZE_BITS-1)] matrix_C_num_counter_jj_inc ;
    logic [    0:(ARRAY_SIZE_BITS-1)] matrix_C_num_counter_ii_inc ;
    logic [    0:(ARRAY_SIZE_BITS-1)] matrix_C_id_counter         ;
    logic                             generate_read_command       ;
    logic                             setup_read_command          ;
    MatrixCInterface                  matrix_C_variable           ;
    logic [0:(DATA_SIZE_READ_BITS-1)] matrix_C_data               ;
    logic                             matrix_C_data_ready         ;
    logic                             read_command_bus_request_pop;


    matrix_C_struct_state current_state, next_state;
    logic                 enabled      ;
    logic                 enabled_cmd  ;

    logic [0:63] cu_configure_2_latched;
    logic [0:63] cu_configure_3_latched;

    logic [0:(ARRAY_SIZE_BITS-1)] ii_reg_start;
    logic [0:(ARRAY_SIZE_BITS-1)] jj_reg_start;

    logic [0:(ARRAY_SIZE_BITS-1)] ii_reg_end;
    logic [0:(ARRAY_SIZE_BITS-1)] jj_reg_end;

    logic [0:(ARRAY_SIZE_BITS-1)] ii_reg_limit;
    logic [0:(ARRAY_SIZE_BITS-1)] jj_reg_limit;

////////////////////////////////////////////////////////////////////////////
//enable logic
////////////////////////////////////////////////////////////////////////////

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            enabled     <= 0;
            enabled_cmd <= 0;
        end else begin
            enabled     <= enabled_in;
            enabled_cmd <= enabled && (cu_configure_2_latched[63]) && (cu_configure_3_latched[63]);
        end
    end

////////////////////////////////////////////////////////////////////////////
//drive outputs
////////////////////////////////////////////////////////////////////////////

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            matrix_C_job_out.valid <= 0;
            read_command_out.valid <= 0;
        end else begin
            if(enabled) begin
                matrix_C_job_out.valid <= matrix_C_latched.valid;
                read_command_out.valid <= read_command_out_latched.valid;
                // read_command_out.valid            <= read_command_out_latched_S2.valid;
            end
        end
    end

    always_ff @(posedge clock) begin
        matrix_C_job_out.payload <= matrix_C_latched.payload;
        read_command_out.payload <= read_command_out_latched.payload;
        // read_command_out.payload            <= read_command_out_latched_S2.payload;
    end

////////////////////////////////////////////////////////////////////////////
//drive inputs
////////////////////////////////////////////////////////////////////////////
    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            wed_request_in_latched.valid     <= 0;
            read_response_in_latched.valid   <= 0;
            read_data_0_in_latched.valid     <= 0;
            read_data_1_in_latched.valid     <= 0;
            matrix_C_request_latched         <= 0;
            read_buffer_status_latched       <= 0;
            read_buffer_status_latched.empty <= 1;

            cu_configure_2_latched <= 0;
            cu_configure_3_latched <= 0;
        end else begin
            if(enabled) begin
                read_buffer_status_latched     <= read_buffer_status;
                wed_request_in_latched.valid   <= wed_request_in.valid ;
                read_response_in_latched.valid <= read_response_in.valid ;
                read_data_0_in_latched.valid   <= read_data_0_in.valid ;
                read_data_1_in_latched.valid   <= read_data_1_in.valid ;
                matrix_C_request_latched       <= matrix_C_request;

                if((cu_configure_2[63]))
                    cu_configure_2_latched <= cu_configure_2;
                if((|cu_configure_3[63]))
                    cu_configure_3_latched <= cu_configure_3;

            end
        end
    end

    always_ff @(posedge clock) begin
        wed_request_in_latched.payload   <= wed_request_in.payload;
        read_response_in_latched.payload <= read_response_in.payload;
        read_data_0_in_latched.payload   <= read_data_0_in.payload;
        read_data_1_in_latched.payload   <= read_data_1_in.payload;
    end

    // assign ii_reg_limit = (cu_configure_2_latched[0:62]) + wed_request_in_latched.payload.wed.size_tile;
    // assign jj_reg_limit = (cu_configure_3_latched[0:62]) + wed_request_in_latched.payload.wed.size_tile;

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            ii_reg_limit <= 0;
            jj_reg_limit <= 0;
        end else begin
            ii_reg_limit <= (cu_configure_2_latched[0:62]) + wed_request_in_latched.payload.wed.size_tile;
            jj_reg_limit <= (cu_configure_3_latched[0:62]) + wed_request_in_latched.payload.wed.size_tile;
        end
    end

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            ii_reg_start <= 0;
            jj_reg_start <= 0;
            ii_reg_end   <= 0;
            jj_reg_end   <= 0;
        end else begin
            ii_reg_start <= (cu_configure_2_latched[0:62]);
            jj_reg_start <= (cu_configure_3_latched[0:62]);
            ii_reg_end   <= (ii_reg_limit  < wed_request_in_latched.payload.wed.size_n) ? ii_reg_limit : wed_request_in_latched.payload.wed.size_n;
            jj_reg_end   <= (jj_reg_limit  < wed_request_in_latched.payload.wed.size_n) ? jj_reg_limit : wed_request_in_latched.payload.wed.size_n;
        end
    end

////////////////////////////////////////////////////////////////////////////
//1. Generate Read Commands to obtain matrix_C structural info
////////////////////////////////////////////////////////////////////////////
    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn)
            current_state <= SEND_MATRIX_C_RESET;
        else begin
            if(enabled) begin
                current_state <= next_state;
            end
        end
    end // always_ff @(posedge clock)

    always_comb begin
        next_state = current_state;
        case (current_state)
            SEND_MATRIX_C_RESET : begin
                if(wed_request_in_latched.valid && enabled_cmd)
                    next_state = SEND_MATRIX_C_INIT;
                else
                    next_state = SEND_MATRIX_C_RESET;
            end
            SEND_MATRIX_C_INIT : begin
                next_state = SEND_MATRIX_C_IDLE;
            end
            SEND_MATRIX_C_IDLE : begin
                if(send_request_ready)
                    next_state = START_MATRIX_C_REQ;
                else
                    next_state = SEND_MATRIX_C_IDLE;
            end
            START_MATRIX_C_REQ : begin
                next_state = CALC_MATRIX_C_REQ_SIZE;
            end
            CALC_MATRIX_C_REQ_SIZE : begin
                next_state = SEND_MATRIX_C_START;
            end
            SEND_MATRIX_C_START : begin
                next_state = SEND_MATRIX_C_DATA_READ;
            end
            SEND_MATRIX_C_DATA_READ : begin
                next_state = WAIT_MATRIX_C_DATA;
            end
            WAIT_MATRIX_C_DATA : begin
                if(fill_matrix_C_job_buffer)
                    next_state = SHIFT_MATRIX_C_DATA_START;
                else
                    next_state = WAIT_MATRIX_C_DATA;
            end
            SHIFT_MATRIX_C_DATA_START : begin
                next_state = SHIFT_MATRIX_C_DATA_0;
            end
            SHIFT_MATRIX_C_DATA_0 : begin
                if((shift_counter < shift_limit_0))
                    next_state = SHIFT_MATRIX_C_DATA_0;
                else
                    next_state = SHIFT_MATRIX_C_DATA_DONE_0;
            end
            SHIFT_MATRIX_C_DATA_DONE_0 : begin
                if(|shift_limit_1 || zero_pass)
                    next_state = SHIFT_MATRIX_C_DATA_1;
                else
                    next_state = SHIFT_MATRIX_C_DATA_DONE_1;
            end
            SHIFT_MATRIX_C_DATA_1 : begin
                if((shift_counter < shift_limit_1))
                    next_state = SHIFT_MATRIX_C_DATA_1;
                else
                    next_state = SHIFT_MATRIX_C_DATA_DONE_1;
            end
            SHIFT_MATRIX_C_DATA_DONE_1 : begin
                next_state = SEND_MATRIX_C_IDLE;
            end
        endcase
    end // always_comb

    always_ff @(posedge clock) begin
        case (current_state)
            SEND_MATRIX_C_RESET : begin
                read_command_matrix_C_job_latched.valid <= 0;
                generate_read_command                   <= 0;
                setup_read_command                      <= 0;
                clear_data_ready                        <= 1;
                shift_limit_clear                       <= 1;
                start_shift_hf_0                        <= 0;
                start_shift_hf_1                        <= 0;
                switch_shift_hf                         <= 0;
                shift_counter                           <= 0;
            end
            SEND_MATRIX_C_INIT : begin
                read_command_matrix_C_job_latched.valid <= 0;
                clear_data_ready                        <= 0;
                shift_limit_clear                       <= 0;
                setup_read_command                      <= 1;
            end
            SEND_MATRIX_C_IDLE : begin
                read_command_matrix_C_job_latched.valid <= 0;
                setup_read_command                      <= 0;
                shift_limit_clear                       <= 0;
                shift_counter                           <= 0;
            end
            START_MATRIX_C_REQ : begin
                read_command_matrix_C_job_latched.valid <= 0;
                generate_read_command                   <= 1;
                shift_limit_clear                       <= 0;
            end
            CALC_MATRIX_C_REQ_SIZE : begin
                generate_read_command <= 0;
            end
            SEND_MATRIX_C_START : begin
                read_command_matrix_C_job_latched.payload <= read_command_matrix_C_job_latched_S2.payload;
            end
            SEND_MATRIX_C_DATA_READ : begin
                read_command_matrix_C_job_latched.valid                    <= 1'b1;
                read_command_matrix_C_job_latched.payload.address          <= wed_request_in_latched.payload.wed.Matrix_C + (((matrix_C_num_counter_ii_inc * wed_request_in_latched.payload.wed.size_n) + matrix_C_num_counter_jj_inc) << $clog2(DATA_SIZE_READ));
                read_command_matrix_C_job_latched.payload.cmd.array_struct <= MATRIX_C_DATA_READ;
            end
            WAIT_MATRIX_C_DATA : begin
                read_command_matrix_C_job_latched.valid <= 0;
                if(fill_matrix_C_job_buffer) begin
                    clear_data_ready <= 1;
                end
            end
            SHIFT_MATRIX_C_DATA_START : begin
                clear_data_ready <= 0;
                start_shift_hf_0 <= 0;
                start_shift_hf_1 <= 0;
                switch_shift_hf  <= 0;
            end
            SHIFT_MATRIX_C_DATA_0 : begin
                start_shift_hf_0 <= 1;
                start_shift_hf_1 <= 0;
                switch_shift_hf  <= 0;
                shift_counter    <= shift_counter + 1;
            end
            SHIFT_MATRIX_C_DATA_DONE_0 : begin
                start_shift_hf_0 <= 0;
                start_shift_hf_1 <= 0;
                switch_shift_hf  <= 0;
                shift_counter    <= 0;
            end
            SHIFT_MATRIX_C_DATA_1 : begin
                start_shift_hf_0 <= 0;
                start_shift_hf_1 <= 1;
                switch_shift_hf  <= 1;
                shift_counter    <= shift_counter + 1;
            end
            SHIFT_MATRIX_C_DATA_DONE_1 : begin
                start_shift_hf_0  <= 0;
                start_shift_hf_1  <= 0;
                shift_limit_clear <= 1;
                switch_shift_hf   <= 0;
                shift_counter     <= 0;
            end
        endcase
    end // always_ff @(posedge clock)

////////////////////////////////////////////////////////////////////////////
//generate Vertex data offset
////////////////////////////////////////////////////////////////////////////

// track i iteration in for loop i*j
// track j iteration in for loop
    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            matrix_C_num_counter_jj_dec <= 0;
            matrix_C_num_counter_ii_dec <= 0;
            matrix_C_num_counter_jj_inc <= 0;
            matrix_C_num_counter_ii_inc <= 0;
        end else begin
            if(setup_read_command) begin
                matrix_C_num_counter_jj_dec <= (jj_reg_end - jj_reg_start);
                matrix_C_num_counter_ii_dec <= (ii_reg_end - ii_reg_start);
                matrix_C_num_counter_jj_inc <= jj_reg_start;
                matrix_C_num_counter_ii_inc <= ii_reg_start;
            end

            if (generate_read_command) begin
                if(matrix_C_num_counter_jj_dec > CACHELINE_DATA_READ_NUM)begin
                    matrix_C_num_counter_jj_dec <= matrix_C_num_counter_jj_dec - CACHELINE_DATA_READ_NUM;
                end
                else if (matrix_C_num_counter_jj_dec <= CACHELINE_DATA_READ_NUM) begin
                    matrix_C_num_counter_jj_dec <= (jj_reg_end - jj_reg_start);
                    matrix_C_num_counter_ii_dec <= matrix_C_num_counter_ii_dec;
                    matrix_C_num_counter_ii_inc <= matrix_C_num_counter_ii_inc + 1;
                    matrix_C_num_counter_jj_inc <= jj_reg_start;
                end
            end

            if (read_command_matrix_C_job_latched.valid ) begin
                matrix_C_num_counter_jj_inc <= matrix_C_num_counter_jj_inc + CACHELINE_DATA_READ_NUM;
            end
        end
    end


    always_ff @(posedge clock) begin
        if (generate_read_command) begin
            if(matrix_C_num_counter_jj_dec > CACHELINE_DATA_READ_NUM)begin
                read_command_matrix_C_job_latched_S2.payload.cmd.real_size       <= CACHELINE_DATA_READ_NUM;
                read_command_matrix_C_job_latched_S2.payload.cmd.real_size_bytes <= 128;
            end
            else if (matrix_C_num_counter_jj_dec <= CACHELINE_DATA_READ_NUM) begin
                read_command_matrix_C_job_latched_S2.payload.cmd.real_size       <= matrix_C_num_counter_jj_dec;
                read_command_matrix_C_job_latched_S2.payload.cmd.real_size_bytes <= (matrix_C_num_counter_jj_dec << $clog2(DATA_SIZE_READ));
            end
            read_command_matrix_C_job_latched_S2.payload.size                 <= 12'h080;
            read_command_matrix_C_job_latched_S2.payload.command              <= READ_CL_S;
            read_command_matrix_C_job_latched_S2.payload.cmd.cu_id_x          <= MATRIX_C_CONTROL_ID;
            read_command_matrix_C_job_latched_S2.payload.cmd.cu_id_y          <= MATRIX_C_CONTROL_ID;
            read_command_matrix_C_job_latched_S2.payload.cmd.cmd_type         <= CMD_READ;
            read_command_matrix_C_job_latched_S2.payload.cmd.address_offset   <= matrix_C_num_counter_ii_inc;
            read_command_matrix_C_job_latched_S2.payload.cmd.aux_data         <= matrix_C_num_counter_jj_inc;
            read_command_matrix_C_job_latched_S2.payload.cmd.cacheline_offset <= 0;
            read_command_matrix_C_job_latched_S2.payload.cmd.abt              <= STRICT;
            read_command_matrix_C_job_latched_S2.payload.cmd.size             <= 12'h080;
            read_command_matrix_C_job_latched_S2.payload.cmd.tag              <= 0;
            read_command_matrix_C_job_latched_S2.payload.abt                  <= STRICT;
        end
    end


////////////////////////////////////////////////////////////////////////////
//Read Vertex data into registers
////////////////////////////////////////////////////////////////////////////

    always_ff @(posedge clock) begin
        if(read_data_0_in_latched.valid) begin
            case (read_data_0_in_latched.payload.cmd.array_struct)
                MATRIX_C_DATA_READ : begin
                    reg_MATRIX_C_DATA_READ_0 <= read_data_0_in_latched.payload.data;
                end
            endcase
        end

        if(~switch_shift_hf && start_shift_hf_0) begin
            reg_MATRIX_C_DATA_READ_0 <= {reg_MATRIX_C_DATA_READ_0[DATA_SIZE_READ_BITS:(CACHELINE_SIZE_BITS_HF-1)],DATA_SIZE_READ_NULL_BITS};
        end
    end

    always_ff @(posedge clock) begin
        if(read_data_1_in_latched.valid) begin
            case (read_data_1_in_latched.payload.cmd.array_struct)
                MATRIX_C_DATA_READ : begin
                    reg_MATRIX_C_DATA_READ_1 <= read_data_1_in_latched.payload.data;
                end
            endcase
        end

        if(switch_shift_hf && start_shift_hf_1) begin
            reg_MATRIX_C_DATA_READ_1 <= {reg_MATRIX_C_DATA_READ_1[DATA_SIZE_READ_BITS:(CACHELINE_SIZE_BITS_HF-1)],DATA_SIZE_READ_NULL_BITS};
        end
    end

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            matrix_C_data_ready <= 0;
        end else begin
            if(read_response_in_latched.valid) begin
                case (read_response_in_latched.payload.cmd.array_struct)
                    MATRIX_C_DATA_READ : begin
                        matrix_C_data_ready <= 1;
                    end
                endcase
            end

            if(clear_data_ready) begin
                matrix_C_data_ready <= 0;
            end
        end
    end

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            shift_limit_0 <= 0;
            shift_limit_1 <= 0;
            zero_pass     <= 0;
        end else begin
            if(read_response_in_latched.valid) begin
                if(~(|shift_limit_0) && ~shift_limit_clear) begin
                    if(read_response_in_latched.payload.cmd.real_size > CACHELINE_DATA_READ_NUM_HF) begin
                        shift_limit_0 <= CACHELINE_DATA_READ_NUM_HF-1;
                        shift_limit_1 <= read_response_in_latched.payload.cmd.real_size - CACHELINE_DATA_READ_NUM_HF - 1;
                        zero_pass     <= ((read_response_in_latched.payload.cmd.real_size - CACHELINE_DATA_READ_NUM_HF) == 1);
                    end else begin
                        shift_limit_0 <= read_response_in_latched.payload.cmd.real_size-1;
                        shift_limit_1 <= 0;
                        zero_pass     <= 0;
                    end
                end
            end

            if(shift_limit_clear) begin
                shift_limit_0 <= 0;
                shift_limit_1 <= 0;
                zero_pass     <= 0;
            end
        end
    end

////////////////////////////////////////////////////////////////////////////
//Read Vertex registers into matrix_C job queue
////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////
//Buffers Vertices
////////////////////////////////////////////////////////////////////////////

    assign send_request_ready       = read_buffer_status_internal.empty && matrix_C_buffer_burst_status.empty  && (|matrix_C_num_counter_ii_dec) && wed_request_in_latched.valid;
    assign fill_matrix_C_job_buffer = matrix_C_data_ready;

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            matrix_C_variable.valid <= 0;
            matrix_C_id_counter     <= 0;
        end
        else begin
            if(push_shift) begin
                matrix_C_id_counter     <= matrix_C_id_counter+1;
                matrix_C_variable.valid <= 1;
            end else begin
                matrix_C_variable.valid <= 0;
            end
        end
    end

    always_ff @(posedge clock) begin
        matrix_C_variable.payload.ii   <= matrix_C_id_counter;
        matrix_C_variable.payload.jj   <= matrix_C_id_counter;
        matrix_C_variable.payload.data <= swap_endianness_data_read(matrix_C_data);
    end

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            push_shift <= 0;
        end else begin
            if(~switch_shift_hf && start_shift_hf_0) begin
                push_shift <= 1;
            end else if(switch_shift_hf && start_shift_hf_1) begin
                push_shift <= 1;
            end else begin
                push_shift <= 0;
            end
        end
    end

    always_ff @(posedge clock) begin
        if(~switch_shift_hf && start_shift_hf_0) begin
            matrix_C_data <= reg_MATRIX_C_DATA_READ_0[0:DATA_SIZE_READ_BITS-1];
        end else if(switch_shift_hf && start_shift_hf_1) begin
            matrix_C_data <= reg_MATRIX_C_DATA_READ_1[0:DATA_SIZE_READ_BITS-1];
        end
    end

////////////////////////////////////////////////////////////////////////////
//Read Vertex double buffer
////////////////////////////////////////////////////////////////////////////
    assign matrix_C_buffer_burst_pop = ~matrix_C_buffer_status.alfull && ~matrix_C_buffer_burst_status.empty;

    fifo #(
        .WIDTH($bits(MatrixCInterface)),
        .DEPTH(CACHELINE_DATA_READ_NUM)
    ) matrix_C_job_buffer_burst_fifo_instant (
        .clock   (clock                              ),
        .rstn    (rstn                               ),

        .push    (matrix_C_variable.valid            ),
        .data_in (matrix_C_variable                  ),
        .full    (matrix_C_buffer_burst_status.full  ),
        .alFull  (matrix_C_buffer_burst_status.alfull),

        .pop     (matrix_C_buffer_burst_pop          ),
        .valid   (matrix_C_buffer_burst_status.valid ),
        .data_out(matrix_C_burst_variable            ),
        .empty   (matrix_C_buffer_burst_status.empty )
    );

    fifo #(
        .WIDTH($bits(MatrixCInterface)    ),
        .DEPTH(CU_MATRIX_C_JOB_BUFFER_SIZE)
    ) matrix_C_job_buffer_fifo_instant (
        .clock   (clock                        ),
        .rstn    (rstn                         ),

        .push    (matrix_C_burst_variable.valid),
        .data_in (matrix_C_burst_variable      ),
        .full    (matrix_C_buffer_status.full  ),
        .alFull  (matrix_C_buffer_status.alfull),

        .pop     (matrix_C_request_latched     ),
        .valid   (matrix_C_buffer_status.valid ),
        .data_out(matrix_C_latched             ),
        .empty   (matrix_C_buffer_status.empty )
    );

///////////////////////////////////////////////////////////////////////////
//Read Command Vertex double buffer
////////////////////////////////////////////////////////////////////////////

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            read_command_bus_grant_latched <= 0;
            read_command_bus_request       <= 0;
        end else begin
            if(enabled_cmd) begin
                read_command_bus_grant_latched <= read_command_bus_grant;
                read_command_bus_request       <= read_command_bus_request_latched;
            end
        end
    end

    assign read_command_bus_request_latched = ~read_buffer_status_latched.alfull && ~read_buffer_status_internal.empty;
    assign read_command_bus_request_pop     = ~read_buffer_status_latched.alfull && read_command_bus_grant_latched;

    fifo #(
        .WIDTH($bits(CommandBufferLine)),
        .DEPTH(16                      )
    ) read_command_job_matrix_C_burst_fifo_instant (
        .clock   (clock                                  ),
        .rstn    (rstn                                   ),

        .push    (read_command_matrix_C_job_latched.valid),
        .data_in (read_command_matrix_C_job_latched      ),
        .full    (read_buffer_status_internal.full       ),
        .alFull  (read_buffer_status_internal.alfull     ),

        .pop     (read_command_bus_request_pop           ),
        .valid   (read_buffer_status_internal.valid      ),
        .data_out(read_command_out_latched               ),
        .empty   (read_buffer_status_internal.empty      )
    );


endmodule