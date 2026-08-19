// -----------------------------------------------------------------------------
//
//      Shared Memory Accelerator Project"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi atmughrabi@gmail.com/atmughra@ncsu.edu
// File   : cu_control.sv
// Create : 2019-09-26 15:18:39
// Revise : 2019-11-07 19:49:13
// Editor : sublime text3, tab size (4)
// -----------------------------------------------------------------------------

import GLOBALS_AFU_PKG::*;
import GLOBALS_CU_PKG::*;
import CAPI_PKG::*;
import WED_PKG::*;
import AFU_PKG::*;
import CU_PKG::*;

module cu_control #(
    parameter NUM_READ_REQUESTS = 2              ,
    parameter NUM_X_CU          = NUM_X_CU_GLOBAL,
    parameter NUM_Y_CU          = NUM_Y_CU_GLOBAL
) (
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

    logic                         rstn                                                  ;
    logic                         rstn_internal                                         ;
    logic                         rstn_output                                           ;
    logic                         rstn_input                                            ;
    logic [0:(ARRAY_SIZE_BITS-1)] matrix_C_job_counter_filtered                         ;
    logic [NUM_READ_REQUESTS-1:0] submit                                                ;
    logic [NUM_READ_REQUESTS-1:0] requests                                              ;
    logic [NUM_READ_REQUESTS-1:0] ready                                                 ;
    CommandBufferLine             read_command_buffer_arbiter_in [0:NUM_READ_REQUESTS-1];
    CommandBufferLine             read_command_buffer_arbiter_out                       ;



    // matrix_C control variables

    // logic [0:(ARRAY_SIZE_BITS-1)] ii_reg_start;
    // logic [0:(ARRAY_SIZE_BITS-1)] jj_reg_start;
    // logic [0:(ARRAY_SIZE_BITS-1)] kk_reg_start;
    // logic [0:(ARRAY_SIZE_BITS-1)] ii_reg_end  ;
    // logic [0:(ARRAY_SIZE_BITS-1)] jj_reg_end  ;
    // logic [0:(ARRAY_SIZE_BITS-1)] kk_reg_end  ;
    // logic [0:(ARRAY_SIZE_BITS-1)] ii_reg_limit;
    // logic [0:(ARRAY_SIZE_BITS-1)] jj_reg_limit;
    // logic [0:(ARRAY_SIZE_BITS-1)] kk_reg_limit;

    //output latched
    CommandBufferLine write_command_out_matrix_A_B;
    ReadWriteDataLine write_data_0_out_matrix_A_B ;
    ReadWriteDataLine write_data_1_out_matrix_A_B ;


    //input lateched
    WEDInterface       wed_request_in_latched       ;
    ResponseBufferLine read_response_in_latched     ;
    ResponseBufferLine read_response_in_matrix_C_job;
    ResponseBufferLine read_response_in_matrix_A_B  ;

    BufferStatus write_buffer_status_latched;
    BufferStatus read_buffer_status_latched ;

    ResponseBufferLine write_response_in_matrix_A_B;
    ReadWriteDataLine  read_data_0_in_latched      ;
    ReadWriteDataLine  read_data_1_in_latched      ;

    ReadWriteDataLine read_data_0_in_matrix_C_job;
    ReadWriteDataLine read_data_0_in_matrix_A_B  ;
    ReadWriteDataLine read_data_1_in_matrix_C_job;
    ReadWriteDataLine read_data_1_in_matrix_A_B  ;



    cu_return_type cu_return_latched     ;
    logic [0:63]   cu_configure_latched  ;
    logic [0:63]   cu_configure_2_latched;
    logic [0:63]   cu_configure_3_latched;
    logic [0:63]   cu_configure_4_latched;

    logic                         done_algorithm                     ;
    logic [0:(ARRAY_SIZE_BITS-1)] matrix_C_job_counter_done          ;
    logic [0:(ARRAY_SIZE_BITS-1)] matrix_A_B_job_counter_done        ;
    logic [0:(ARRAY_SIZE_BITS-1)] matrix_C_job_counter_done_latched  ;
    logic [0:(ARRAY_SIZE_BITS-1)] matrix_A_B_job_counter_done_latched;
    logic [0:(ARRAY_SIZE_BITS-1)] matrix_C_job_counter_total_latched ;

    logic            enabled                    ;
    logic            enabled_cmd                ;
    logic            enabled_matrix_C_job       ;
    logic            enabled_matrix_A_B         ;
    logic            cu_ready                   ;
    MatrixCInterface matrix_C_unfiltered        ;
    logic            matrix_C_request_unfiltered;

    ResponseBufferLine prefetch_read_response_in_latched;
    CommandBufferLine  prefetch_read_command_out_latched;

    ResponseBufferLine prefetch_write_response_in_latched;
    CommandBufferLine  prefetch_write_command_out_latched;

    logic enabled_prefetch_read ;
    logic enabled_prefetch_write;

    logic write_command_bus_grant  ;
    logic write_command_bus_request;

    localparam int MATRIX_ENGINE_COUNT = NUM_X_CU * NUM_Y_CU;

    CommandBufferLine matrix_engine_read_command [0:MATRIX_ENGINE_COUNT-1];
    CommandBufferLine matrix_engine_write_command[0:MATRIX_ENGINE_COUNT-1];
    ReadWriteDataLine matrix_engine_write_data_0 [0:MATRIX_ENGINE_COUNT-1];
    ReadWriteDataLine matrix_engine_write_data_1 [0:MATRIX_ENGINE_COUNT-1];
    logic [MATRIX_ENGINE_COUNT-1:0] matrix_engine_read_valid;
    logic [MATRIX_ENGINE_COUNT-1:0] matrix_engine_write_valid;
    logic [MATRIX_ENGINE_COUNT-1:0] matrix_engine_read_grant;
    logic [MATRIX_ENGINE_COUNT-1:0] matrix_engine_write_grant;
    logic [MATRIX_ENGINE_COUNT-1:0] matrix_engine_read_armed;
    logic [MATRIX_ENGINE_COUNT-1:0] matrix_engine_write_armed;
    logic [0:1] matrix_engine_read_rearm_delay [0:MATRIX_ENGINE_COUNT-1];
    logic [0:1] matrix_engine_write_rearm_delay[0:MATRIX_ENGINE_COUNT-1];
    logic [MATRIX_ENGINE_COUNT-1:0] matrix_engine_done;
    logic [0:63] matrix_engine_completed_writes[0:MATRIX_ENGINE_COUNT-1];
    logic [0:63] matrix_engine_multiply_terms [0:MATRIX_ENGINE_COUNT-1];
    logic [0:63] matrix_engine_completed_sum;
    logic [0:63] matrix_engine_terms_sum;
    logic matrix_engine_all_done;
    CommandBufferLine matrix_engine_read_pending;
    CommandBufferLine matrix_engine_write_pending;
    ReadWriteDataLine matrix_engine_write_data_0_pending;
    ReadWriteDataLine matrix_engine_write_data_1_pending;
    integer matrix_read_rr;
    integer matrix_write_rr;
    integer matrix_read_selected;
    integer matrix_write_selected;
    integer matrix_read_pending_owner;
    integer matrix_write_pending_owner;
    logic matrix_read_cooldown;
    logic matrix_write_cooldown;
    logic matrix_read_ready_latched;
    logic matrix_engine_write_dispatch;

    function automatic integer select_matrix_engine(
        input logic [MATRIX_ENGINE_COUNT-1:0] valids,
        input integer start_index
    );
        integer offset;
        integer candidate;
        begin
            select_matrix_engine = -1;
            for(offset = 0; offset < MATRIX_ENGINE_COUNT; offset = offset + 1) begin
                candidate = (start_index + offset) % MATRIX_ENGINE_COUNT;
                if(select_matrix_engine < 0 && valids[candidate])
                    select_matrix_engine = candidate;
            end
        end
    endfunction

////////////////////////////////////////////////////////////////////////////
// logic
////////////////////////////////////////////////////////////////////////////

    assign read_command_buffer_arbiter_in[1] = matrix_engine_read_pending;
    assign write_command_bus_request         = matrix_engine_write_pending.valid;
    assign matrix_engine_write_dispatch =
        matrix_engine_write_pending.valid &&
        ~write_buffer_status_latched.alfull;

    always_comb begin
        write_command_out_matrix_A_B = matrix_engine_write_pending;
        write_data_0_out_matrix_A_B = matrix_engine_write_data_0_pending;
        write_data_1_out_matrix_A_B = matrix_engine_write_data_1_pending;
        write_command_out_matrix_A_B.valid = matrix_engine_write_dispatch;
        write_data_0_out_matrix_A_B.valid =
            matrix_engine_write_dispatch &&
            matrix_engine_write_data_0_pending.valid;
        write_data_1_out_matrix_A_B.valid =
            matrix_engine_write_dispatch &&
            matrix_engine_write_data_1_pending.valid;
    end

    always_comb begin
        matrix_read_selected =
            select_matrix_engine(matrix_engine_read_valid, matrix_read_rr);
        matrix_write_selected =
            select_matrix_engine(matrix_engine_write_valid, matrix_write_rr);
        matrix_engine_completed_sum = 0;
        matrix_engine_terms_sum = 0;
        matrix_engine_all_done = 1;
        for(int lane = 0; lane < MATRIX_ENGINE_COUNT; lane = lane + 1) begin
            matrix_engine_completed_sum =
                matrix_engine_completed_sum + matrix_engine_completed_writes[lane];
            matrix_engine_terms_sum =
                matrix_engine_terms_sum + matrix_engine_multiply_terms[lane];
            matrix_engine_all_done =
                matrix_engine_all_done && matrix_engine_done[lane];
        end
    end

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            matrix_engine_read_pending <= 0;
            matrix_engine_write_pending <= 0;
            matrix_engine_write_data_0_pending <= 0;
            matrix_engine_write_data_1_pending <= 0;
            matrix_engine_read_grant <= 0;
            matrix_engine_write_grant <= 0;
            matrix_engine_read_armed <= '1;
            matrix_engine_write_armed <= '1;
            for(int lane = 0; lane < MATRIX_ENGINE_COUNT; lane = lane + 1) begin
                matrix_engine_read_rearm_delay[lane] <= 0;
                matrix_engine_write_rearm_delay[lane] <= 0;
            end
            matrix_read_rr <= 0;
            matrix_write_rr <= 0;
            matrix_read_pending_owner <= 0;
            matrix_write_pending_owner <= 0;
            matrix_read_cooldown <= 0;
            matrix_write_cooldown <= 0;
            matrix_read_ready_latched <= 0;
        end else begin
            matrix_engine_read_grant <= 0;
            matrix_engine_write_grant <= 0;
            for(int lane = 0; lane < MATRIX_ENGINE_COUNT; lane = lane + 1) begin
                if(|matrix_engine_read_rearm_delay[lane])
                    matrix_engine_read_rearm_delay[lane] <=
                        matrix_engine_read_rearm_delay[lane] - 1;
                else if(~matrix_engine_read_command[lane].valid)
                    matrix_engine_read_armed[lane] <= 1;
                if(|matrix_engine_write_rearm_delay[lane])
                    matrix_engine_write_rearm_delay[lane] <=
                        matrix_engine_write_rearm_delay[lane] - 1;
                else if(~matrix_engine_write_command[lane].valid)
                    matrix_engine_write_armed[lane] <= 1;
            end

            if(matrix_engine_read_pending.valid) begin
                if(matrix_read_ready_latched) begin
                    matrix_engine_read_pending.valid <= 0;
                    matrix_engine_read_grant[matrix_read_pending_owner] <= 1;
                    matrix_engine_read_armed[matrix_read_pending_owner] <= 0;
                    matrix_engine_read_rearm_delay[matrix_read_pending_owner] <= 2;
                    matrix_read_cooldown <= 1;
                    matrix_read_ready_latched <= 0;
                end else
                    matrix_read_ready_latched <= ready[1];
            end else if(matrix_read_cooldown) begin
                matrix_read_cooldown <= 0;
                matrix_read_ready_latched <= 0;
            end else if(matrix_read_selected >= 0) begin
                matrix_engine_read_pending <=
                    matrix_engine_read_command[matrix_read_selected];
                matrix_read_pending_owner <= matrix_read_selected;
                matrix_read_ready_latched <= 0;
                matrix_read_rr <=
                    (matrix_read_selected + 1) % MATRIX_ENGINE_COUNT;
            end else
                matrix_read_ready_latched <= 0;

            if(matrix_engine_write_pending.valid) begin
                if(matrix_engine_write_dispatch) begin
                    matrix_engine_write_pending.valid <= 0;
                    matrix_engine_write_data_0_pending.valid <= 0;
                    matrix_engine_write_data_1_pending.valid <= 0;
                    matrix_engine_write_grant[matrix_write_pending_owner] <= 1;
                    matrix_engine_write_armed[matrix_write_pending_owner] <= 0;
                    matrix_engine_write_rearm_delay[matrix_write_pending_owner] <= 2;
                    matrix_write_cooldown <= 1;
                end
            end else if(matrix_write_cooldown) begin
                matrix_write_cooldown <= 0;
            end else if(matrix_write_selected >= 0) begin
                matrix_engine_write_pending <=
                    matrix_engine_write_command[matrix_write_selected];
                matrix_engine_write_data_0_pending <=
                    matrix_engine_write_data_0[matrix_write_selected];
                matrix_engine_write_data_1_pending <=
                    matrix_engine_write_data_1[matrix_write_selected];
                matrix_write_pending_owner <= matrix_write_selected;
                matrix_write_rr <=
                    (matrix_write_selected + 1) % MATRIX_ENGINE_COUNT;
            end
        end
    end


    always_ff @(posedge clock or negedge rstn_in) begin
        if(~rstn_in) begin
            rstn_internal <= 0;
        end else begin
            rstn_internal <= rstn_in;
        end
    end

    always_ff @(posedge clock or negedge rstn_internal) begin
        if(~rstn_internal) begin
            rstn        <= 0;
            rstn_output <= 0;
            rstn_input  <= 0;
        end else begin
            rstn        <= rstn_internal;
            rstn_output <= rstn_internal;
            rstn_input  <= rstn_internal;
        end
    end

    always_ff @(posedge clock or negedge rstn_output) begin
        if(~rstn_output) begin
            prefetch_read_command_out_latched  <= 0;
            prefetch_write_command_out_latched <= 0;
        end else begin
            prefetch_read_command_out_latched  <= 0;
            prefetch_write_command_out_latched <= 0;
        end
    end

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            write_command_bus_grant <= 0;
        end else begin
            write_command_bus_grant <= write_command_bus_request && ~write_buffer_status_latched.alfull;
        end
    end

////////////////////////////////////////////////////////////////////////////
//enable logic
////////////////////////////////////////////////////////////////////////////

    always_ff @(posedge clock or negedge rstn_input) begin
        if(~rstn_input) begin
            enabled                <= 0;
            cu_ready               <= 0;
            enabled_prefetch_read  <= 0;
            enabled_prefetch_write <= 0;
        end else begin
            enabled  <= enabled_in;
            cu_ready <= (|cu_configure_latched) && (cu_configure_2_latched[63]) && (cu_configure_3_latched[63]) && (cu_configure_4_latched[63]) && wed_request_in_latched.valid;
            // enabled_prefetch_read  <= cu_ready && cu_configure_latched[30];
            // enabled_prefetch_write <= cu_ready && cu_configure_latched[31];

            enabled_prefetch_read  <= 0;
            enabled_prefetch_write <= 0;
        end
    end

////////////////////////////////////////////////////////////////////////////
//Done signal
//Final return value with done signal asserted.
//number of vertecies and edges processed returned
////////////////////////////////////////////////////////////////////////////a

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            cu_return_latched <= 0;
            done_algorithm    <= 0;
        end else begin
            if(enabled_matrix_A_B)begin
                cu_return_latched.var1 <= matrix_engine_completed_sum;
                cu_return_latched.var2 <= matrix_engine_terms_sum;
                done_algorithm         <= matrix_engine_all_done;
            end
        end
    end

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            cu_return                           <= 0;
            cu_done                             <= 0;
            matrix_C_job_counter_done_latched   <= 0;
            matrix_A_B_job_counter_done_latched <= 0;
            matrix_C_job_counter_total_latched  <= 0;
        end else begin
            if(enabled)begin
                cu_return                           <= cu_return_latched;
                cu_done                             <= done_algorithm;
                matrix_C_job_counter_done_latched   <= matrix_engine_completed_sum;
                matrix_A_B_job_counter_done_latched <= matrix_engine_terms_sum;
                matrix_C_job_counter_total_latched  <= matrix_engine_completed_sum;
            end
        end
    end

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            cu_status            <= 0;
            enabled_matrix_C_job <= 0;
            enabled_matrix_A_B   <= 0;
            enabled_cmd          <= 0;
        end else begin
            if(cu_ready) begin
                cu_status            <= cu_configure_latched;
                enabled_matrix_C_job <= 0;
                enabled_matrix_A_B   <= 1;
                enabled_cmd          <= 1;
            end
        end
    end

////////////////////////////////////////////////////////////////////////////
//Drive input output
////////////////////////////////////////////////////////////////////////////

    always_ff @(posedge clock or negedge rstn_output) begin
        if(~rstn_output) begin
            write_command_out.valid           <= 0;
            write_data_0_out.valid            <= 0;
            write_data_1_out.valid            <= 0;
            read_command_out.valid            <= 0;
            write_buffer_status_latched       <= 0;
            read_buffer_status_latched        <= 0;
            write_buffer_status_latched.empty <= 1;
            read_buffer_status_latched.empty  <= 1;
        end else begin
            if(enabled_cmd)begin
                write_command_out.valid     <= write_command_out_matrix_A_B.valid;
                write_data_0_out.valid      <= write_data_0_out_matrix_A_B.valid;
                write_data_1_out.valid      <= write_data_1_out_matrix_A_B.valid;
                read_command_out.valid      <= read_command_buffer_arbiter_out.valid;
                write_buffer_status_latched <= write_buffer_status;
                read_buffer_status_latched  <= read_buffer_status;
            end
        end
    end


    always_ff @(posedge clock or negedge rstn_output) begin
        if(~rstn_output) begin
            write_command_out.payload <= 0 ;
            write_data_0_out.payload  <= 0 ;
            write_data_1_out.payload  <= 0 ;
            read_command_out.payload  <= 0 ;
        end else begin
            write_command_out.payload <= write_command_out_matrix_A_B.payload ;
            write_data_0_out.payload  <= write_data_0_out_matrix_A_B.payload ;
            write_data_1_out.payload  <= write_data_1_out_matrix_A_B.payload ;
            read_command_out.payload  <= read_command_buffer_arbiter_out.payload ;
        end
    end

////////////////////////////////////////////////////////////////////////////
//Drive input
////////////////////////////////////////////////////////////////////////////

    always_ff @(posedge clock or negedge rstn_input) begin
        if(~rstn_input) begin
            wed_request_in_latched.valid       <= 0;
            read_response_in_latched.valid     <= 0;
            write_response_in_matrix_A_B.valid <= 0;
            read_data_0_in_latched.valid       <= 0;
            read_data_1_in_latched.valid       <= 0;
        end else begin
            if(enabled)begin
                wed_request_in_latched.valid       <= wed_request_in.valid;
                read_response_in_latched.valid     <= read_response_in.valid;
                write_response_in_matrix_A_B.valid <= write_response_in.valid;
                read_data_0_in_latched.valid       <= read_data_0_in.valid;
                read_data_1_in_latched.valid       <= read_data_1_in.valid;
            end
        end
    end

    always_ff @(posedge clock or negedge rstn_input) begin
        if(~rstn_input) begin
            wed_request_in_latched.payload       <= 0;
            read_response_in_latched.payload     <= 0;
            write_response_in_matrix_A_B.payload <= 0;
            read_data_0_in_latched.payload       <= 0;
            read_data_1_in_latched.payload       <= 0;
        end else begin
            wed_request_in_latched.payload       <= wed_request_in.payload;
            read_response_in_latched.payload     <= read_response_in.payload;
            write_response_in_matrix_A_B.payload <= write_response_in.payload;
            read_data_0_in_latched.payload       <= read_data_0_in.payload;
            read_data_1_in_latched.payload       <= read_data_1_in.payload;
        end
    end

    always_ff @(posedge clock or negedge rstn_input) begin
        if(~rstn_input) begin
            cu_configure_latched   <= 0;
            cu_configure_2_latched <= 0;
            cu_configure_3_latched <= 0;
            cu_configure_4_latched <= 0;
        end else begin
            if(enabled)begin
                if((|cu_configure.var1))
                    cu_configure_latched <= cu_configure.var1;

                if((|cu_configure.var2))
                    cu_configure_2_latched <= cu_configure.var2;

                if((|cu_configure.var3))
                    cu_configure_3_latched <= cu_configure.var3;

                if((|cu_configure.var4))
                    cu_configure_4_latched <= cu_configure.var4;
            end
        end
    end

    // assign ii_reg_limit = (cu_configure_2_latched[0:62]) + wed_request_in_latched.payload.wed.size_tile;
    // assign jj_reg_limit = (cu_configure_3_latched[0:62]) + wed_request_in_latched.payload.wed.size_tile;
    // assign kk_reg_limit = (cu_configure_4_latched[0:62]) + wed_request_in_latched.payload.wed.size_tile;

    // always_ff @(posedge clock or negedge rstn_input) begin
    //     if(~rstn_input) begin
    //         ii_reg_start         <= 0;
    //         jj_reg_start         <= 0;
    //         kk_reg_start         <= 0;
    //         ii_reg_end           <= 0;
    //         jj_reg_end           <= 0;
    //         kk_reg_end           <= 0;
    //         enabled_matrix_C_job <= 0;
    //         enabled_matrix_A_B   <= 0;
    //         enabled_cmd          <= 0;
    //     end else begin
    //         if(cu_ready) begin
    //             ii_reg_start         <= (cu_configure_2_latched[0:62]);
    //             jj_reg_start         <= (cu_configure_3_latched[0:62]);
    //             kk_reg_start         <= (cu_configure_4_latched[0:62]);
    //             ii_reg_end           <= (ii_reg_limit  < wed_request_in_latched.payload.wed.size_n) ? ii_reg_limit : wed_request_in_latched.payload.wed.size_n;
    //             jj_reg_end           <= (jj_reg_limit  < wed_request_in_latched.payload.wed.size_n) ? jj_reg_limit : wed_request_in_latched.payload.wed.size_n;
    //             kk_reg_end           <= (kk_reg_limit  < wed_request_in_latched.payload.wed.size_n) ? kk_reg_limit : wed_request_in_latched.payload.wed.size_n;
    //             enabled_matrix_C_job <= 1;
    //             enabled_matrix_A_B   <= 1;
    //             enabled_cmd          <= 1;
    //         end
    //     end
    // end

////////////////////////////////////////////////////////////////////////////
//Drive Read Prefetch
////////////////////////////////////////////////////////////////////////////

    always_ff @(posedge clock or negedge rstn_output) begin
        if(~rstn_output) begin
            prefetch_read_response_in_latched.valid <= 0;
            prefetch_read_command_out.valid         <= 0;
        end else begin
            if(enabled_prefetch_read)begin
                prefetch_read_response_in_latched.valid <= prefetch_read_response_in.valid;
                prefetch_read_command_out.valid         <= prefetch_read_command_out_latched.valid;
            end
        end
    end

    always_ff @(posedge clock) begin
        prefetch_read_response_in_latched.payload <= prefetch_read_response_in.payload;
        prefetch_read_command_out.payload         <= prefetch_read_command_out_latched.payload;
    end

////////////////////////////////////////////////////////////////////////////
//Drive Write Prefetch
////////////////////////////////////////////////////////////////////////////

    always_ff @(posedge clock or negedge rstn_output) begin
        if(~rstn_output) begin
            prefetch_write_response_in_latched.valid <= 0;
            prefetch_write_command_out.valid         <= 0;
        end else begin
            if(enabled_prefetch_write)begin
                prefetch_write_response_in_latched.valid <= prefetch_write_response_in.valid;
                prefetch_write_command_out.valid         <= prefetch_write_command_out_latched.valid;
            end
        end
    end

    always_ff @(posedge clock) begin
        prefetch_write_response_in_latched.payload <= prefetch_write_response_in.payload;
        prefetch_write_command_out.payload         <= prefetch_write_command_out_latched.payload;
    end

////////////////////////////////////////////////////////////////////////////
//cu_matrix_C_control - graph algorithm compute units arbitration
//read commands / data read commands / read reponses
////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////
//read response arbitration logic - input
////////////////////////////////////////////////////////////////////////////

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            read_response_in_matrix_C_job.valid <= 0;
            read_response_in_matrix_A_B.valid   <= 0;
        end else begin
            if(enabled && read_response_in_latched.valid) begin
                case (read_response_in_latched.payload.cmd.cu_id_x)
                    MATRIX_C_CONTROL_ID : begin
                        read_response_in_matrix_C_job.valid <= read_response_in_latched.valid;
                        read_response_in_matrix_A_B.valid   <= 0;
                    end
                    default : begin
                        read_response_in_matrix_A_B.valid   <= read_response_in_latched.valid;
                        read_response_in_matrix_C_job.valid <= 0;
                    end
                endcase
            end else begin
                read_response_in_matrix_C_job.valid <= 0;
                read_response_in_matrix_A_B.valid   <= 0;
            end
        end
    end

    always_ff @(posedge clock) begin
        read_response_in_matrix_C_job.payload <= read_response_in_latched.payload;
        read_response_in_matrix_A_B.payload   <= read_response_in_latched.payload;
    end

////////////////////////////////////////////////////////////////////////////
//read data request logic - input
////////////////////////////////////////////////////////////////////////////

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            read_data_0_in_matrix_C_job.valid <= 0;
            read_data_0_in_matrix_A_B.valid   <= 0;
        end else begin
            if(enabled && read_data_0_in_latched.valid) begin
                case (read_data_0_in_latched.payload.cmd.cu_id_x)
                    MATRIX_C_CONTROL_ID : begin
                        read_data_0_in_matrix_C_job.valid <= read_data_0_in_latched.valid;
                        read_data_0_in_matrix_A_B.valid   <= 0;
                    end
                    default : begin
                        read_data_0_in_matrix_A_B.valid   <= read_data_0_in_latched.valid;
                        read_data_0_in_matrix_C_job.valid <= 0;
                    end
                endcase
            end else begin
                read_data_0_in_matrix_C_job.valid <= 0;
                read_data_0_in_matrix_A_B.valid   <= 0;
            end
        end
    end

    always_ff @(posedge clock) begin
        read_data_0_in_matrix_C_job.payload <= read_data_0_in_latched.payload;
        read_data_0_in_matrix_A_B.payload   <= read_data_0_in_latched.payload;
    end


    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            read_data_1_in_matrix_C_job.valid <= 0;
            read_data_1_in_matrix_A_B.valid   <= 0;
        end else begin
            if(enabled && read_data_1_in_latched.valid) begin
                case (read_data_1_in_latched.payload.cmd.cu_id_x)
                    MATRIX_C_CONTROL_ID : begin
                        read_data_1_in_matrix_C_job.valid <= read_data_1_in_latched.valid;
                        read_data_1_in_matrix_A_B.valid   <= 0;
                    end
                    default : begin
                        read_data_1_in_matrix_A_B.valid   <= read_data_1_in_latched.valid;
                        read_data_1_in_matrix_C_job.valid <= 0;
                    end
                endcase
            end else begin
                read_data_1_in_matrix_C_job.valid <= 0;
                read_data_1_in_matrix_A_B.valid   <= 0;
            end
        end
    end

    always_ff @(posedge clock) begin
        read_data_1_in_matrix_C_job.payload <= read_data_1_in_latched.payload;
        read_data_1_in_matrix_A_B.payload   <= read_data_1_in_latched.payload;
    end

////////////////////////////////////////////////////////////////////////////
//read Buffer arbitration logic
////////////////////////////////////////////////////////////////////////////

    assign submit[0]   = read_command_buffer_arbiter_in[0].valid;
    assign submit[1]   = read_command_buffer_arbiter_in[1].valid;
    assign requests[1] = read_command_buffer_arbiter_in[1].valid;

    round_robin_priority_arbiter_N_input_1_ouput #(
        .NUM_REQUESTS(NUM_READ_REQUESTS       ),
        .WIDTH       ($bits(CommandBufferLine))
    ) read_command_buffer_arbiter_instant (
        .clock      (clock                          ),
        .rstn       (rstn                           ),
        .enabled    (enabled_cmd                    ),
        .buffer_in  (read_command_buffer_arbiter_in ),
        .submit     (submit                         ),
        .requests   (requests                       ),
        .arbiter_out(read_command_buffer_arbiter_out),
        .ready      (ready                          )
    );

