`timescale 1ns/1ps

module accelerator_verification #(
    parameter int unsigned CONFIG_BOUND_CYCLES = 1000000,
    parameter int unsigned STALL_BOUND_CYCLES  = 10000000,
    parameter int unsigned DONE_BOUND_CYCLES   = 1024,
    parameter int unsigned ACK_BOUND_CYCLES    = 100000000,
    parameter int unsigned RESET_BOUND_CYCLES  = 1024,
    parameter logic [3:0] REQUIRED_CU_CONFIG_MASK = 4'b1101,
    parameter bit          CHECK_TARGET        = 1'b0,
    parameter bit          REPORT_FAILURES     = 1'b1
) (
    input  logic        clock,
    input  logic        rstn,
    input  logic        enabled,
    input  logic        reset_done,
    input  logic        cu_done,
    input  logic        cu_return_done_ack,
    input  logic        completion_valid,
    input  logic [0:63] report_errors,
    input  logic [0:63] afu_status,
    input  logic [0:63] cu_status,
    input  logic [0:63] afu_configure_1,
    input  logic [0:63] cu_configure_1,
    input  logic [0:63] cu_configure_2,
    input  logic [0:63] cu_configure_3,
    input  logic [0:63] cu_configure_4,
    input  logic [0:63] cu_return_1,
    input  logic [0:63] cu_return_2,
    input  logic [0:63] cu_return_done_1,
    input  logic [0:63] cu_return_done_2,
    input  logic        target_valid,
    input  logic [31:0] target_count,
    output logic [31:0] failure_count,
    output logic [31:0] cover_mask
);

    localparam int unsigned COVER_AFU_CONFIG = 0;
    localparam int unsigned COVER_CU_CONFIG  = 1;
    localparam int unsigned COVER_PROGRESS   = 2;
    localparam int unsigned COVER_CU_DONE    = 3;
    localparam int unsigned COVER_PUBLISHED  = 4;
    localparam int unsigned COVER_ACK        = 5;
    localparam int unsigned COVER_RESET      = 6;
    localparam int unsigned COVER_ERROR      = 7;

    typedef enum logic [1:0] {
        VERIFY_DONE_IDLE,
        VERIFY_DONE_PUBLISH,
        VERIFY_DONE_ACK,
        VERIFY_DONE_CLEAR
    } verification_done_state_type;

    verification_done_state_type verification_state;

    logic        afu_config_pending;
    logic        cu_config_pending;
    logic        cu_status_seen;
    logic        cu_config_complete;
    logic        config_incomplete_reported;
    logic        progress_valid;
    logic        active_job;
    logic        stall_reported;
    logic        status_loss_reported;
    logic        error_reported;
    logic        saw_reset_request;
    logic        cu_done_previous;
    logic [0:63] cu_status_previous;
    logic [0:63] expected_afu_config;
    logic [0:63] expected_cu_config_1;
    logic [0:63] expected_cu_config_2;
    logic [0:63] expected_cu_config_3;
    logic [0:63] expected_cu_config_4;
    logic [3:0]  cu_config_seen;
    logic [0:63] last_return_1;
    logic [0:63] last_return_2;
    logic [0:63] final_return_1;
    logic [0:63] final_return_2;
    logic [0:63] held_done_1;
    logic [0:63] held_done_2;
    logic [0:63] target_count_extended;
    int unsigned afu_config_age;
    int unsigned cu_config_age;
    int unsigned stall_age;
    int unsigned done_age;
    int unsigned ack_age;
    int unsigned reset_age;

    logic [3:0] cu_config_pulse;
    logic [3:0] cu_config_observed;
    logic       cu_config_required_observed;
    bit         monitor_initialized = 1'b0;
    bit         verification_fatal = 1'b1;
    integer     verification_fatal_value;

    task automatic record_failure(input string message);
        begin
            failure_count <= failure_count + 1'b1;
            if(REPORT_FAILURES) begin
                if(verification_fatal)
                    $fatal(1, "accelerator_verification: %s", message);
                else
                    $error("accelerator_verification: %s", message);
            end
        end
    endtask

    initial begin
        if($value$plusargs("VERIF_FATAL=%d", verification_fatal_value))
            verification_fatal = verification_fatal_value != 0;
    end

    assign target_count_extended = {32'b0, target_count};
    assign cu_config_pulse = {
        |cu_configure_4,
        |cu_configure_3,
        |cu_configure_2,
        |cu_configure_1
    };
    assign cu_config_observed = cu_config_seen | cu_config_pulse;
    assign cu_config_required_observed =
        ((cu_config_observed & REQUIRED_CU_CONFIG_MASK) ==
         REQUIRED_CU_CONFIG_MASK);

    always @(posedge clock or negedge rstn) begin
        if($isunknown(rstn)) begin
        end else if(!rstn || !monitor_initialized) begin
            monitor_initialized   <= 1'b1;
            failure_count       <= 0;
            cover_mask          <= 0;
            verification_state          <= VERIFY_DONE_IDLE;
            afu_config_pending  <= 0;
            cu_config_pending   <= 0;
            cu_status_seen      <= 0;
            cu_config_complete  <= 0;
            config_incomplete_reported <= 0;
            progress_valid      <= 0;
            active_job          <= 0;
            stall_reported      <= 0;
            status_loss_reported <= 0;
            error_reported      <= 0;
            saw_reset_request   <= 0;
            cu_done_previous    <= 0;
            cu_status_previous  <= 0;
            expected_afu_config <= 0;
            expected_cu_config_1 <= 0;
            expected_cu_config_2 <= 0;
            expected_cu_config_3 <= 0;
            expected_cu_config_4 <= 0;
            cu_config_seen       <= 0;
            last_return_1       <= 0;
            last_return_2       <= 0;
            final_return_1      <= 0;
            final_return_2      <= 0;
            held_done_1         <= 0;
            held_done_2         <= 0;
            afu_config_age      <= 0;
            cu_config_age       <= 0;
            stall_age           <= 0;
            done_age            <= 0;
            ack_age             <= 0;
            reset_age           <= 0;
        end else begin
            cu_done_previous <= cu_done;
            cu_status_previous <= cu_status;

            if($isunknown(enabled))
                record_failure("unknown accelerator enable state");
            else if(enabled &&
                    $isunknown({
                   reset_done,
                   cu_done,
                   cu_return_done_ack,
                   completion_valid,
                   report_errors,
                   afu_status,
                   cu_status,
                   afu_configure_1,
                   cu_configure_1,
                   cu_configure_2,
                   cu_configure_3,
                   cu_configure_4,
                   cu_return_1,
                   cu_return_2,
                   cu_return_done_1,
                   cu_return_done_2
               }))
                record_failure("unknown value on the accelerator control path");

            if(CHECK_TARGET && $isunknown(target_valid))
                record_failure("unknown graph target-valid state");
            else if(CHECK_TARGET &&
                    target_valid &&
                    $isunknown(target_count))
                record_failure("unknown graph target count");

            if(|report_errors) begin
                cover_mask[COVER_ERROR] <= 1'b1;
                if(!error_reported) begin
                    record_failure("RTL error register asserted");
                    error_reported <= 1'b1;
                end
            end else begin
                error_reported <= 1'b0;
            end

            if(|afu_configure_1) begin
                if(!afu_config_pending) begin
                    expected_afu_config <= afu_configure_1;
                    afu_config_age      <= 0;
                    if(afu_status == afu_configure_1)
                        cover_mask[COVER_AFU_CONFIG] <= 1'b1;
                    else
                        afu_config_pending <= 1'b1;
                end else if(expected_afu_config != afu_configure_1) begin
                    record_failure("AFU configuration changed before acceptance");
                end
            end

            if(afu_config_pending) begin
                if(afu_status == expected_afu_config) begin
                    afu_config_pending           <= 1'b0;
                    afu_config_age               <= 0;
                    cover_mask[COVER_AFU_CONFIG] <= 1'b1;
                end else if(afu_config_age >= CONFIG_BOUND_CYCLES) begin
                    record_failure("AFU configuration acceptance timeout");
                    afu_config_pending <= 1'b0;
                end else begin
                    afu_config_age <= afu_config_age + 1'b1;
                end
            end

            if(|cu_config_pulse) begin
                if(active_job && cu_config_complete) begin
                    if(cu_config_pulse[0] &&
                       (expected_cu_config_1 != cu_configure_1))
                        record_failure("CU configuration word 1 changed during an active job");
                    if(cu_config_pulse[1] &&
                       (expected_cu_config_2 != cu_configure_2))
                        record_failure("CU configuration word 2 changed during an active job");
                    if(cu_config_pulse[2] &&
                       (expected_cu_config_3 != cu_configure_3))
                        record_failure("CU configuration word 3 changed during an active job");
                    if(cu_config_pulse[3] &&
                       (expected_cu_config_4 != cu_configure_4))
                        record_failure("CU configuration word 4 changed during an active job");
                end

                if(!cu_config_pending) begin
                    cu_config_pending <= 1'b1;
                    cu_config_age     <= 0;
                    cu_config_seen    <= cu_config_pulse;
                    cu_status_seen    <= |cu_status;
                    if(!active_job) begin
                        cu_config_complete         <= 1'b0;
                        config_incomplete_reported <= 1'b0;
                    end
                end else begin
                    cu_config_seen <= cu_config_observed;
                end

                if(cu_config_pulse[0]) begin
                    if(cu_config_seen[0] &&
                       (expected_cu_config_1 != cu_configure_1))
                        record_failure("CU configuration word 1 changed before acceptance");
                    expected_cu_config_1 <= cu_configure_1;
                end

                if(cu_config_pulse[1]) begin
                    if(cu_config_seen[1] &&
                       (expected_cu_config_2 != cu_configure_2))
                        record_failure("CU configuration word 2 changed before acceptance");
                    expected_cu_config_2 <= cu_configure_2;
                end

                if(cu_config_pulse[2]) begin
                    if(cu_config_seen[2] &&
                       (expected_cu_config_3 != cu_configure_3))
                        record_failure("CU configuration word 3 changed before acceptance");
                    expected_cu_config_3 <= cu_configure_3;
                end

                if(cu_config_pulse[3]) begin
                    if(cu_config_seen[3] &&
                       (expected_cu_config_4 != cu_configure_4))
                        record_failure("CU configuration word 4 changed before acceptance");
                    expected_cu_config_4 <= cu_configure_4;
                end
            end

            if(|cu_status)
                cu_status_seen <= 1'b1;

            if((|cu_status) && !(|cu_status_previous)) begin
                active_job           <= 1'b1;
                progress_valid       <= 1'b0;
                status_loss_reported <= 1'b0;
            end

            if(cu_config_pending) begin
                if(cu_config_required_observed)
                    cu_config_complete <= 1'b1;

                if(cu_config_required_observed &&
                   (cu_status_seen || (|cu_status))) begin
                    cover_mask[COVER_CU_CONFIG] <= 1'b1;
                    cu_config_pending <= 1'b0;
                    cu_config_age     <= 0;
                    cu_config_seen    <= 0;
                end else if(cu_config_age >= CONFIG_BOUND_CYCLES) begin
                    record_failure("CU configuration acceptance timeout");
                    cu_config_pending <= 1'b0;
                    cu_config_seen    <= 0;
                end else begin
                    cu_config_age <= cu_config_age + 1'b1;
                end
            end

            if(active_job && (verification_state == VERIFY_DONE_IDLE)) begin
                if(!(|cu_status) && !cu_done) begin
                    if(!status_loss_reported) begin
                        record_failure("CU status cleared before completion");
                        status_loss_reported <= 1'b1;
                    end
                end else begin
                    status_loss_reported <= 1'b0;

                    if(progress_valid &&
                       ((cu_return_1 < last_return_1) ||
                        (cu_return_2 < last_return_2)))
                        record_failure("CU progress counter decreased");

                    if(!progress_valid) begin
                        progress_valid <= 1'b1;
                        stall_age      <= 0;
                        stall_reported <= 1'b0;
                    end else if((cu_return_1 != last_return_1) ||
                                (cu_return_2 != last_return_2)) begin
                        if(!cu_config_complete &&
                           !cu_config_required_observed &&
                           !config_incomplete_reported) begin
                            record_failure("CU progressed before required configuration words");
                            config_incomplete_reported <= 1'b1;
                        end
                        stall_age                  <= 0;
                        stall_reported              <= 1'b0;
                        cover_mask[COVER_PROGRESS]  <= 1'b1;
                    end else if(stall_age >= STALL_BOUND_CYCLES) begin
                        if(!stall_reported) begin
                            record_failure("CU progress stalled");
                            stall_reported <= 1'b1;
                        end
                    end else begin
                        stall_age <= stall_age + 1'b1;
                    end

                    if(CHECK_TARGET &&
                       target_valid &&
                       (cu_return_1 > target_count_extended))
                        record_failure("CU progress exceeded the workload target");

                    last_return_1 <= cu_return_1;
                    last_return_2 <= cu_return_2;
                end
            end else begin
                progress_valid <= 1'b0;
                stall_age      <= 0;
                stall_reported <= 1'b0;
                last_return_1  <= cu_return_1;
                last_return_2  <= cu_return_2;
            end

            if(cu_return_done_ack && (verification_state != VERIFY_DONE_ACK))
                record_failure("completion acknowledgement outside the published-result state");

            case(verification_state)
                VERIFY_DONE_IDLE: begin
                    if(cu_done && !cu_done_previous) begin
                        if(!cu_config_complete &&
                           !cu_config_required_observed &&
                           !config_incomplete_reported) begin
                            record_failure("CU completed before required configuration words");
                            config_incomplete_reported <= 1'b1;
                        end
                        active_job                <= 1'b0;
                        final_return_1            <= cu_return_1;
                        final_return_2            <= cu_return_2;
                        done_age                  <= 0;
                        saw_reset_request         <= 1'b0;
                        verification_state                <= VERIFY_DONE_PUBLISH;
                        cover_mask[COVER_CU_DONE] <= 1'b1;

                        if(CHECK_TARGET &&
                           target_valid &&
                           (cu_return_1 != target_count_extended))
                            record_failure("CU completion did not match the workload target");
                    end
                end

                VERIFY_DONE_PUBLISH: begin
                    if(!reset_done)
                        saw_reset_request <= 1'b1;

                    if(saw_reset_request &&
                       reset_done &&
                       completion_valid &&
                       (cu_return_done_1 == final_return_1) &&
                       (cu_return_done_2 == final_return_2)) begin
                        held_done_1                  <= cu_return_done_1;
                        held_done_2                  <= cu_return_done_2;
                        ack_age                      <= 0;
                        verification_state                   <= VERIFY_DONE_ACK;
                        cover_mask[COVER_PUBLISHED]  <= 1'b1;
                    end else if(done_age >= DONE_BOUND_CYCLES) begin
                        record_failure("CU completion publication timeout");
                        verification_state <= VERIFY_DONE_IDLE;
                    end else begin
                        done_age <= done_age + 1'b1;
                    end
                end

                VERIFY_DONE_ACK: begin
                    if(!cu_return_done_ack &&
                       ((cu_return_done_1 != held_done_1) ||
                        (cu_return_done_2 != held_done_2))) begin
                        record_failure("published completion changed before acknowledgement");
                        verification_state <= VERIFY_DONE_IDLE;
                    end else if(cu_return_done_ack) begin
                        reset_age               <= 0;
                        verification_state              <= VERIFY_DONE_CLEAR;
                        cover_mask[COVER_ACK]   <= 1'b1;
                    end else if(ack_age >= ACK_BOUND_CYCLES) begin
                        record_failure("CU completion acknowledgement timeout");
                        verification_state <= VERIFY_DONE_IDLE;
                    end else begin
                        ack_age <= ack_age + 1'b1;
                    end
                end

                VERIFY_DONE_CLEAR: begin
                    if(!(|cu_return_done_1) &&
                       !(|cu_return_done_2) &&
                       !(|cu_status)) begin
                        verification_state                <= VERIFY_DONE_IDLE;
                        cover_mask[COVER_RESET]   <= 1'b1;
                    end else if(reset_age >= RESET_BOUND_CYCLES) begin
                        record_failure("CU completion reset timeout");
                        verification_state <= VERIFY_DONE_IDLE;
                    end else begin
                        reset_age <= reset_age + 1'b1;
                    end
                end

                default: verification_state <= VERIFY_DONE_IDLE;
            endcase
        end
    end

endmodule
