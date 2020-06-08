// -----------------------------------------------------------------------------
//
//      "ACCEL-GRAPH Shared Memory Accelerator Project"
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
    logic [ 0:(ARRAY_SIZE_BITS-1)] matrix_C_job_counter_filtered                         ;
    logic [NUM_READ_REQUESTS-1:0] submit                                                ;
    logic [NUM_READ_REQUESTS-1:0] requests                                              ;
    logic [NUM_READ_REQUESTS-1:0] ready                                                 ;
    CommandBufferLine             read_command_buffer_arbiter_in [0:NUM_READ_REQUESTS-1];
    CommandBufferLine             read_command_buffer_arbiter_out                       ;

    // vertex control variables

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

    logic                        done_algorithm                    ;
    logic [0:(ARRAY_SIZE_BITS-1)] matrix_C_job_counter_done         ;
    logic [0:(ARRAY_SIZE_BITS-1)] matrix_A_B_job_counter_done        ;
    logic [0:(ARRAY_SIZE_BITS-1)] matrix_C_job_counter_done_latched ;
    logic [0:(ARRAY_SIZE_BITS-1)] matrix_A_B_job_counter_done_latched;
    logic [0:(ARRAY_SIZE_BITS-1)] matrix_C_job_counter_total_latched;

    logic           enabled                  ;
    logic           enabled_cmd              ;
    logic           enabled_matrix_C_job     ;
    logic           enabled_matrix_A_B       ;
    logic           cu_ready                 ;
    VertexInterface vertex_unfiltered        ;
    logic           vertex_request_unfiltered;

    ResponseBufferLine prefetch_read_response_in_latched;
    CommandBufferLine  prefetch_read_command_out_latched;

    ResponseBufferLine prefetch_write_response_in_latched;
    CommandBufferLine  prefetch_write_command_out_latched;

    logic enabled_prefetch_read ;
    logic enabled_prefetch_write;

    logic write_command_bus_grant  ;
    logic write_command_bus_request;

////////////////////////////////////////////////////////////////////////////
// logic
////////////////////////////////////////////////////////////////////////////

    assign  write_command_out_matrix_A_B = 0;
    assign  write_data_0_out_matrix_A_B = 0;
    assign  write_data_1_out_matrix_A_B = 0;
    assign  read_command_buffer_arbiter_in[1] = 0;
    assign  write_command_bus_request = 0;


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
            enabled_matrix_C_job   <= 0;
            enabled_prefetch_read  <= 0;
            enabled_prefetch_write <= 0;
        end else begin
            enabled              <= enabled_in;
            enabled_matrix_C_job <= cu_ready;
            enabled_matrix_A_B   <= cu_ready;
            enabled_cmd          <= cu_ready;
            // enabled_prefetch_read  <= cu_ready && cu_configure_latched[30];
            // enabled_prefetch_write <= cu_ready && cu_configure_latched[31];

            enabled_prefetch_read  <= 0;
            enabled_prefetch_write <= 0;
        end
    end

    assign cu_ready = (|cu_configure_latched) && wed_request_in_latched.valid;

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
            if(enabled_matrix_C_job)begin
                cu_return_latched.var1 <= matrix_C_job_counter_total_latched;
                cu_return_latched.var2 <= matrix_A_B_job_counter_done_latched;
                done_algorithm         <= (wed_request_in_latched.payload.wed.num_vertices == matrix_C_job_counter_total_latched) && (wed_request_in_latched.payload.wed.num_edges == matrix_A_B_job_counter_done_latched);
            end
        end
    end

    always_ff @(posedge clock or negedge rstn) begin
        if(~rstn) begin
            cu_return                          <= 0;
            cu_status                          <= 0;
            cu_done                            <= 0;
            matrix_C_job_counter_done_latched  <= 0;
            matrix_A_B_job_counter_done_latched <= 0;
            matrix_C_job_counter_total_latched <= 0;
        end else begin
            if(enabled)begin
                cu_return                          <= cu_return_latched;
                cu_done                            <= done_algorithm;
                cu_status                          <= cu_configure_latched;
                matrix_C_job_counter_done_latched  <= matrix_C_job_counter_done;
                matrix_A_B_job_counter_done_latched <= matrix_A_B_job_counter_done;
                matrix_C_job_counter_total_latched <= matrix_C_job_counter_done_latched + matrix_C_job_counter_filtered;
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
        end else begin
            if(enabled)begin
                if((|cu_configure.var1))
                    cu_configure_latched <= cu_configure.var1;

                if((|cu_configure.var2))
                    cu_configure_2_latched <= cu_configure.var2;
            end
        end
    end

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
//cu_vertex_control - graph algorithm compute units arbitration
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
                    VERTEX_CONTROL_ID : begin
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
                    VERTEX_CONTROL_ID : begin
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
                    VERTEX_CONTROL_ID : begin
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

    assign submit[0] = read_command_buffer_arbiter_in[0].valid;
    assign submit[1] = read_command_buffer_arbiter_in[1].valid;

    round_robin_priority_arbiter_N_input_1_ouput #(
        .NUM_REQUESTS(NUM_READ_REQUESTS       ),
        .WIDTH       ($bits(CommandBufferLine))
    ) read_command_buffer_arbiter_instant (
        .clock      (clock                          ),
        .rstn       (rstn                           ),
        .enabled    (enabled_matrix_C_job           ),
        .buffer_in  (read_command_buffer_arbiter_in ),
        .submit     (submit                         ),
        .requests   (requests                       ),
        .arbiter_out(read_command_buffer_arbiter_out),
        .ready      (ready                          )
    );

////////////////////////////////////////////////////////////////////////////
//cu_vertex_control - vertex job queue generation
////////////////////////////////////////////////////////////////////////////

    cu_matrix_C_job_control cu_matrix_C_job_control_instant (
        .clock                   (clock                            ),
        .rstn                    (rstn                             ),
        .enabled_in              (enabled_matrix_C_job             ),
        .cu_configure            (cu_configure_latched             ),
        .wed_request_in          (wed_request_in_latched           ),
        .read_response_in        (read_response_in_matrix_C_job    ),
        .read_data_0_in          (read_data_0_in_matrix_C_job      ),
        .read_data_1_in          (read_data_1_in_matrix_C_job      ),
        .read_buffer_status      (read_buffer_status_latched       ),
        .vertex_request          (vertex_request_unfiltered        ),
        .read_command_bus_grant  (ready[0]                         ),
        .read_command_bus_request(requests[0]                      ),
        .read_command_out        (read_command_buffer_arbiter_in[0]),
        .vertex                  (vertex_unfiltered                )
    );



endmodule