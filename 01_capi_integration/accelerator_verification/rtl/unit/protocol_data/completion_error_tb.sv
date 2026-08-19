// completion-error family: done_control.sv and error_control.sv
//
// Independent model: two cycle accurate lifecycle models. The completion model
// owns the snapshot, publish, acknowledge and reset request sequence together
// with the soft reset edge detector. The error model owns the sticky error
// snapshot, its stable publication and the acknowledge driven reset request.
// Both models keep their own state enumeration and transition table, and both
// are driven only from the sampled interface trace.
//
// Sampling contract, cycle c is the interval closed by the posedge that samples
// it:
//   * outputs published during cycle c+1 are produced by the state and the
//     inputs of cycle c.
//   * state advances only while the block is enabled, the asynchronous reset
//     forces the reset state in the cycle it is asserted.

import GLOBALS_AFU_PKG::*;
import AFU_PKG::*;

module completion_error_tb (
  input  logic        clock   ,
  output logic        finished,
  output int unsigned checks  ,
  output int unsigned bin_hits,
  output int unsigned stalls
);

  // Named bounded stall profiles.
  localparam int unsigned STALL_SOFT_RESET_DELAY = 7 ;
  localparam int unsigned STALL_ACK_DELAY        = 9 ;
  localparam int unsigned STALL_ACK_ABSENT       = 15;
  localparam int unsigned STALL_ENABLE_LOW       = 5 ;
  localparam int unsigned STALL_RESET_LOW        = 6 ;
  localparam int unsigned STALL_PROFILES         = 5 ;
  localparam int unsigned DRAIN_CYCLES           = 8 ;
  localparam int unsigned PROGRESS_BOUND         = 96;

  typedef enum int unsigned {
    D_RESET        ,
    D_IDLE         ,
    D_RESET_REQUEST,
    D_RESET_PENDING,
    D_PUBLISH
  } done_model_t;

  typedef enum int unsigned {
    E_RESET        ,
    E_IDLE         ,
    E_PUBLISH      ,
    E_RESET_REQUEST,
    E_RESET_PENDING
  } error_model_t;

  logic                      rstn_in                  ;
  logic                      enabled_in               ;
  logic                      soft_rstn                ;
  cu_return_type             cu_return                ;
  ResponseStatistcsInterface response_statistics       ;
  logic                      cu_done                  ;
  logic                      cu_return_done_ack       ;
  logic                      reset_done               ;
  cu_return_type             cu_return_done           ;
  ResponseStatistcsInterface report_response_statistics;

  logic [0:63] external_errors  ;
  logic        report_errors_ack;
  logic        reset_error      ;
  logic [0:63] report_errors    ;

  done_control done_dut (
    .clock                    (clock                    ),
    .rstn_in                  (rstn_in                  ),
    .soft_rstn                (soft_rstn                ),
    .enabled_in               (enabled_in               ),
    .cu_return                (cu_return                ),
    .response_statistics      (response_statistics      ),
    .cu_done                  (cu_done                  ),
    .cu_return_done_ack       (cu_return_done_ack       ),
    .reset_done               (reset_done               ),
    .cu_return_done           (cu_return_done           ),
    .report_response_statistics(report_response_statistics)
  );

  error_control error_dut (
    .clock            (clock            ),
    .rstn_in          (rstn_in          ),
    .enabled_in       (enabled_in       ),
    .external_errors  (external_errors  ),
    .report_errors_ack(report_errors_ack),
    .reset_error      (reset_error      ),
    .report_errors    (report_errors    )
  );