////////////////////////////////////////////////////////////////////////////
//cu_matrix_C_control - matrix_C job queue generation
////////////////////////////////////////////////////////////////////////////

    genvar engine_x;
    genvar engine_y;
    generate
        for(engine_x = 0; engine_x < NUM_X_CU; engine_x = engine_x + 1) begin : matrix_engine_x
            for(engine_y = 0; engine_y < NUM_Y_CU; engine_y = engine_y + 1) begin : matrix_engine_y
                localparam int ENGINE_INDEX = engine_x * NUM_Y_CU + engine_y;

                assign matrix_engine_read_valid[ENGINE_INDEX] =
                    matrix_engine_read_command[ENGINE_INDEX].valid &&
                    matrix_engine_read_armed[ENGINE_INDEX];
                assign matrix_engine_write_valid[ENGINE_INDEX] =
                    matrix_engine_write_command[ENGINE_INDEX].valid &&
                    matrix_engine_write_armed[ENGINE_INDEX];

                cu_matrix_multiply_control #(
                    .ENGINE_X(engine_x),
                    .ENGINE_Y(engine_y),
                    .X_STRIDE(NUM_X_CU),
                    .Y_STRIDE(NUM_Y_CU),
                    .CU_ID_X(MATRIX_A_B_CONTROL_ID - engine_x),
                    .CU_ID_Y(MATRIX_A_B_CONTROL_ID - engine_y)
                ) matrix_multiply_control_instant (
                    .clock               (clock                                      ),
                    .rstn                (rstn                                       ),
                    .enabled_in          (enabled_matrix_A_B                         ),
                    .wed_request_in      (wed_request_in_latched                     ),
                    .cu_configure_2      (cu_configure_2_latched                     ),
                    .cu_configure_3      (cu_configure_3_latched                     ),
                    .cu_configure_4      (cu_configure_4_latched                     ),
                    .read_response_in    (read_response_in_matrix_A_B                ),
                    .read_data_0_in      (read_data_0_in_matrix_A_B                  ),
                    .read_data_1_in      (read_data_1_in_matrix_A_B                  ),
                    .read_buffer_status  (read_buffer_status_latched                 ),
                    .read_command_grant (matrix_engine_read_grant[ENGINE_INDEX]     ),
                    .write_response_in   (write_response_in_matrix_A_B               ),
                    .write_buffer_status (write_buffer_status_latched                ),
                    .write_command_grant(matrix_engine_write_grant[ENGINE_INDEX]    ),
                    .read_command_out    (matrix_engine_read_command[ENGINE_INDEX]   ),
                    .write_command_out   (matrix_engine_write_command[ENGINE_INDEX]  ),
                    .write_data_0_out    (matrix_engine_write_data_0[ENGINE_INDEX]   ),
                    .write_data_1_out    (matrix_engine_write_data_1[ENGINE_INDEX]   ),
                    .done_out            (matrix_engine_done[ENGINE_INDEX]           ),
                    .completed_writes_out(matrix_engine_completed_writes[ENGINE_INDEX]),
                    .multiply_terms_out  (matrix_engine_multiply_terms[ENGINE_INDEX] )
                );
            end
        end
    endgenerate

    assign matrix_C_request_unfiltered = 1'b1;

    cu_matrix_C_job_control cu_matrix_C_job_control_instant (
        .clock                   (clock                            ),
        .rstn                    (rstn                             ),
        .enabled_in              (enabled_matrix_C_job             ),
        .cu_configure_2          (cu_configure_2_latched           ),
        .cu_configure_3          (cu_configure_3_latched           ),
        .wed_request_in          (wed_request_in_latched           ),
        .read_response_in        (read_response_in_matrix_C_job    ),
        .read_data_0_in          (read_data_0_in_matrix_C_job      ),
        .read_data_1_in          (read_data_1_in_matrix_C_job      ),
        .read_buffer_status      (read_buffer_status_latched       ),
        .read_command_bus_grant  (ready[0]                         ),
        .read_command_bus_request(requests[0]                      ),
        .read_command_out        (read_command_buffer_arbiter_in[0]),
        .matrix_C_request        (matrix_C_request_unfiltered      ),
        .matrix_C_job_out        (matrix_C_unfiltered              )
    );


    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            matrix_A_B_job_counter_done <= 0;
            matrix_C_job_counter_done   <= 0;
        end else begin
            matrix_A_B_job_counter_done <= matrix_engine_terms_sum;
            matrix_C_job_counter_done   <= matrix_engine_completed_sum;
        end
    end

endmodule