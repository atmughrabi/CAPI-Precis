module restart_control_tb;

  import GLOBALS_AFU_PKG::*;
  import CAPI_PKG::*;
  import AFU_PKG::*;
  import CU_PKG::*;
  import PROTOCOL_TB_PKG::*;

  logic clock;
  logic enabled_in;
  logic rstn_in;
  CommandBufferLine command_outstanding_in;
  logic [0:7] command_tag_in;
  ResponseBufferLine restart_response_in;
  ResponseInterface response_in;
  CommandTagLine response_tag_id_in;
  logic [0:7] credits_in;
  logic [0:7] total_credits;
  logic ready_restart_issue;
  CommandBufferLine restart_command_issue_out;
  logic restart_command_flushed;
  logic restart_pending;

  int unsigned checks;
  int unsigned bins_hit;
  bit error_abt_cross [0:2][0:4];
  bit restart_outcome_bin;
  bit abort_outcome_bin;
  bit starvation_bin;
  bit flush_bin;
  bit replay_bin;
  bit no_duplicate_bin;
  bit counter_event_bins [0:7];
  bit fsm_transition_bins [0:5];
  bit restart_fifo_headroom_bin;
  bit init_buffer_valid_bin;

  restart_control #(.CREDIT_HEADROOM(4)) dut (
    .clock(clock),
    .enabled_in(enabled_in),
    .rstn_in(rstn_in),
    .command_outstanding_in(command_outstanding_in),
    .command_tag_in(command_tag_in),
    .restart_response_in(restart_response_in),
    .response_in(response_in),
    .response_tag_id_in(response_tag_id_in),
    .credits_in(credits_in),
    .total_credits(total_credits),
    .ready_restart_issue(ready_restart_issue),
    .restart_command_issue_out(restart_command_issue_out),
    .restart_command_flushed(restart_command_flushed),
    .restart_pending(restart_pending)
  );

  always #5 clock = ~clock;

  task automatic tick;
    @(posedge clock);
    #1;
  endtask

  function automatic psl_response_t restart_error(input int unsigned index);
    case(index)
      0: return PAGED;
      1: return AERROR;
      2: return DERROR;
      default: return PAGED;
    endcase
  endfunction

  function automatic bit should_restart(input trans_order_behavior_t abt);
    return abt == STRICT || abt == PAGE || abt == PREF || abt == SPEC;
  endfunction

  task automatic reset_dut;
    rstn_in = 0;
    enabled_in = 0;
    command_outstanding_in = '0;
    command_tag_in = 0;
    restart_response_in = '0;
    response_in = '0;
    response_tag_id_in = '0;
    credits_in = 8'd64;
    total_credits = 8'd64;
    repeat(4) tick();
    rstn_in = 1;
    enabled_in = 1;
    repeat(5) tick();
  endtask

  task automatic toggle_idle_inputs;
    @(negedge clock);
    response_in = '1;
    response_in.valid = 0;
    response_tag_id_in = '1;
    command_tag_in = 8'hff;
    credits_in = 8'd63;
    total_credits = 8'd63;
    tick();
    @(negedge clock);
    response_in = '0;
    response_tag_id_in = '0;
    command_tag_in = 8'h00;
    credits_in = 8'd64;
    total_credits = 8'd64;
    tick();
  endtask

  task automatic record_outstanding(
      input logic [0:7] tag,
      input trans_order_behavior_t abt,
      output CommandBufferLine original_command
  );
    original_command = '0;
    original_command.valid = 1;
    original_command.payload.command = READ_CL_NA;
    original_command.payload.address = 64'h1234_0000_0000_0080 | tag;
    original_command.payload.size = 12'd128;
    original_command.payload.abt = abt;
    original_command.payload.cmd = tag[0] ? '1 : '0;
    original_command.payload.cmd.cu_id_x = tag;
    original_command.payload.cmd.cu_id_y = ~tag;
    original_command.payload.cmd.array_struct =
      array_struct_type'((tag % 3) + 1);
    original_command.payload.cmd.cmd_type = CMD_READ;
    original_command.payload.cmd.real_size = tag ^ 8'h96;
    original_command.payload.cmd.real_size_bytes = 8'd128;
    original_command.payload.cmd.cacheline_offset = tag ^ 8'ha5;
    original_command.payload.cmd.address_offset =
      tag[0] ? 64'ha55a_f00f_9669_c33c : 64'h5aa5_0ff0_6996_3cc3;
    original_command.payload.cmd.aux_data =
      ~original_command.payload.cmd.address_offset;
    original_command.payload.cmd.size = {tag[3:7], tag[1:7]};
    original_command.payload.cmd.tag = tag;
    original_command.payload.cmd.abt = abt;

    @(negedge clock);
    command_tag_in = tag;
    command_outstanding_in = original_command;
    tick();
    @(negedge clock);
    command_outstanding_in.valid = 0;
    repeat(3) tick();
  endtask

  task automatic trigger_error(
      input logic [0:7] tag,
      input psl_response_t response_code,
      input trans_order_behavior_t abt
  );
    @(negedge clock);
      response_tag_id_in = tag[0] ? '1 : '0;
      response_tag_id_in.cu_id_x = tag;
      response_tag_id_in.cu_id_y = ~tag;
      response_tag_id_in.array_struct = array_struct_type'((tag % 3) + 1);
      response_tag_id_in.cmd_type = CMD_READ;
      response_tag_id_in.real_size = tag ^ 8'h96;
      response_tag_id_in.real_size_bytes = 8'd128;
      response_tag_id_in.cacheline_offset = tag ^ 8'ha5;
      response_tag_id_in.address_offset =
        tag[0] ? 64'ha55a_f00f_9669_c33c : 64'h5aa5_0ff0_6996_3cc3;
      response_tag_id_in.aux_data = ~response_tag_id_in.address_offset;
      response_tag_id_in.size = {tag[3:7], tag[1:7]};
      response_tag_id_in.tag = tag;
      response_tag_id_in.abt = abt;
    response_in = '0;
    response_in.valid = 1;
    response_in.tag = tag;
    response_in.tag_parity = model_odd_parity8(tag);
    response_in.response = response_code;
    response_in.credits = {tag[0], tag};
    response_in.cache_state = tag[6:7];
    response_in.cache_pos = {tag[3:7], tag};
    tick();
    @(negedge clock);
    response_in.valid = 0;
  endtask

  task automatic complete_restart;
    @(negedge clock);
    restart_response_in.valid = 1;
    tick();
    @(negedge clock);
    restart_response_in.valid = 0;
  endtask

  function automatic logic [0:7] counter_expected(
      input logic [0:2] selector,
      input logic [0:7] initial_value
  );
    case(selector)
      3'b100: return initial_value + 1;
      3'b110: return initial_value;
      3'b101: return initial_value;
      3'b111: return initial_value - 1;
      3'b011: return initial_value - 2;
      3'b001: return initial_value - 1;
      3'b010: return initial_value - 1;
      default: return initial_value;
    endcase
  endfunction

  task automatic probe_counter_event(
      input logic [0:2] selector,
      input logic [0:7] initial_value
  );
    logic [0:7] expected;

    reset_dut();
    force dut.outstanding_restart_commands = initial_value;
    tick();
    release dut.outstanding_restart_commands;
    force dut.is_restart_cmd = selector[0];
    force dut.is_restart_rsp_done = selector[1];
    force dut.is_restart_rsp_flush = selector[2];
    expected = counter_expected(selector, initial_value);
    tick();
    release dut.is_restart_cmd;
    release dut.is_restart_rsp_done;
    release dut.is_restart_rsp_flush;
    checks++;
    if(dut.outstanding_restart_commands !== expected)
      $fatal(
        1,
        "restart replay mismatch counter selector=%b expected=%0d actual=%0d",
        selector,
        expected,
        dut.outstanding_restart_commands
      );
    counter_event_bins[selector] = 1;
  endtask

  task automatic probe_fsm_transition(
      input int unsigned bin_index,
      input restart_state state,
      input logic latched_flag,
      input logic current_flag,
      input logic buffer_empty,
      input logic credits_equal,
      input logic response_valid,
      input restart_state expected_state
  );
    force dut.current_state = state;
    force dut.restart_command_flag_latched = latched_flag;
    force dut.restart_command_flag = current_flag;
    force dut.restart_command_buffer_status_internal.empty = buffer_empty;
    force dut.total_credit_count = credits_equal ? 8'd64 : 8'd63;
    force total_credits = 8'd64;
    force dut.response.valid = response_valid;
    #1;
    checks++;
    if(dut.next_state !== expected_state)
      $fatal(
        1,
        "restart replay mismatch transition state=%0d expected=%0d actual=%0d",
        state,
        expected_state,
        dut.next_state
      );
    fsm_transition_bins[bin_index] = 1;
    release dut.current_state;
    release dut.restart_command_flag_latched;
    release dut.restart_command_flag;
    release dut.restart_command_buffer_status_internal.empty;
    release dut.total_credit_count;
    release total_credits;
    release dut.response.valid;
    #1;
  endtask

  task automatic probe_init_buffer_valid;
    CommandBufferLine buffered_command;

    reset_dut();
    buffered_command = '0;
    buffered_command.valid = 1;
    buffered_command.payload.command = READ_CL_NA;
    buffered_command.payload.abt = PAGE;
    buffered_command.payload.cmd = make_metadata(CMD_READ, 8'h5a, PAGE, 8'd64);
    force dut.current_state = RESTART_INIT;
    force dut.restart_command_buffer_out = buffered_command;
    tick();
    checks++;
    if(
      !dut.restart_command_out.cmd.valid ||
      !dut.restart_command_out.flushed ||
      dut.restart_command_out.cmd.payload.abt !== STRICT
    )
      $fatal(1, "restart replay mismatch RESTART_INIT buffered-command path");
    release dut.current_state;
    release dut.restart_command_buffer_out;
    init_buffer_valid_bin = 1;
  endtask

  task automatic fill_restart_fifos;
    CommandBufferLine original_command;

    reset_dut();
    for(int tag = 0; tag < 64; tag++)
      record_outstanding(tag[7:0], STRICT, original_command);
    credits_in = 0;
    @(negedge clock);
    response_tag_id_in = make_metadata(CMD_READ, 8'h00, STRICT, 8'd128);
    response_in = '0;
    response_in.valid = 1;
    response_in.response = PAGED;
    for(int cycle = 0; cycle < 64; cycle++) begin
      response_in.tag = (cycle % 64);
      response_in.tag_parity = model_odd_parity8(response_in.tag);
      tick();
      @(negedge clock);
    end
    response_in.valid = 0;
    repeat(10) tick();
    checks++;
    if(
      !dut.restart_command_buffer_status_internal.alfull ||
      !dut.restart_command_issue_buffer_status_internal.alfull ||
      dut.restart_command_buffer_fifo_instant.count > 64 ||
      dut.restart_command_issue_buffer_fifo_instant.count > 64
    )
      $fatal(
        1,
        "restart replay mismatch FIFO saturation command=%b/%b/%0d issue=%b/%b/%0d",
        dut.restart_command_buffer_status_internal.full,
        dut.restart_command_buffer_status_internal.alfull,
        dut.restart_command_buffer_fifo_instant.count,
        dut.restart_command_issue_buffer_status_internal.full,
        dut.restart_command_issue_buffer_status_internal.alfull,
        dut.restart_command_issue_buffer_fifo_instant.count
      );
    restart_fifo_headroom_bin = 1;
  endtask

  task automatic run_case(
      input int unsigned error_index,
      input int unsigned abt_index,
      input bit starve
  );
    logic [0:7] tag;
    psl_response_t response_code;
    trans_order_behavior_t abt;
    CommandBufferLine original_command;
    int unsigned restart_issues;
    int unsigned replay_issues;
    int unsigned timeout;
    bit qualifying;

    reset_dut();
    toggle_idle_inputs();
    tag = 8'h40 + (error_index * 8) + abt_index;
    response_code = restart_error(error_index);
    abt = legal_abt(abt_index);
    qualifying = should_restart(abt);
    record_outstanding(tag, abt, original_command);
    if(starve)
      credits_in = 8'd4;
    else
      credits_in = 8'd63;
    trigger_error(tag, response_code, abt);

    restart_issues = 0;
    replay_issues = 0;
    if(starve) begin
      repeat(6) begin
        tick();
        checks++;
        if(restart_command_issue_out.valid)
          $fatal(
            1,
            "restart replay mismatch credit-starvation issued tag=%0d",
            tag
          );
      end
      starvation_bin = 1;
      credits_in = 8'd63;
    end

    timeout = 0;
    while((restart_issues == 0) && qualifying && timeout < 48) begin
      tick();
      if(restart_command_issue_out.valid) begin
        checks++;
        if(
          restart_command_flushed ||
          restart_command_issue_out.payload.command !== RESTART ||
          restart_command_issue_out.payload.abt !== STRICT ||
          restart_command_issue_out.payload.cmd.cmd_type !== CMD_RESTART ||
          restart_command_issue_out.payload.cmd.cu_id_x !== RESTART_ID ||
          restart_command_issue_out.payload.cmd.cu_id_y !== RESTART_ID
        )
          $fatal(
            1,
            "restart replay mismatch restart command tag=%0d command=%h flushed=%0b",
            tag,
            restart_command_issue_out.payload.command,
            restart_command_flushed
          );
        restart_issues++;
      end
      timeout++;
    end
    if(qualifying && restart_issues != 1)
      $fatal(
        1,
        "restart replay mismatch missing restart error=%0d abt=%0d",
        error_index,
        abt_index
      );
    if(qualifying) begin
      restart_outcome_bin = 1;
      repeat(4) tick();
      complete_restart();
    end else begin
      abort_outcome_bin = 1;
    end

    timeout = 0;
    while(replay_issues == 0 && timeout < 64) begin
      tick();
      if(restart_command_issue_out.valid) begin
        if(!restart_command_flushed) begin
          restart_issues++;
        end else begin
          checks++;
          if(
            restart_command_issue_out.payload.command !== original_command.payload.command ||
            restart_command_issue_out.payload.address !== original_command.payload.address ||
            restart_command_issue_out.payload.size !== original_command.payload.size ||
            restart_command_issue_out.payload.cmd.tag !== tag
          )
            $fatal(
              1,
              "restart replay mismatch flushed payload tag=%0d actual_tag=%0d",
              tag,
              restart_command_issue_out.payload.cmd.tag
            );
          replay_issues++;
        end
      end
      timeout++;
    end
    if(replay_issues != 1)
      $fatal(
        1,
        "restart replay mismatch missing replay error=%0d abt=%0d pending=%0b state=%0d count=%0d",
        error_index,
        abt_index,
        restart_pending,
        dut.current_state,
        dut.restart_command_buffer_fifo_instant.count
      );
    credits_in = 8'd64;
    flush_bin = 1;
    replay_bin = 1;

    repeat(12) begin
      tick();
      if(restart_command_issue_out.valid) begin
        if(restart_command_flushed)
          replay_issues++;
        else
          restart_issues++;
      end
    end
    checks++;
    if(
      replay_issues != 1 ||
      restart_issues != (qualifying ? 1 : 0)
    )
      $fatal(
        1,
        "restart replay mismatch duplicate completion restart=%0d replay=%0d",
        restart_issues,
        replay_issues
      );
    no_duplicate_bin = 1;
    error_abt_cross[error_index][abt_index] = 1;
  endtask

  initial begin
    clock = 0;
    rstn_in = 0;
    enabled_in = 0;
    command_outstanding_in = '0;
    command_tag_in = 0;
    restart_response_in = '0;
    response_in = '0;
    response_tag_id_in = '0;
    credits_in = 0;
    total_credits = 0;
    checks = 0;
    bins_hit = 0;

    for(int error_index = 0; error_index < 3; error_index++) begin
      for(int abt_index = 0; abt_index < 5; abt_index++)
        run_case(error_index, abt_index, error_index == 0 && abt_index == 0);
    end
    for(int selector = 0; selector < 8; selector++)
      probe_counter_event(selector[2:0], selector == 4 ? 8'd63 : 8'd8);
    probe_fsm_transition(
      0, RESTART_SEND_CMD, 1, 0, 1, 1, 0, RESTART_SEND_CMD
    );
    probe_fsm_transition(
      1, RESTART_SEND_CMD, 0, 1, 1, 1, 0, RESTART_INIT
    );
    probe_fsm_transition(
      2, RESTART_RESP_WAIT, 0, 1, 1, 1, 0, RESTART_INIT
    );
    probe_fsm_transition(
      3, RESTART_SEND_CMD_FLUSHED, 0, 1, 1, 1, 0, RESTART_INIT
    );
    probe_fsm_transition(
      4, RESTART_SEND_CMD_FLUSHED, 0, 1, 0, 0, 0, RESTART_INIT
    );
    probe_fsm_transition(
      5, RESTART_DONE, 0, 0, 1, 1, 1, RESTART_INIT
    );
    probe_init_buffer_valid();
    fill_restart_fifos();

    for(int error_index = 0; error_index < 3; error_index++) begin
      for(int abt_index = 0; abt_index < 5; abt_index++) begin
        if(!error_abt_cross[error_index][abt_index])
          $fatal(
            1,
            "restart replay mismatch missing cross error=%0d abt=%0d",
            error_index,
            abt_index
          );
        bins_hit++;
      end
    end
    if(
      !restart_outcome_bin ||
      !abort_outcome_bin ||
      !starvation_bin ||
      !flush_bin ||
      !replay_bin ||
      !no_duplicate_bin
    )
      $fatal(1, "restart replay mismatch missing lifecycle bin");
    bins_hit += 6;
    for(int selector = 0; selector < 8; selector++) begin
      if(!counter_event_bins[selector])
        $fatal(1, "restart replay mismatch missing counter bin=%0d", selector);
      bins_hit++;
    end
    for(int transition = 0; transition < 6; transition++) begin
      if(!fsm_transition_bins[transition])
        $fatal(
          1,
          "restart replay mismatch missing transition bin=%0d",
          transition
        );
      bins_hit++;
    end
    if(!restart_fifo_headroom_bin || !init_buffer_valid_bin)
      $fatal(1, "restart replay mismatch missing saturation/init bin");
    bins_hit += 2;

    $display(
      "PASS protocol_control dut=restart_control checks=%0d bins=%0d/37",
      checks,
      bins_hit
    );
    $finish;
  end

endmodule