////////////////////////////////////////////////////////////////////////////
// model state
////////////////////////////////////////////////////////////////////////////

  done_model_t  model_done_state ;
  error_model_t model_error_state;

  cu_return_type             done_latched_return;
  ResponseStatistcsInterface done_latched_stats ;

  logic                      expect_reset_done        ;
  cu_return_type             expect_cu_return_done    ;
  ResponseStatistcsInterface expect_report_statistics ;
  logic                      expect_reset_error       ;
  logic [0:63]               expect_report_errors     ;
  logic                      done_outputs_known       ;
  logic                      error_outputs_known      ;

  logic model_next_soft;
  logic model_prev_soft;
  logic model_done_soft;

  logic rstn_previous;
  logic rstn_reg     ;
  logic rstn_reg_last;
  logic enabled_last ;

  int unsigned cycle   ;
  logic        checking;
  string       phase   ;

  bit bin_done_state      [0:4];
  bit bin_done_transition [0:7];
  bit bin_done_value      [0:1];
  bit bin_done_ack        [0:2];
  bit bin_done_reset      [0:2];
  bit bin_done_freeze     [0:0];
  bit bin_error_state     [0:4];
  bit bin_error_transition[0:6];
  bit bin_error_class     [0:2];
  bit bin_error_ack       [0:2];
  bit bin_error_sticky    [0:0];
  bit bin_error_reset     [0:1];
  bit bin_error_freeze    [0:0];
  bit bin_overlap         [0:0];
  bit stall_used          [0:4];

////////////////////////////////////////////////////////////////////////////
// diagnostics
////////////////////////////////////////////////////////////////////////////

  task automatic fail(input string reason);
    $error(
      "completion_error mismatch reason=%s phase=%s cycle=%0d done_state=%s error_state=%s",
      reason,
      phase,
      cycle,
      model_done_state.name(),
      model_error_state.name()
    );
    $fatal(1);
  endtask

