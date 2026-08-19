module response_control_tb;

  import CAPI_PKG::*;
  import AFU_PKG::*;
  import PROTOCOL_TB_PKG::*;

  logic clock;
  logic rstn_in;
  logic enabled_in;
  ResponseInterface response;
  CommandTagLine response_tag_id_in;
  logic [0:6] response_error;
  ResponseControlInterfaceOut response_control_out;

  CommandTagLine metadata [0:255];
  bit metadata_valid [0:255];
  int unsigned checks;
  int unsigned bins_hit;
  bit response_route_cross [0:8][0:5];
  bit parity_bins [0:1];
  bit reorder_bin;
  bit unknown_tag_bin;
  bit nlock_error_bin;

  response_control dut (
    .clock(clock),
    .rstn_in(rstn_in),
    .enabled_in(enabled_in),
    .response(response),
    .response_tag_id_in(response_tag_id_in),
    .response_error(response_error),
    .response_control_out(response_control_out)
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

  function automatic command_type route_class(input int unsigned index);
    case(index)
      0: return CMD_READ;
      1: return CMD_WRITE;
      2: return CMD_WED;
      3: return CMD_RESTART;
      4: return CMD_PREFETCH_READ;
      5: return CMD_PREFETCH_WRITE;
      default: return CMD_INVALID;
    endcase
  endfunction

  task automatic check_route(
      input command_type expected_route,
      input ResponseInterface sent_response,
      input bit known_tag
  );
    logic [0:5] route_vector;
    logic [0:6] expected_error;
    int unsigned timeout;
    bit saw_expected_error;

    timeout = 0;
    while(!response_control_out.response.valid && timeout < 8) begin
      tick();
      timeout++;
    end
    if(timeout == 8)
      $fatal(1, "response router mismatch response timeout tag=%0d", sent_response.tag);

    route_vector = {
      response_control_out.read_response,
      response_control_out.write_response,
      response_control_out.wed_response,
      response_control_out.restart_response,
      response_control_out.prefetch_read_response,
      response_control_out.prefetch_write_response
    };
    checks++;
    if(
      response_control_out.response.payload.response !== sent_response.response ||
      response_control_out.response.payload.response_credits !== sent_response.credits ||
      response_control_out.response.payload.cmd.tag !== sent_response.tag ||
      (known_tag && response_control_out.response.payload.cmd.cmd_type !== expected_route)
    )
      $fatal(1, "response router mismatch payload tag=%0d", sent_response.tag);

    case(expected_route)
      CMD_READ:           if(route_vector !== 6'b100000)
        $fatal(1, "response router mismatch route=read actual=%b", route_vector);
      CMD_WRITE:          if(route_vector !== 6'b010000)
        $fatal(1, "response router mismatch route=write actual=%b", route_vector);
      CMD_WED:            if(route_vector !== 6'b001000)
        $fatal(1, "response router mismatch route=wed actual=%b", route_vector);
      CMD_RESTART:        if(route_vector !== 6'b000100)
        $fatal(1, "response router mismatch route=restart actual=%b", route_vector);
      CMD_PREFETCH_READ:  if(route_vector !== 6'b000010)
        $fatal(1, "response router mismatch route=prefetch-read actual=%b", route_vector);
      CMD_PREFETCH_WRITE: if(route_vector !== 6'b000001)
        $fatal(1, "response router mismatch route=prefetch-write actual=%b", route_vector);
      default: if(route_vector !== 6'b000000)
        $fatal(1, "response router mismatch route=unknown actual=%b", route_vector);
    endcase

    expected_error = {
      model_odd_parity8(sent_response.tag) ^ sent_response.tag_parity,
      model_response_error(sent_response.response)
    };
    saw_expected_error = response_error === expected_error;
    repeat(4) begin
      tick();
      saw_expected_error |= response_error === expected_error;
    end
    checks++;
    if(!saw_expected_error)
      $fatal(
        1,
        "response router mismatch error tag=%0d expected=%b last=%b",
        sent_response.tag,
        expected_error,
        response_error
      );
    if(sent_response.response == NLOCK)
      nlock_error_bin = 1;
  endtask

  task automatic send_response(
      input logic [0:7] tag,
      input psl_response_t response_code,
      input logic tag_parity,
      input bit known_tag
  );
    ResponseInterface sent_response;
    command_type expected_route;

    sent_response = '0;
    sent_response.valid = 1;
    sent_response.tag = tag;
    sent_response.tag_parity = tag_parity;
    sent_response.response = response_code;
    sent_response.credits = {tag[0], tag};
    sent_response.cache_state = tag[6:7];
    sent_response.cache_pos = tag[0] ? 13'h1fff : 13'h0000;
    expected_route = known_tag ? metadata[tag].cmd_type : CMD_INVALID;

    @(negedge clock);
    response_tag_id_in = known_tag ? metadata[tag] : '0;
    response = sent_response;
    tick();
    @(negedge clock);
    response.valid = 0;
    check_route(expected_route, sent_response, known_tag);
    parity_bins[
      model_odd_parity8(sent_response.tag) == sent_response.tag_parity ? 0 : 1
    ] = 1;
    repeat(2) tick();
  endtask

  initial begin
    clock = 0;
    rstn_in = 0;
    enabled_in = 0;
    response = '0;
    response_tag_id_in = '0;
    checks = 0;
    bins_hit = 0;
    for(int tag = 0; tag < 256; tag++) begin
      metadata[tag] = '0;
      metadata_valid[tag] = 0;
    end
    repeat(3) tick();
    rstn_in = 1;
    enabled_in = 1;
    repeat(3) tick();

    for(int response_index = 0; response_index < 9; response_index++) begin
      for(int reverse_route = 5; reverse_route >= 0; reverse_route--) begin
        int tag;
        tag = (response_index * 29 + reverse_route * 37) % 240;
        metadata[tag] = response_index[0] ? '1 : '0;
        metadata[tag].cmd_type = route_class(reverse_route);
        metadata[tag].array_struct = array_struct_type'((response_index % 3) + 1);
        metadata[tag].abt = legal_abt((response_index + reverse_route) % 5);
        metadata[tag].tag = tag[7:0];
        metadata[tag].real_size = (8'h1 << (response_index % 8));
        metadata[tag].real_size_bytes = ~tag[7:0];
        metadata[tag].cacheline_offset = tag[7:0] ^ 8'ha5;
        metadata[tag].address_offset =
          response_index[0] ? 64'ha55a_f00f_9669_c33c : 64'h5aa5_0ff0_6996_3cc3;
        metadata[tag].aux_data = ~metadata[tag].address_offset;
        metadata[tag].size = {response_index[3:0], tag[7:0]};
        metadata_valid[tag] = 1;
        send_response(
          tag[7:0],
          response_class(response_index),
          model_odd_parity8(tag[7:0]),
          1
        );
        response_route_cross[response_index][reverse_route] = 1;
      end
    end
    reorder_bin = 1;

    metadata[8'h22] = make_metadata(CMD_WED, 8'h22, STRICT, 8'd16);
    metadata_valid[8'h22] = 1;
    send_response(8'h22, DONE, ~model_odd_parity8(8'h22), 1);
    send_response(8'hee, DONE, model_odd_parity8(8'hee), 0);
    unknown_tag_bin = 1;

    for(int response_index = 0; response_index < 9; response_index++) begin
      for(int route_index = 0; route_index < 6; route_index++) begin
        if(!response_route_cross[response_index][route_index])
          $fatal(
            1,
            "response router mismatch missing cross response=%0d route=%0d",
            response_index,
            route_index
          );
        bins_hit++;
      end
    end
    for(int parity_index = 0; parity_index < 2; parity_index++) begin
      if(!parity_bins[parity_index])
        $fatal(1, "response router mismatch missing parity bin=%0d", parity_index);
      bins_hit++;
    end
    if(!reorder_bin || !unknown_tag_bin || !nlock_error_bin)
      $fatal(1, "response router mismatch missing reorder/unknown/NLOCK bin");
    bins_hit += 3;

    $display(
      "PASS protocol_control dut=response_control checks=%0d bins=%0d/59",
      checks,
      bins_hit
    );
    $finish;
  end

endmodule
