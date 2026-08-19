module response_statistics_control_tb;

  import CAPI_PKG::*;
  import AFU_PKG::*;
  import PROTOCOL_TB_PKG::*;

  localparam int JOURNAL_DEPTH = 32;

  logic clock;
  logic rstn_in;
  logic enabled_in;
  ResponseInterface response;
  CommandTagLine response_tag_id_in;
  ResponseStatistcsInterface response_statistics_out;

  psl_response_t journal_response [0:JOURNAL_DEPTH-1];
  command_type journal_type [0:JOURNAL_DEPTH-1];
  logic [0:7] journal_bytes [0:JOURNAL_DEPTH-1];
  int unsigned journal_count;
  int unsigned checks;
  int unsigned bins_hit;
  bit response_class_bins [0:8];
  bit done_route_bins [0:4];
  bit byte_counter_bins [0:3];
  bit rollover_bins [0:2];

  response_statistics_control dut (
    .clock(clock),
    .rstn_in(rstn_in),
    .enabled_in(enabled_in),
    .response(response),
    .response_tag_id_in(response_tag_id_in),
    .response_statistics_out(response_statistics_out)
  );

  always #5 clock = ~clock;

  task automatic tick;
    @(posedge clock);
    #1;
  endtask

  function automatic psl_response_t response_class(input int unsigned index);
    case(index)
      0: return DONE;
      1: return FLUSHED;
      2: return PAGED;
      3: return AERROR;
      4: return DERROR;
      5: return FAILED;
      6: return FAULT;
      7: return NRES;
      8: return NLOCK;
      default: return DONE;
    endcase
  endfunction

  function automatic logic [0:63] journal_response_count(
      input psl_response_t response_code
  );
    logic [0:63] result;
    result = 0;
    for(int index = 0; index < journal_count; index++)
      if(journal_response[index] == response_code)
        result++;
    return result;
  endfunction

  function automatic logic [0:63] journal_done_count(
      input command_type cmd_type
  );
    logic [0:63] result;
    result = 0;
    for(int index = 0; index < journal_count; index++)
      if(journal_response[index] == DONE && journal_type[index] == cmd_type)
        result++;
    return result;
  endfunction

  function automatic logic [0:63] journal_byte_count(
      input command_type cmd_type
  );
    logic [0:63] result;
    result = 0;
    for(int index = 0; index < journal_count; index++)
      if(journal_response[index] == DONE && journal_type[index] == cmd_type)
        result += journal_bytes[index];
    return result;
  endfunction

  task automatic reset_dut;
    rstn_in = 0;
    enabled_in = 0;
    response = '0;
    response_tag_id_in = '0;
    repeat(3) tick();
    rstn_in = 1;
    enabled_in = 1;
    repeat(4) tick();
  endtask

  task automatic journal_and_send(
      input psl_response_t response_code,
      input command_type cmd_type,
      input logic [0:7] size_bytes,
      input logic [0:7] tag
  );
    if(journal_count == JOURNAL_DEPTH)
      $fatal(1, "statistics journal mismatch journal overflow");
    journal_response[journal_count] = response_code;
    journal_type[journal_count] = cmd_type;
    journal_bytes[journal_count] = size_bytes;
    journal_count++;

    @(negedge clock);
    response = '0;
    response.valid = 1;
    response.tag = tag;
    response.tag_parity = model_odd_parity8(tag);
    response.response = response_code;
    response.credits = {tag[0], tag};
    response.cache_state = tag[6:7];
    response.cache_pos = {tag[3:7], tag};
    response_tag_id_in = tag[0] ? '1 : '0;
    response_tag_id_in.cu_id_x = tag;
    response_tag_id_in.cu_id_y = ~tag;
    response_tag_id_in.array_struct = array_struct_type'((tag % 3) + 1);
    response_tag_id_in.cmd_type = cmd_type;
    response_tag_id_in.real_size = size_bytes;
    response_tag_id_in.real_size_bytes = size_bytes;
    response_tag_id_in.cacheline_offset = tag ^ 8'h5a;
    response_tag_id_in.address_offset =
      tag[0] ? 64'ha55a_f00f_9669_c33c : 64'h5aa5_0ff0_6996_3cc3;
    response_tag_id_in.aux_data = ~response_tag_id_in.address_offset;
    response_tag_id_in.size = {tag[3:7], size_bytes[1:7]};
    response_tag_id_in.tag = tag;
    response_tag_id_in.abt = legal_abt(tag % 5);
    tick();
    @(negedge clock);
    response.valid = 0;
    repeat(6) tick();
  endtask

  task automatic check_journal;
    checks++;
    if(
      response_statistics_out.DONE_count !== journal_response_count(DONE) ||
      response_statistics_out.FLUSHED_count !== journal_response_count(FLUSHED) ||
      response_statistics_out.PAGED_count !== journal_response_count(PAGED) ||
      response_statistics_out.AERROR_count !== journal_response_count(AERROR) ||
      response_statistics_out.DERROR_count !== journal_response_count(DERROR) ||
      response_statistics_out.FAILED_count !== journal_response_count(FAILED) ||
      response_statistics_out.FAULT_count !== journal_response_count(FAULT) ||
      response_statistics_out.NRES_count !== journal_response_count(NRES) ||
      response_statistics_out.NLOCK_count !== journal_response_count(NLOCK) ||
      response_statistics_out.DONE_RESTART_count !== journal_done_count(CMD_RESTART) ||
      response_statistics_out.DONE_PREFETCH_READ_count !==
        journal_done_count(CMD_PREFETCH_READ) ||
      response_statistics_out.DONE_PREFETCH_WRITE_count !==
        journal_done_count(CMD_PREFETCH_WRITE) ||
      response_statistics_out.DONE_READ_count !== journal_done_count(CMD_READ) ||
      response_statistics_out.DONE_WRITE_count !== journal_done_count(CMD_WRITE) ||
      response_statistics_out.READ_BYTE_count !== journal_byte_count(CMD_READ) ||
      response_statistics_out.WRITE_BYTE_count !== journal_byte_count(CMD_WRITE) ||
      response_statistics_out.PREFETCH_READ_BYTE_count !==
        journal_byte_count(CMD_PREFETCH_READ) ||
      response_statistics_out.PREFETCH_WRITE_BYTE_count !==
        journal_byte_count(CMD_PREFETCH_WRITE)
    )
      $fatal(
        1,
        "statistics journal mismatch entries=%0d done_expected=%0d done_actual=%0d",
        journal_count,
        journal_response_count(DONE),
        response_statistics_out.DONE_count
      );
    if(response_statistics_out.CYCLE_count == 0)
      $fatal(1, "statistics journal mismatch cycle counter did not advance");
  endtask

  task automatic check_rollover;
    bit saw_cycle_zero;

    reset_dut();
    force dut.response_statistics_out_latched.CYCLE_count = 64'hffff_ffff_ffff_ffff;
    tick();
    release dut.response_statistics_out_latched.CYCLE_count;
    saw_cycle_zero = 0;
    repeat(4) begin
      tick();
      if(response_statistics_out.CYCLE_count == 0)
        saw_cycle_zero = 1;
    end
    if(!saw_cycle_zero)
      $fatal(1, "statistics journal mismatch cycle rollover not observed");
    rollover_bins[0] = 1;

    force dut.response_statistics_out_latched.DONE_count =
      64'hffff_ffff_ffff_ffff;
    force dut.response_statistics_out_latched.READ_BYTE_count =
      64'hffff_ffff_ffff_ff80;
    tick();
    release dut.response_statistics_out_latched.DONE_count;
    release dut.response_statistics_out_latched.READ_BYTE_count;

    journal_count = 0;
    journal_and_send(DONE, CMD_READ, 8'd128, 8'ha5);
    checks++;
    if(response_statistics_out.DONE_count !== 0)
      $fatal(
        1,
        "statistics journal mismatch response rollover actual=%h",
        response_statistics_out.DONE_count
      );
    rollover_bins[1] = 1;
    checks++;
    if(response_statistics_out.READ_BYTE_count !== 0)
      $fatal(
        1,
        "statistics journal mismatch byte rollover actual=%h",
        response_statistics_out.READ_BYTE_count
      );
    rollover_bins[2] = 1;
  endtask

  initial begin
    clock = 0;
    rstn_in = 0;
    enabled_in = 0;
    response = '0;
    response_tag_id_in = '0;
    journal_count = 0;
    checks = 0;
    bins_hit = 0;
    reset_dut();

    for(int response_index = 0; response_index < 9; response_index++) begin
      journal_and_send(
        response_class(response_index),
        CMD_WED,
        8'd0,
        (8'h10 + response_index)
      );
      response_class_bins[response_index] = 1;
    end

    journal_and_send(DONE, CMD_RESTART, 8'd0, 8'h30);
    done_route_bins[0] = 1;
    journal_and_send(DONE, CMD_PREFETCH_READ, 8'd16, 8'h31);
    done_route_bins[1] = 1;
    byte_counter_bins[0] = 1;
    journal_and_send(DONE, CMD_PREFETCH_WRITE, 8'd32, 8'h32);
    done_route_bins[2] = 1;
    byte_counter_bins[1] = 1;
    journal_and_send(DONE, CMD_READ, 8'd64, 8'h33);
    done_route_bins[3] = 1;
    byte_counter_bins[2] = 1;
    journal_and_send(DONE, CMD_WRITE, 8'd128, 8'h34);
    done_route_bins[4] = 1;
    byte_counter_bins[3] = 1;
    journal_and_send(DONE, CMD_READ, 8'd1, 8'h41);
    journal_and_send(DONE, CMD_WRITE, 8'd2, 8'h42);
    journal_and_send(DONE, CMD_PREFETCH_READ, 8'd4, 8'h43);
    journal_and_send(DONE, CMD_PREFETCH_WRITE, 8'd8, 8'h44);
    journal_and_send(psl_response_t'(8'hff), CMD_INVALID, 8'd0, 8'hfe);
    check_journal();
    check_rollover();

    for(int index = 0; index < 9; index++) begin
      if(!response_class_bins[index])
        $fatal(1, "statistics journal mismatch missing response bin=%0d", index);
      bins_hit++;
    end
    for(int index = 0; index < 5; index++) begin
      if(!done_route_bins[index])
        $fatal(1, "statistics journal mismatch missing route bin=%0d", index);
      bins_hit++;
    end
    for(int index = 0; index < 4; index++) begin
      if(!byte_counter_bins[index])
        $fatal(1, "statistics journal mismatch missing byte bin=%0d", index);
      bins_hit++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!rollover_bins[index])
        $fatal(1, "statistics journal mismatch missing rollover bin=%0d", index);
      bins_hit++;
    end

    $display(
      "PASS protocol_control dut=response_statistics_control checks=%0d bins=%0d/21",
      checks,
      bins_hit
    );
    $finish;
  end

endmodule
