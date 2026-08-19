import AFU_PKG::*;

bind cached_afu accelerator_verification #(
`ifdef CAPI_PRECIS_VERIFY_ALL_CONFIG_WORDS
    .REQUIRED_CU_CONFIG_MASK(4'b1111),
`else
    .REQUIRED_CU_CONFIG_MASK(4'b1101),
`endif
    .CHECK_TARGET(1'b0)
) accelerator_verification_instant (
    .clock              (clock),
    .rstn               (reset_afu_internal),
    .enabled            (enabled),
    .reset_done         (reset_done),
    .cu_done            (cu_done),
    .cu_return_done_ack (cu_return_done_ack),
    .completion_valid   (done_control_instant.current_state == DONE_MMIO_REQ),
    .report_errors      (report_errors),
    .afu_status         (afu_status),
    .cu_status          (cu_status),
    .afu_configure_1    (afu_configure.var1),
    .cu_configure_1     (cu_configure.var1),
    .cu_configure_2     (cu_configure.var2),
    .cu_configure_3     (cu_configure.var3),
    .cu_configure_4     (cu_configure.var4),
    .cu_return_1        (cu_return.var1),
    .cu_return_2        (cu_return.var2),
    .cu_return_done_1   (cu_return_done.var1),
    .cu_return_done_2   (cu_return_done.var2),
    .target_valid       (1'b0),
    .target_count       (32'b0),
    .failure_count      (),
    .cover_mask         ()
);
