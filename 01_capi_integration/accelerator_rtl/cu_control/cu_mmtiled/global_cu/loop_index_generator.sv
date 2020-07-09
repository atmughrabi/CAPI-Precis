// -----------------------------------------------------------------------------
//
//          Shared Memory Accelerator Project"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi atmughrabi@gmail.com/atmughra@ncsu.edu
// File   : loop_index_generator.sv
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

module loop_index_generator (
    input  logic        clock              , // Clock
    input  logic        rstn_in            ,
    input  logic        enabled_in         ,
    input  logic [0:63] start_index        ,
    input  logic [0:63] end_index          ,
    input  logic [0:63] displacement       ,
    input  logic        index_request      ,
    output BufferStatus index_buffer_status,
    output logic        index_done         ,
    output logic [0:63] output_index
);

    logic [0:63] loop_index              ;
    logic [0:63] pushed_index            ;
    logic        loop_index_valid        ;
    logic        loop_index_valid_latched;
    logic        rstn                    ;

    loop_index_gen_state  current_state, next_state;

    always_ff @(posedge clock or negedge rstn_in) begin
        if(~rstn_in) begin
            rstn <= 0;
        end else begin
            rstn <= rstn_in;
        end
    end

    ////////////////////////////////////////////////////////////////////////////
//1. Generate Read Commands to obtain matrix_C structural info
////////////////////////////////////////////////////////////////////////////

    // wed_request_in_latched.payload.size_n
    // wed_request_in_latched.payload.Matrix_C
    // cu_configure_latched[0:31]
    // cu_configure_2_latched[0:31]
    // cu_configure_2_latched[32:63]

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn)
            current_state <= SEND_READ_MATRIX_C_RESET;
        else begin
            if(enabled) begin
                current_state <= next_state;
            end
        end
    end // always_ff @(posedge clock)

    always_comb begin
        next_state = current_state;
        case (current_state)
            SEND_READ_MATRIX_C_RESET : begin
                if(wed_request_in_latched.valid && enabled_cmd)
                    next_state = SEND_READ_MATRIX_C_INIT;
                else
                    next_state = SEND_READ_MATRIX_C_RESET;
            end
            SEND_READ_MATRIX_C_INIT : begin
                next_state = SEND_READ_MATRIX_C_IDLE;
            end
            SEND_READ_MATRIX_C_IDLE : begin
                if(send_request_ready)
                    next_state = START_READ_MATRIX_C_REQ;
                else
                    next_state = SEND_READ_MATRIX_C_IDLE;
            end
            START_READ_MATRIX_C_REQ : begin
                next_state = CALC_READ_MATRIX_C_REQ_SIZE;
            end
            CALC_READ_MATRIX_C_REQ_SIZE : begin
                next_state = SEND_READ_MATRIX_C_START;
            end
            SEND_READ_MATRIX_C_START : begin
                next_state = SEND_READ_MATRIX_C_DATA_READ;
            end
            SEND_READ_MATRIX_C_DATA_READ : begin
                next_state = WAIT_READ_MATRIX_C_DATA;
            end
            WAIT_READ_MATRIX_C_DATA : begin
                if(fill_matrix_C_job_buffer)
                    next_state = SHIFT_READ_MATRIX_C_DATA_START;
                else
                    next_state = WAIT_READ_MATRIX_C_DATA;
            end
            SHIFT_READ_MATRIX_C_DATA_START : begin
                next_state = SHIFT_READ_MATRIX_C_DATA_0;
            end
            SHIFT_READ_MATRIX_C_DATA_0 : begin
                if((shift_counter < shift_limit_0))
                    next_state = SHIFT_READ_MATRIX_C_DATA_0;
                else
                    next_state = SHIFT_READ_MATRIX_C_DATA_DONE_0;
            end
            SHIFT_READ_MATRIX_C_DATA_DONE_0 : begin
                if(|shift_limit_1 || zero_pass)
                    next_state = SHIFT_READ_MATRIX_C_DATA_1;
                else
                    next_state = SHIFT_READ_MATRIX_C_DATA_DONE_1;
            end
            SHIFT_READ_MATRIX_C_DATA_1 : begin
                if((shift_counter < shift_limit_1))
                    next_state = SHIFT_READ_MATRIX_C_DATA_1;
                else
                    next_state = SHIFT_READ_MATRIX_C_DATA_DONE_1;
            end
            SHIFT_READ_MATRIX_C_DATA_DONE_1 : begin
                next_state = SEND_READ_MATRIX_C_IDLE;
            end
        endcase
    end // always_comb

    always_ff @(posedge clock) begin
        case (current_state)
            SEND_READ_MATRIX_C_RESET : begin
                read_command_matrix_C_job_latched.valid <= 0;
                matrix_C_next_offset                    <= 0;
                generate_read_command                   <= 0;
                setup_read_command                      <= 0;
                clear_data_ready                        <= 1;
                shift_limit_clear                       <= 1;
                start_shift_hf_0                        <= 0;
                start_shift_hf_1                        <= 0;
                switch_shift_hf                         <= 0;
                shift_counter                           <= 0;
                ii_count                                <= 0;
                jj_count                                <= 0;
                ii_jj_offset                            <= 0;
            end
            SEND_READ_MATRIX_C_INIT : begin
                read_command_matrix_C_job_latched.valid <= 0;
                clear_data_ready                        <= 0;
                shift_limit_clear                       <= 0;
                setup_read_command                      <= 1;
                ii_count                                <= ii;
                jj_count                                <= jj;
            end
            SEND_READ_MATRIX_C_IDLE : begin
                read_command_matrix_C_job_latched.valid <= 0;
                setup_read_command                      <= 0;
                shift_limit_clear                       <= 0;
                shift_counter                           <= 0;
            end
            START_READ_MATRIX_C_REQ : begin
                read_command_matrix_C_job_latched.valid <= 0;
                generate_read_command                   <= 1;
                shift_limit_clear                       <= 0;
            end
            CALC_READ_MATRIX_C_REQ_SIZE : begin
                generate_read_command <= 0;
            end
            SEND_READ_MATRIX_C_START : begin
                read_command_matrix_C_job_latched.payload <= read_command_matrix_C_job_latched_S2.payload;
                ii_jj_offset                              <= ii_count *  wed_request_in_latched.payload.wed.size_n;
            end
            SEND_READ_MATRIX_C_DATA_READ : begin
                read_command_matrix_C_job_latched.valid                    <= 1'b1;
                read_command_matrix_C_job_latched.payload.address          <= wed_request_in_latched.payload.wed.Matrix_C +  ii_jj_offset + jj_count;
                read_command_matrix_C_job_latched.payload.cmd.array_struct <= MATRIX_C_DATA_READ;
                jj_count                                                   <= jj_count + CACHELINE_SIZE;
            end
            WAIT_READ_MATRIX_C_DATA : begin
                read_command_matrix_C_job_latched.valid <= 0;
                if(fill_matrix_C_job_buffer) begin
                    clear_data_ready <= 1;
                end
            end
            SHIFT_READ_MATRIX_C_DATA_START : begin
                clear_data_ready <= 0;
                start_shift_hf_0 <= 0;
                start_shift_hf_1 <= 0;
                switch_shift_hf  <= 0;
            end
            SHIFT_READ_MATRIX_C_DATA_0 : begin
                start_shift_hf_0 <= 1;
                start_shift_hf_1 <= 0;
                switch_shift_hf  <= 0;
                shift_counter    <= shift_counter + 1;
            end
            SHIFT_READ_MATRIX_C_DATA_DONE_0 : begin
                start_shift_hf_0 <= 0;
                start_shift_hf_1 <= 0;
                switch_shift_hf  <= 0;
                shift_counter    <= 0;
            end
            SHIFT_READ_MATRIX_C_DATA_1 : begin
                start_shift_hf_0 <= 0;
                start_shift_hf_1 <= 1;
                switch_shift_hf  <= 1;
                shift_counter    <= shift_counter + 1;
            end
            SHIFT_READ_MATRIX_C_DATA_DONE_1 : begin
                start_shift_hf_0  <= 0;
                start_shift_hf_1  <= 0;
                shift_limit_clear <= 1;
                switch_shift_hf   <= 0;
                shift_counter     <= 0;
            end
        endcase
    end // always_ff @(posedge clock)


    fifo #(
        .WIDTH(64),
        .DEPTH(32)
    ) loop_index_generator_fifo_instant (
        .clock   (clock                     ),
        .rstn    (rstn                      ),

        .push    (loop_index_valid_latched  ),
        .data_in (pushed_index              ),
        .full    (index_buffer_status.full  ),
        .alFull  (index_buffer_status.alfull),

        .pop     (index_request             ),
        .valid   (index_buffer_status.valid ),
        .data_out(output_index              ),
        .empty   (index_buffer_status.empty )
    );


endmodule