////////////////////////////////////////////////////////////////////////////
// model and checker
////////////////////////////////////////////////////////////////////////////

  always @(posedge clock) begin
    done_model_t  done_next ;
    error_model_t error_next;
    logic         enabled_now;

    rstn_reg_last = rstn_reg;
    rstn_reg      = rstn_in ? rstn_previous : 1'b0;
    enabled_now   = (rstn_reg && rstn_reg_last) ? enabled_last : 1'b0;
    cycle++;

    if(!rstn_reg) begin
      if(model_done_state != D_RESET)
        bin_done_reset[
          model_done_state == D_IDLE ? 0 :
          model_done_state == D_PUBLISH ? 1 : 2
        ] = 1;
      if(model_error_state != E_RESET)
        bin_error_reset[model_error_state == E_IDLE ? 0 : 1] = 1;
      model_done_state      = D_RESET;
      model_error_state     = E_RESET;
      model_next_soft = 1'b0;
      model_prev_soft = 1'b0;
      model_done_soft = 1'b0;
    end

    // -------------------------------------------------------------------
    // compare the outputs published in this cycle
    // -------------------------------------------------------------------
    if(checking && done_outputs_known) begin
      checks++;
      if(reset_done !== expect_reset_done)
        fail("completion reset request");
      checks++;
      if(cu_return_done !== expect_cu_return_done)
        fail("completion publication");
      checks++;
      if(report_response_statistics !== expect_report_statistics)
        fail("completion statistics publication");
    end
    if(checking && error_outputs_known) begin
      checks++;
      if(reset_error !== expect_reset_error)
        fail("error reset request");
      checks++;
      if(report_errors !== expect_report_errors)
        fail("error publication");
    end

    // -------------------------------------------------------------------
    // outputs that this cycle produces for the next cycle
    // -------------------------------------------------------------------
    case (model_done_state)
      D_RESET : begin
        expect_cu_return_done    = '0;
        done_latched_return      = '0;
        done_latched_stats       = '0;
        expect_report_statistics = '0;
        expect_reset_done        = 1'b1;
        done_outputs_known       = 1'b1;
      end
      D_IDLE : begin
        expect_cu_return_done    = '0;
        done_latched_return      = cu_return;
        expect_report_statistics = response_statistics;
        done_latched_stats       = response_statistics;
        expect_reset_done        = 1'b1;
      end
      D_RESET_REQUEST : begin
        expect_reset_done = 1'b0;
      end
      D_RESET_PENDING : begin
        expect_reset_done = 1'b1;
      end
      D_PUBLISH : begin
        expect_cu_return_done    = done_latched_return;
        expect_report_statistics = done_latched_stats;
      end
    endcase

    case (model_error_state)
      E_RESET : begin
        expect_report_errors = 64'h0;
        expect_reset_error   = 1'b1;
        error_outputs_known  = 1'b1;
      end
      E_IDLE : begin
        expect_report_errors = external_errors;
        expect_reset_error   = 1'b1;
      end
      E_PUBLISH : begin
      end
      E_RESET_REQUEST : begin
        expect_reset_error = 1'b0;
      end
      E_RESET_PENDING : begin
        expect_reset_error = 1'b1;
      end
    endcase

    // -------------------------------------------------------------------
    // transitions
    // -------------------------------------------------------------------
    done_next = model_done_state;
    case (model_done_state)
      D_RESET : done_next = D_IDLE;
      D_IDLE : begin
        if(cu_done)
          done_next = D_RESET_REQUEST;
      end
      D_RESET_REQUEST : done_next = D_RESET_PENDING;
      D_RESET_PENDING : begin
        if(model_done_soft)
          done_next = D_PUBLISH;
      end
      D_PUBLISH : begin
        if(cu_return_done_ack)
          done_next = D_IDLE;
      end
    endcase

    error_next = model_error_state;
    case (model_error_state)
      E_RESET : error_next = E_IDLE;
      E_IDLE : begin
        if(|external_errors)
          error_next = E_PUBLISH;
      end
      E_PUBLISH : begin
        if(report_errors_ack)
          error_next = E_RESET_REQUEST;
      end
      E_RESET_REQUEST : error_next = E_RESET_PENDING;
      E_RESET_PENDING : error_next = E_IDLE;
    endcase

    if(checking) begin
      bin_done_state[int'(model_done_state)]   = 1;
      bin_error_state[int'(model_error_state)] = 1;
      if(enabled_now) begin
        case (model_done_state)
          D_RESET : bin_done_transition[0] = 1;
          D_IDLE : bin_done_transition[(done_next == D_IDLE) ? 1 : 2] = 1;
          D_RESET_REQUEST : bin_done_transition[3] = 1;
          D_RESET_PENDING : bin_done_transition[(done_next == D_RESET_PENDING) ? 4 : 5] = 1;
          D_PUBLISH : bin_done_transition[(done_next == D_PUBLISH) ? 6 : 7] = 1;
        endcase
        case (model_error_state)
          E_RESET : bin_error_transition[0] = 1;
          E_IDLE : bin_error_transition[(error_next == E_IDLE) ? 1 : 2] = 1;
          E_PUBLISH : bin_error_transition[(error_next == E_PUBLISH) ? 3 : 4] = 1;
          E_RESET_REQUEST : bin_error_transition[5] = 1;
          E_RESET_PENDING : bin_error_transition[6] = 1;
        endcase
      end else begin
        if(model_done_state != D_RESET)
          bin_done_freeze[0] = 1;
        if(model_error_state != E_RESET)
          bin_error_freeze[0] = 1;
      end
      if(model_done_state == D_IDLE && cu_done)
        bin_done_value[(|cu_return) ? 1 : 0] = 1;
      if(model_error_state == E_IDLE && (|external_errors))
        bin_error_class[($countones(external_errors) > 1) ? 1 : 0] = 1;
      if(model_error_state == E_PUBLISH && (|external_errors) &&
         (external_errors != expect_report_errors))
        bin_error_sticky[0] = 1;
      if(model_done_state == D_IDLE && cu_done && (|external_errors) &&
         model_error_state == E_IDLE)
        bin_overlap[0] = 1;
    end

    if(rstn_reg && enabled_now) begin
      model_done_state  = done_next;
      model_error_state = error_next;
    end

    if(rstn_reg) begin
      model_done_soft = (~model_prev_soft) && model_next_soft;
      model_prev_soft = model_next_soft;
      model_next_soft = soft_rstn;
    end

    rstn_previous = rstn_in;
    enabled_last  = enabled_in;
  end

////////////////////////////////////////////////////////////////////////////
// stimulus
////////////////////////////////////////////////////////////////////////////

  task automatic step(input int unsigned count);
    for(int unsigned index = 0; index < count; index++)
      @(negedge clock);
  endtask

  task automatic wait_for_done_state(input done_model_t target);
    int unsigned guard;
    guard = 0;
    while(model_done_state != target) begin
      step(1);
      guard++;
      if(guard > PROGRESS_BOUND) begin
        $error(
          "completion progress bound exceeded phase=%s waiting=%s state=%s",
          phase,
          target.name(),
          model_done_state.name()
        );
        $fatal(1);
      end
    end
  endtask

  task automatic wait_for_error_state(input error_model_t target);
    int unsigned guard;
    guard = 0;
    while(model_error_state != target) begin
      step(1);
      guard++;
      if(guard > PROGRESS_BOUND) begin
        $error(
          "error progress bound exceeded phase=%s waiting=%s state=%s",
          phase,
          target.name(),
          model_error_state.name()
        );
        $fatal(1);
      end
    end
  endtask

  task automatic drive_statistics(input logic [0:63] seed);
    response_statistics.DONE_count                = seed ^ 64'h0000_0000_0000_0001;
    response_statistics.DONE_RESTART_count        = seed ^ 64'h0000_0000_0000_0002;
    response_statistics.DONE_PREFETCH_READ_count  = seed ^ 64'h0000_0000_0000_0003;
    response_statistics.DONE_PREFETCH_WRITE_count = seed ^ 64'h0000_0000_0000_0004;
    response_statistics.PAGED_count               = seed ^ 64'h0000_0000_0000_0005;
    response_statistics.FLUSHED_count             = seed ^ 64'h0000_0000_0000_0006;
    response_statistics.AERROR_count              = seed ^ 64'h0000_0000_0000_0007;
    response_statistics.DERROR_count              = seed ^ 64'h0000_0000_0000_0008;
    response_statistics.FAILED_count              = seed ^ 64'h0000_0000_0000_0009;
    response_statistics.FAULT_count               = seed ^ 64'h0000_0000_0000_000A;
    response_statistics.NRES_count                = seed ^ 64'h0000_0000_0000_000B;
    response_statistics.NLOCK_count               = seed ^ 64'h0000_0000_0000_000C;
    response_statistics.CYCLE_count               = seed ^ 64'h0000_0000_0000_000D;
    response_statistics.DONE_READ_count           = seed ^ 64'h0000_0000_0000_000E;
    response_statistics.DONE_WRITE_count          = seed ^ 64'h0000_0000_0000_000F;
    response_statistics.READ_BYTE_count           = seed ^ 64'h0000_0000_0000_0010;
    response_statistics.WRITE_BYTE_count          = seed ^ 64'h0000_0000_0000_0011;
    response_statistics.PREFETCH_READ_BYTE_count  = seed ^ 64'h0000_0000_0000_0012;
    response_statistics.PREFETCH_WRITE_BYTE_count = seed ^ 64'h0000_0000_0000_0013;
  endtask

  task automatic soft_reset_pulse();
    soft_rstn = 1'b0;
    step(2);
    soft_rstn = 1'b1;
    step(2);
    soft_rstn = 1'b0;
  endtask

  task automatic completion_cycle(
      input logic [0:63] return_low  ,
      input logic [0:63] return_high ,
      input logic [0:63] statistic   ,
      input int unsigned soft_delay  ,
      input int unsigned ack_delay
  );
    cu_return.var1 = return_low;
    cu_return.var2 = return_high;
    drive_statistics(statistic);
    step(1);
    cu_done = 1'b1;
    step(1);
    cu_done = 1'b0;
    wait_for_done_state(D_RESET_PENDING);
    step(soft_delay);
    soft_reset_pulse();
    wait_for_done_state(D_PUBLISH);
    step(ack_delay);
    cu_return_done_ack = 1'b1;
    step(1);
    cu_return_done_ack = 1'b0;
    wait_for_done_state(D_IDLE);
    step(DRAIN_CYCLES);
  endtask

  task automatic error_cycle(
      input logic [0:63] errors   ,
      input int unsigned ack_delay,
      input logic [0:63] intruder
  );
    external_errors = errors;
    wait_for_error_state(E_PUBLISH);
    if(|intruder)
      external_errors = intruder;
    step(ack_delay);
    report_errors_ack = 1'b1;
    step(1);
    report_errors_ack = 1'b0;
    external_errors   = 64'h0;
    wait_for_error_state(E_IDLE);
    step(DRAIN_CYCLES);
  endtask

  task automatic check_bins();
    bin_hits = 0;
    for(int index = 0; index < 5; index++) begin
      if(!bin_done_state[index])
        $fatal(1, "completion missing state bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 8; index++) begin
      if(!bin_done_transition[index])
        $fatal(1, "completion missing transition bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 2; index++) begin
      if(!bin_done_value[index])
        $fatal(1, "completion missing snapshot value bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_done_ack[index])
        $fatal(1, "completion missing acknowledge bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_done_reset[index])
        $fatal(1, "completion missing reset entry bin %0d", index);
      bin_hits++;
    end
    if(!bin_done_freeze[0])
      $fatal(1, "completion missing disabled freeze bin");
    bin_hits++;
    for(int index = 0; index < 5; index++) begin
      if(!bin_error_state[index])
        $fatal(1, "error missing state bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 7; index++) begin
      if(!bin_error_transition[index])
        $fatal(1, "error missing transition bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_error_class[index])
        $fatal(1, "error missing error class bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_error_ack[index])
        $fatal(1, "error missing acknowledge bin %0d", index);
      bin_hits++;
    end
    if(!bin_error_sticky[0])
      $fatal(1, "error missing sticky publication bin");
    bin_hits++;
    for(int index = 0; index < 2; index++) begin
      if(!bin_error_reset[index])
        $fatal(1, "error missing reset entry bin %0d", index);
      bin_hits++;
    end
    if(!bin_error_freeze[0])
      $fatal(1, "error missing disabled freeze bin");
    bin_hits++;
    if(!bin_overlap[0])
      $fatal(1, "completion and error overlap bin missing");
    bin_hits++;
    stalls = 0;
    for(int index = 0; index < STALL_PROFILES; index++) begin
      if(!stall_used[index])
        $fatal(1, "completion_error missing stall profile %0d", index);
      stalls++;
    end
  endtask

  initial begin
    finished                 = 1'b0;
    bin_hits                 = 0;
    stalls                   = 0;
    cycle                    = 0;
    checking                 = 1'b0;
    phase                    = "reset";
    rstn_in                  = 1'b0;
    enabled_in               = 1'b0;
    soft_rstn                = 1'b0;
    cu_return                = '0;
    response_statistics      = '0;
    cu_done                  = 1'b0;
    cu_return_done_ack       = 1'b0;
    external_errors          = 64'h0;
    report_errors_ack        = 1'b0;
    model_done_state               = D_RESET;
    model_error_state              = E_RESET;
    done_latched_return      = '0;
    done_latched_stats       = '0;
    expect_reset_done        = 1'b1;
    expect_cu_return_done    = '0;
    expect_report_statistics = '0;
    expect_reset_error       = 1'b1;
    expect_report_errors     = 64'h0;
    done_outputs_known       = 1'b0;
    error_outputs_known      = 1'b0;
    model_next_soft          = 1'b0;
    model_prev_soft          = 1'b0;
    model_done_soft          = 1'b0;
    rstn_previous            = 1'b0;
    rstn_reg                 = 1'b0;
    rstn_reg_last            = 1'b0;
    enabled_last             = 1'b0;

    step(4);
    rstn_in    = 1'b1;
    enabled_in = 1'b1;
    step(DRAIN_CYCLES);
    checking = 1'b1;

    // ---------------------------------------------------------------------
    phase = "zero-completion-immediate-ack";
    completion_cycle(64'h0, 64'h0, 64'h0, 0, 0);
    bin_done_ack[0] = 1;

    // ---------------------------------------------------------------------
    phase = "non-zero-completion-delayed-soft-reset-and-ack";
    completion_cycle(
      64'h0123_4567_89AB_CDEF,
      64'hFEDC_BA98_7654_3210,
      64'h1111_2222_3333_4444,
      STALL_SOFT_RESET_DELAY,
      STALL_ACK_DELAY
    );
    stall_used[0]   = 1;
    stall_used[1]   = 1;
    bin_done_ack[1] = 1;

    // ---------------------------------------------------------------------
    phase = "completion-without-acknowledge";
    cu_return.var1 = 64'hAAAA_AAAA_AAAA_AAAA;
    cu_return.var2 = 64'h5555_5555_5555_5555;
    drive_statistics(64'h9999_8888_7777_6666);
    step(1);
    cu_done = 1'b1;
    step(1);
    cu_done = 1'b0;
    wait_for_done_state(D_RESET_PENDING);
    soft_reset_pulse();
    wait_for_done_state(D_PUBLISH);
    step(STALL_ACK_ABSENT);
    stall_used[2]   = 1;
    bin_done_ack[2] = 1;
    cu_return_done_ack = 1'b1;
    step(1);
    cu_return_done_ack = 1'b0;
    wait_for_done_state(D_IDLE);
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "single-bit-error-immediate-ack";
    error_cycle(64'h0000_0000_0000_0001, 0, 64'h0);
    bin_error_ack[0] = 1;

    phase = "simultaneous-errors-delayed-ack";
    error_cycle(64'h8000_0000_0000_0081, STALL_ACK_DELAY, 64'hFFFF_FFFF_FFFF_FFFF);
    bin_error_ack[1] = 1;

    phase = "repeated-error-without-prompt-ack";
    error_cycle(64'h0000_0000_0000_0001, STALL_ACK_ABSENT, 64'h0);
    bin_error_ack[2]   = 1;
    bin_error_class[2] = 1;

    // ---------------------------------------------------------------------
    phase           = "overlapping-completion-and-error";
    cu_return.var1  = 64'h0F0F_0F0F_0F0F_0F0F;
    cu_return.var2  = 64'hF0F0_F0F0_F0F0_F0F0;
    drive_statistics(64'h2468_ACE0_1357_9BDF);
    step(1);
    cu_done         = 1'b1;
    external_errors = 64'h0000_0000_0000_0003;
    step(1);
    cu_done = 1'b0;
    wait_for_error_state(E_PUBLISH);
    report_errors_ack = 1'b1;
    step(1);
    report_errors_ack = 1'b0;
    external_errors   = 64'h0;
    wait_for_done_state(D_RESET_PENDING);
    soft_reset_pulse();
    wait_for_done_state(D_PUBLISH);
    cu_return_done_ack = 1'b1;
    step(1);
    cu_return_done_ack = 1'b0;
    wait_for_done_state(D_IDLE);
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase      = "disabled-freeze";
    enabled_in = 1'b0;
    step(2);
    external_errors = 64'h0000_0000_0000_00F0;
    cu_done         = 1'b1;
    step(STALL_ENABLE_LOW);
    stall_used[3]   = 1;
    cu_done         = 1'b0;
    external_errors = 64'h0;
    step(2);
    enabled_in = 1'b1;
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "reset-while-publishing";
    cu_return.var1 = 64'h1234_5678_9ABC_DEF0;
    cu_return.var2 = 64'h0FED_CBA9_8765_4321;
    step(1);
    cu_done = 1'b1;
    step(1);
    cu_done = 1'b0;
    external_errors = 64'h0000_0000_0000_0040;
    wait_for_done_state(D_RESET_PENDING);
    soft_reset_pulse();
    wait_for_done_state(D_PUBLISH);
    rstn_in = 1'b0;
    step(STALL_RESET_LOW);
    stall_used[4] = 1;
    rstn_in         = 1'b1;
    external_errors = 64'h0;
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "boundary-completion-and-error-values";
    completion_cycle({64{1'b1}}, {64{1'b1}}, {64{1'b1}}, 1, 1);
    completion_cycle({64{1'b0}}, {64{1'b0}}, {64{1'b0}}, 1, 1);
    error_cycle({64{1'b1}}, 1, 64'h0);
    error_cycle(64'h0000_0000_0000_0080, 1, 64'h0);

    // ---------------------------------------------------------------------
    phase   = "reset-while-idle";
    rstn_in = 1'b0;
    step(STALL_RESET_LOW);
    rstn_in = 1'b1;
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "reset-while-reset-pending";
    step(1);
    cu_done = 1'b1;
    step(1);
    cu_done = 1'b0;
    wait_for_done_state(D_RESET_PENDING);
    rstn_in = 1'b0;
    step(STALL_RESET_LOW);
    rstn_in = 1'b1;
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "post-reset-completion";
    completion_cycle(64'h0000_0000_0000_0001, 64'h0, 64'h5A5A_5A5A_5A5A_5A5A, 1, 1);
    step(DRAIN_CYCLES);

    check_bins();
    checking = 1'b0;
    finished = 1'b1;
  end

endmodule
