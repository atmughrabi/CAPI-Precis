module afu_control_tb;

  import GLOBALS_AFU_PKG::*;
  import CAPI_PKG::*;
  import AFU_PKG::*;
  import CU_PKG::*;

  logic clock = 0;
  logic rstn;
  logic enabled;
  afu_configure_type configure;
  CommandBufferLine prefetch_read_command;
  CommandBufferLine prefetch_write_command;
  CommandBufferLine read_command;
  CommandBufferLine write_command;
  CommandBufferLine wed_command;
  CommandInterfaceInput command_in;
  ResponseInterface response;
  BufferInterfaceInput buffer_in;
  ReadWriteDataLine write_data_0;
  ReadWriteDataLine write_data_1;
  logic [0:63] afu_status;
  ReadWriteDataLine wed_data_0;
  ReadWriteDataLine wed_data_1;
  ReadWriteDataLine read_data_0;
  ReadWriteDataLine read_data_1;
  ResponseBufferLine read_response;
  ResponseBufferLine prefetch_read_response;
  ResponseBufferLine prefetch_write_response;
  ResponseBufferLine write_response;
  ResponseBufferLine wed_response;
  logic [0:6] command_response_error;
  logic [0:1] data_read_error;
  logic data_write_error;
  logic credit_overflow_error;
  BufferInterfaceOutput buffer_out;
  CommandInterfaceOutput command_out;
  CommandBufferStatusInterface command_status;
  ResponseStatistcsInterface response_statistics;
  DataBufferStatusInterface write_data_status;

  logic tag_enabled;
  logic tag_response_valid;
  logic [0:7] tag_response;
  CommandTagLine tag_response_id;
  logic [0:7] tag_data_read;
  CommandTagLine tag_data_read_id;
  logic tag_command_valid;
  CommandTagLine tag_command_id;
  logic [0:7] tag_command;
  logic tag_ready;

  int unsigned bins_hit;
  int unsigned assertions_checked;
  int unsigned tag_capacity_observed;

  always #5 clock = ~clock;

  afu_control #(
    .RSP_DELAY(2),
    .CREDIT_HEADROOM(0)
  ) dut (
    .clock(clock),
    .rstn_in(rstn),
    .enabled_in(enabled),
    .afu_configure_in(configure),
    .prefetch_read_command_in(prefetch_read_command),
    .prefetch_write_command_in(prefetch_write_command),
    .read_command_in(read_command),
    .write_command_in(write_command),
    .wed_command_in(wed_command),
    .command_in(command_in),
    .response(response),
    .buffer_in(buffer_in),
    .write_data_0_in(write_data_0),
    .write_data_1_in(write_data_1),
    .afu_status(afu_status),
    .wed_data_0_out(wed_data_0),
    .wed_data_1_out(wed_data_1),
    .read_data_0_out(read_data_0),
    .read_data_1_out(read_data_1),
    .read_response_out(read_response),
    .prefetch_read_response_out(prefetch_read_response),
    .prefetch_write_response_out(prefetch_write_response),
    .write_response_out(write_response),
    .wed_response_out(wed_response),
    .command_response_error(command_response_error),
    .data_read_error(data_read_error),
    .data_write_error(data_write_error),
    .credit_overflow_error(credit_overflow_error),
    .buffer_out(buffer_out),
    .command_out(command_out),
    .command_buffer_status(command_status),
    .response_statistics(response_statistics),
    .write_data_buffer_status(write_data_status)
  );

  tag_control tag_exhaustion_dut (
    .clock(clock),
    .rstn_in(rstn),
    .enabled_in(tag_enabled),
    .tag_response_valid(tag_response_valid),
    .response_tag(tag_response),
    .response_tag_id_out(tag_response_id),
    .data_read_tag(tag_data_read),
    .data_read_tag_id_out(tag_data_read_id),
    .tag_command_valid(tag_command_valid),
    .tag_command_id(tag_command_id),
    .command_tag_out(tag_command),
    .tag_buffer_ready(tag_ready)
  );

  task automatic tick(input int unsigned cycles = 1);
    repeat(cycles) begin
      @(posedge clock);
      #1;
    end
  endtask

  task automatic require(input logic condition, input string message);
    assertions_checked++;
    if(!condition)
      $fatal(1, "afu_control requirement failed: %s", message);
  endtask

  function automatic logic odd_parity_8(input logic [0:7] value);
    return logic'(($countones(value) + 1) % 2);
  endfunction

  function automatic logic odd_parity_13(input logic [0:12] value);
    return logic'(($countones(value) + 1) % 2);
  endfunction

  function automatic logic odd_parity_64(input logic [0:63] value);
    return logic'(($countones(value) + 1) % 2);
  endfunction

  function automatic logic [0:7] odd_parity_512(input logic [0:511] value);
    logic [0:7] result;
    for(int lane = 0; lane < 8; lane++)
      result[lane] = logic'(($countones(value[lane * 64 +: 64]) + 1) % 2);
    return result;
  endfunction

  task automatic clear_inputs;
    enabled = 0;
    configure = '0;
    prefetch_read_command = '0;
    prefetch_write_command = '0;
    read_command = '0;
    write_command = '0;
    wed_command = '0;
    command_in = '0;
    response = '0;
    buffer_in = '0;
    write_data_0 = '0;
    write_data_1 = '0;
    tag_enabled = 0;
    tag_response_valid = 0;
    tag_response = 0;
    tag_data_read = 0;
    tag_command_valid = 0;
    tag_command_id = '0;
  endtask

  task automatic reset_dut(input logic round_robin, input logic [0:7] room);
    rstn = 0;
    clear_inputs();
    tick(6);
    rstn = 1;
    enabled = 1;
    tag_enabled = 1;
    command_in.room = room;
    configure.var1 = '0;
    if(round_robin)
      configure.var1[63] = 1;
    else
      configure.var1[62] = 1;
    tick(285);
    require(afu_status == configure.var1, "configuration did not latch");
  endtask

  task automatic coverage_toggle_sweep;
    rstn = 0;
    clear_inputs();
    tick(3);
    enabled = 1;
    configure = '1;
    prefetch_read_command = '1;
    prefetch_write_command = '1;
    read_command = '1;
    write_command = '1;
    wed_command = '1;
    command_in = '1;
    response = '1;
    buffer_in = '1;
    write_data_0 = '1;
    write_data_1 = '1;
    tag_enabled = 1;
    tag_response_valid = 1;
    tag_response = '1;
    tag_data_read = '1;
    tag_command_valid = 1;
    tag_command_id = '1;
    tick(3);
    clear_inputs();
    tick(3);
    rstn = 1;
    enabled = 1;
    configure = 0;
    command_in.room = 8;
    tick(5);
    configure = '1;
    command_in.room = 8'hff;
    response = '1;
    buffer_in = '1;
    write_data_0 = '1;
    write_data_1 = '1;
    tick(8);
    enabled = 0;
    configure = 0;
    response = 0;
    buffer_in = 0;
    write_data_0 = 0;
    write_data_1 = 0;
    tick(5);
    rstn = 0;
    clear_inputs();
    tick(4);
  endtask

  task automatic send_buffer_half(
      input logic [0:7] tag,
      input logic [0:5] half,
      input logic [0:511] data
  );
    buffer_in.write_valid = 1;
    buffer_in.write_tag = tag;
    buffer_in.write_tag_parity = odd_parity_8(tag);
    buffer_in.write_address = half;
    buffer_in.write_data = data;
    buffer_in.write_parity = odd_parity_512(data);
    tick();
    buffer_in.write_valid = 0;
  endtask

  task automatic read_data_routing_case;
    logic [0:7] tag;
    bit lower_seen;
    bit upper_seen;

    reset_dut(1, 8);
    pulse_channel(CMD_WED, 64'h8c00);
    wait_command("WED-data-route", 64'h8c00, tag);
    send_buffer_half(tag, 0, {8{64'h0123_4567_89ab_cdef}});
    send_buffer_half(tag, 1, {8{64'hfedc_ba98_7654_3210}});
    send_response(tag, DONE);
    lower_seen = 0;
    upper_seen = 0;
    repeat(80) begin
      tick();
      lower_seen |= wed_data_0.valid;
      upper_seen |= wed_data_1.valid;
    end
    require(lower_seen && upper_seen, "WED lower/upper data routing");

    reset_dut(1, 8);
    pulse_channel(CMD_READ, 64'h8d00);
    wait_command("read-data-route", 64'h8d00, tag);
    send_buffer_half(tag, 0, {8{64'ha5a5_5a5a_dead_beef}});
    send_buffer_half(tag, 1, {8{64'h5a5a_a5a5_cafe_f00d}});
    send_response(tag, DONE);
    lower_seen = 0;
    upper_seen = 0;
    repeat(80) begin
      tick();
      lower_seen |= read_data_0.valid;
      upper_seen |= read_data_1.valid;
    end
    require(lower_seen && upper_seen, "CU lower/upper read-data routing");
    bins_hit++;
  endtask

  task automatic set_line(
      ref CommandBufferLine line,
      input command_type kind,
      input afu_command_t command,
      input logic [0:63] address,
      input logic [0:7] real_size,
      input trans_order_behavior_t abt
  );
    line = '0;
    line.valid = 1;
    line.payload.command = command;
    line.payload.address = address;
    line.payload.size = (real_size == 0) ? 0 : 128;
    line.payload.abt = abt;
    line.payload.cmd.cmd_type = kind;
    line.payload.cmd.real_size = real_size;
    line.payload.cmd.real_size_bytes = real_size;
    line.payload.cmd.address_offset = address;
    line.payload.cmd.abt = abt;
    case(kind)
      CMD_WED: line.payload.cmd.cu_id_x = WED_ID;
      default: line.payload.cmd.cu_id_x = 8'h44;
    endcase
    line.payload.cmd.cu_id_y = line.payload.cmd.cu_id_x;
  endtask

  task automatic pulse_channel(
      input command_type kind,
      input logic [0:63] address
  );
    case(kind)
      CMD_WED: set_line(wed_command, kind, READ_CL_NA, address, 128, STRICT);
      CMD_READ: set_line(read_command, kind, READ_CL_NA, address, 128, STRICT);
      CMD_WRITE: begin
        set_line(write_command, kind, WRITE_NA, address, 128, STRICT);
        write_data_0.valid = 1;
        write_data_1.valid = 1;
        write_data_0.payload.cmd = write_command.payload.cmd;
        write_data_1.payload.cmd = write_command.payload.cmd;
        write_data_0.payload.data = {8{64'h1122_3344_5566_7788}};
        write_data_1.payload.data = {8{64'h8877_6655_4433_2211}};
      end
      CMD_PREFETCH_READ:
        set_line(prefetch_read_command, kind, TOUCH_I, address, 128, STRICT);
      CMD_PREFETCH_WRITE:
        set_line(prefetch_write_command, kind, TOUCH_I, address, 128, STRICT);
      default: $fatal(1, "unsupported channel");
    endcase
    tick();
    prefetch_read_command.valid = 0;
    prefetch_write_command.valid = 0;
    read_command.valid = 0;
    write_command.valid = 0;
    wed_command.valid = 0;
    write_data_0.valid = 0;
    write_data_1.valid = 0;
  endtask

  task automatic wait_command(
      input string name,
      input logic [0:63] expected_address,
      output logic [0:7] tag
  );
    bit found;
    found = 0;
    tag = 0;
    repeat(140) begin
      tick();
      if(command_out.valid && !found) begin
        found = 1;
        tag = command_out.tag;
        require(command_out.address == expected_address, {name, ": address"});
        require(command_out.tag_parity == odd_parity_8(command_out.tag),
                {name, ": tag parity"});
        require(command_out.command_parity == odd_parity_13(command_out.command),
                {name, ": command parity"});
        require(command_out.address_parity == odd_parity_64(command_out.address),
                {name, ": address parity"});
        require(command_out.context_handle == 0, {name, ": context handle"});
      end
    end
    require(found, {name, ": command missing"});
  endtask

  task automatic send_response(
      input logic [0:7] tag,
      input psl_response_t response_code
  );
    response.valid = 1;
    response.tag = tag;
    response.tag_parity = odd_parity_8(tag);
    response.response = response_code;
    response.credits = 1;
    tick();
    response.valid = 0;
  endtask

  task automatic wait_routed_response(
      input string name,
      input command_type expected_kind,
      input logic [0:7] expected_tag
  );
    bit found;
    found = 0;
    repeat(80) begin
      tick();
      case(expected_kind)
        CMD_WED:
          if(wed_response.valid) begin
            found = 1;
            require(wed_response.payload.cmd.tag == expected_tag, {name, ": WED tag"});
          end
        CMD_READ:
          if(read_response.valid) begin
            found = 1;
            require(read_response.payload.cmd.tag == expected_tag, {name, ": read tag"});
          end
        CMD_WRITE:
          if(write_response.valid) begin
            found = 1;
            require(write_response.payload.cmd.tag == expected_tag, {name, ": write tag"});
          end
        CMD_PREFETCH_READ:
          if(prefetch_read_response.valid) begin
            found = 1;
            require(prefetch_read_response.payload.cmd.tag == expected_tag,
                    {name, ": prefetch-read tag"});
          end
        CMD_PREFETCH_WRITE:
          if(prefetch_write_response.valid) begin
            found = 1;
            require(prefetch_write_response.payload.cmd.tag == expected_tag,
                    {name, ": prefetch-write tag"});
          end
        default: begin end
      endcase
    end
    require(found, {name, ": routed response missing"});
  endtask

  task automatic sequential_channels(input logic round_robin);
    logic [0:7] tag;
    command_type kinds[0:4];
    logic [0:63] addresses[0:4];

    kinds[0] = CMD_WED;
    kinds[1] = CMD_PREFETCH_WRITE;
    kinds[2] = CMD_WRITE;
    kinds[3] = CMD_PREFETCH_READ;
    kinds[4] = CMD_READ;
    addresses[0] = 64'h1000;
    addresses[1] = 64'h2000;
    addresses[2] = 64'h3000;
    addresses[3] = 64'h4000;
    addresses[4] = 64'h5000;
    reset_dut(round_robin, 8);
    for(int index = 0; index < 5; index++) begin
      pulse_channel(kinds[index], addresses[index]);
      wait_command($sformatf("channel-%0d", index), addresses[index], tag);
      send_response(tag, DONE);
      wait_routed_response($sformatf("channel-%0d", index), kinds[index], tag);
      bins_hit++;
    end
  endtask

  task automatic response_reorder_case;
    logic [0:7] read_tag;
    logic [0:7] write_tag;

    reset_dut(1, 8);
    pulse_channel(CMD_READ, 64'h6100);
    wait_command("reorder-read", 64'h6100, read_tag);
    pulse_channel(CMD_WRITE, 64'h6200);
    wait_command("reorder-write", 64'h6200, write_tag);
    require(read_tag != write_tag, "reorder tags were not unique");
    send_response(write_tag, DONE);
    wait_routed_response("reorder-write", CMD_WRITE, write_tag);
    send_response(read_tag, DONE);
    wait_routed_response("reorder-read", CMD_READ, read_tag);
    bins_hit++;
  endtask

  task automatic error_case;
    logic [0:7] tag;
    bit tag_error_seen;
    bit response_error_seen;

    reset_dut(1, 8);
    pulse_channel(CMD_READ, 64'h7100);
    wait_command("error-read", 64'h7100, tag);
    response.valid = 1;
    response.tag = tag;
    response.tag_parity = ~odd_parity_8(tag);
    response.response = FAILED;
    response.credits = 1;
    tick();
    response.valid = 0;
    tag_error_seen = 0;
    response_error_seen = 0;
    repeat(20) begin
      tick();
      tag_error_seen |= command_response_error[0];
      response_error_seen |= |command_response_error[1:6];
    end
    require(tag_error_seen, "response tag parity error missing");
    require(response_error_seen, "FAILED response error missing");

    reset_dut(1, 8);
    pulse_channel(CMD_READ, 64'h7200);
    wait_command("read-data-error", 64'h7200, tag);
    buffer_in.write_valid = 1;
    buffer_in.write_tag = tag;
    buffer_in.write_tag_parity = ~odd_parity_8(tag);
    buffer_in.write_address = 0;
    buffer_in.write_data = '1;
    buffer_in.write_parity = ~odd_parity_512('1);
    tick();
    buffer_in.write_valid = 0;
    tag_error_seen = 0;
    response_error_seen = 0;
    repeat(12) begin
      tick();
      tag_error_seen |= data_read_error[0];
      response_error_seen |= data_read_error[1];
    end
    require(tag_error_seen && response_error_seen,
            "read-data parity errors missing");

    reset_dut(1, 8);
    pulse_channel(CMD_WRITE, 64'h7300);
    wait_command("write-data-error", 64'h7300, tag);
    buffer_in.read_valid = 1;
    buffer_in.read_tag = tag;
    buffer_in.read_tag_parity = ~odd_parity_8(tag);
    buffer_in.read_address = 0;
    tick();
    buffer_in.read_valid = 0;
    tag_error_seen = 0;
    repeat(12) begin
      tick();
      tag_error_seen |= data_write_error;
    end
    require(tag_error_seen, "write-data tag parity error missing");

    reset_dut(1, 8);
    pulse_channel(CMD_READ, 64'h7400);
    wait_command("NRES-error", 64'h7400, tag);
    send_response(tag, NRES);
    response_error_seen = 0;
    repeat(16) begin
      tick();
      response_error_seen |= |command_response_error;
    end
    require(response_error_seen, "NRES response error missing");

    reset_dut(1, 8);
    pulse_channel(CMD_READ, 64'h7500);
    wait_command("FAULT-error", 64'h7500, tag);
    send_response(tag, FAULT);
    response_error_seen = 0;
    repeat(16) begin
      tick();
      response_error_seen |= |command_response_error;
    end
    require(response_error_seen, "FAULT response error missing");
    bins_hit++;
  endtask

  task automatic nlock_lifecycle_case;
    logic [0:7] tag;
    bit routed_seen;
    bit error_seen;
    bit restart_seen;

    reset_dut(1, 8);
    pulse_channel(CMD_READ, 64'h7600);
    wait_command("NLOCK-read", 64'h7600, tag);
    send_response(tag, NLOCK);
    routed_seen = 0;
    error_seen = 0;
    restart_seen = 0;
    repeat(100) begin
      tick();
      if(read_response.valid) begin
        routed_seen = 1;
        require(read_response.payload.cmd.tag == tag, "NLOCK routed tag");
        require(read_response.payload.response == NLOCK,
                "NLOCK routed response code");
      end
      error_seen |= |command_response_error;
      restart_seen |= command_out.valid && command_out.command == RESTART;
    end
    require(routed_seen, "NLOCK response was not routed");
    require(error_seen, "NLOCK error bit was not reported");
    require(!restart_seen, "NLOCK incorrectly entered restart");

    pulse_channel(CMD_READ, 64'h7700);
    wait_command("post-NLOCK-read", 64'h7700, tag);
    send_response(tag, DONE);
    wait_routed_response("post-NLOCK-read", CMD_READ, tag);
    bins_hit++;
  endtask

  task automatic buffer_pressure_case;
    bit command_pressure_seen;
    bit data_pressure_seen;

    reset_dut(1, 1);
    for(int index = 0; index < 96; index++) begin
      set_line(wed_command, CMD_WED, READ_CL_NA, 64'hc000 + index * 128, 128, STRICT);
      set_line(read_command, CMD_READ, READ_CL_NA, 64'hd000 + index * 128, 128, STRICT);
      set_line(write_command, CMD_WRITE, WRITE_NA, 64'he000 + index * 128, 128, STRICT);
      set_line(
        prefetch_read_command,
        CMD_PREFETCH_READ,
        TOUCH_I,
        64'hf000 + index * 128,
        128,
        STRICT
      );
      set_line(
        prefetch_write_command,
        CMD_PREFETCH_WRITE,
        TOUCH_I,
        64'h10000 + index * 128,
        128,
        STRICT
      );
      write_data_0.valid = 1;
      write_data_1.valid = 1;
      write_data_0.payload.cmd = write_command.payload.cmd;
      write_data_1.payload.cmd = write_command.payload.cmd;
      write_data_0.payload.data = '1;
      write_data_1.payload.data = '0;
      tick();
    end
    wed_command.valid = 0;
    read_command.valid = 0;
    write_command.valid = 0;
    prefetch_read_command.valid = 0;
    prefetch_write_command.valid = 0;
    write_data_0.valid = 0;
    write_data_1.valid = 0;
    tick(8);
    command_pressure_seen =
        command_status.wed_buffer.full ||
        command_status.read_buffer.alfull ||
        command_status.write_buffer.alfull ||
        command_status.prefetch_read_buffer.alfull ||
        command_status.prefetch_write_buffer.alfull;
    data_pressure_seen =
        write_data_status.buffer_0.alfull &&
        write_data_status.buffer_1.alfull;
    require(command_pressure_seen, "command-buffer pressure not reached");
    require(data_pressure_seen, "write-data pressure not reached");
    rstn = 0;
    tick(6);
    bins_hit++;
  endtask

  task automatic reset_no_leak_case;
    logic [0:7] tag;

    reset_dut(0, 4);
    pulse_channel(CMD_READ, 64'h8100);
    wait_command("pre-reset", 64'h8100, tag);
    rstn = 0;
    tick(8);
    require(!command_out.valid, "command valid leaked through reset");
    require(!read_response.valid && !write_response.valid && !wed_response.valid,
            "response valid leaked through reset");
    rstn = 1;
    enabled = 1;
    command_in.room = 4;
    configure.var1 = '0;
    configure.var1[62] = 1;
    tick(285);
    pulse_channel(CMD_WED, 64'h8200);
    wait_command("post-reset", 64'h8200, tag);
    require(tag == 0, "tag allocator did not restart from tag zero");
    send_response(tag, DONE);
    wait_routed_response("post-reset", CMD_WED, tag);
    bins_hit++;
  endtask

  task automatic credit_exhaustion_case;
    logic [0:7] issued_tags[0:2];
    logic [0:63] issued_addresses[0:2];
    int unsigned seen;

    reset_dut(1, 2);
    pulse_channel(CMD_READ, 64'h8800);
    pulse_channel(CMD_READ, 64'h8900);
    pulse_channel(CMD_READ, 64'h8a00);
    seen = 0;
    repeat(140) begin
      tick();
      if(command_out.valid) begin
        if(seen < 3) begin
          issued_tags[seen] = command_out.tag;
          issued_addresses[seen] = command_out.address;
        end
        seen++;
      end
    end
    if(seen != 2)
      $fatal(
        1,
        "afu_control requirement failed: credit exhaustion expected=2 actual=%0d",
        seen
      );
    assertions_checked++;
    require(issued_addresses[0] == 64'h8800, "credit command zero address");
    require(issued_addresses[1] == 64'h8900, "credit command one address");
    send_response(issued_tags[0], DONE);
    seen = 0;
    repeat(100) begin
      tick();
      if(command_out.valid) begin
        seen++;
        require(command_out.address == 64'h8a00, "credit recovery address");
        issued_tags[2] = command_out.tag;
      end
    end
    require(seen == 1, "credit return did not release exactly one command");
    send_response(issued_tags[1], DONE);
    send_response(issued_tags[2], DONE);
    bins_hit++;
  endtask

  task automatic tag_exhaustion_case;
    logic [0:7] allocated[0:255];
    logic [255:0] unique_tags;
    logic [0:7] recycled;
    int unsigned release_index;

    reset_dut(1, 8);
    unique_tags = '0;
    tag_capacity_observed = 0;
    while(tag_capacity_observed < 256) begin
      tag_command_id = '0;
      tag_command_id.aux_data = tag_capacity_observed;
      tag_command_valid = 1;
      #1;
      if(!tag_ready)
        break;
      allocated[tag_capacity_observed] = tag_command;
      require(!unique_tags[tag_command], "tag allocator duplicated an outstanding tag");
      unique_tags[tag_command] = 1;
      tick();
      tag_command_valid = 0;
      tag_capacity_observed++;
    end
    tag_command_valid = 0;
    tick(4);
    require(!tag_ready, "tag allocator did not report exhaustion");
    require(tag_capacity_observed > 0 && tag_capacity_observed <= TAG_COUNT,
            "tag allocator capacity outside declared range");

    release_index = tag_capacity_observed / 2;
    tag_response = allocated[release_index];
    tag_response_valid = 1;
    tick();
    tag_response_valid = 0;
    tick(4);
    tag_command_valid = 1;
    #1;
    require(tag_ready, "returned tag did not restore allocator readiness");
    recycled = tag_command;
    require(recycled == allocated[release_index], "returned tag was not safely reused");
    tick();
    tag_command_valid = 0;
    bins_hit++;
  endtask

  task automatic probe_fixed_arbitration;
    logic [0:63] observed[0:7];
    logic [0:63] expected[0:4];
    int unsigned seen;

    reset_dut(0, 8);
    set_line(wed_command, CMD_WED, READ_CL_NA, 64'h9000, 128, STRICT);
    set_line(prefetch_write_command, CMD_PREFETCH_WRITE, TOUCH_I, 64'h9100, 128, STRICT);
    set_line(write_command, CMD_WRITE, WRITE_NA, 64'h9200, 128, STRICT);
    set_line(prefetch_read_command, CMD_PREFETCH_READ, TOUCH_I, 64'h9300, 128, STRICT);
    set_line(read_command, CMD_READ, READ_CL_NA, 64'h9400, 128, STRICT);
    tick();
    wed_command.valid = 0;
    prefetch_write_command.valid = 0;
    write_command.valid = 0;
    prefetch_read_command.valid = 0;
    read_command.valid = 0;
    expected[0] = 64'h9000;
    expected[1] = 64'h9100;
    expected[2] = 64'h9200;
    expected[3] = 64'h9300;
    expected[4] = 64'h9400;
    seen = 0;
    repeat(160) begin
      tick();
      if(command_out.valid) begin
        if(seen < 8)
          observed[seen] = command_out.address;
        seen++;
      end
    end
    require(seen == 5, "fixed arbitration command count");
    for(int index = 0; index < 5; index++) begin
      if(observed[index] != expected[index])
        $fatal(
          1,
          "afu_control requirement failed: fixed arbitration index=%0d expected=%h actual=%h",
          index,
          expected[index],
          observed[index]
        );
      assertions_checked++;
    end
    $display("PASS afu_control_probe_fixed assertions=%0d", assertions_checked);
  endtask

  task automatic probe_round_robin_arbitration;
    logic [0:63] observed[0:7];
    logic [0:63] expected[0:4];
    int unsigned seen;

    reset_dut(1, 8);
    set_line(wed_command, CMD_WED, READ_CL_NA, 64'ha000, 128, STRICT);
    set_line(prefetch_write_command, CMD_PREFETCH_WRITE, TOUCH_I, 64'ha100, 128, STRICT);
    set_line(write_command, CMD_WRITE, WRITE_NA, 64'ha200, 128, STRICT);
    set_line(prefetch_read_command, CMD_PREFETCH_READ, TOUCH_I, 64'ha300, 128, STRICT);
    set_line(read_command, CMD_READ, READ_CL_NA, 64'ha400, 128, STRICT);
    tick();
    wed_command.valid = 0;
    prefetch_write_command.valid = 0;
    write_command.valid = 0;
    prefetch_read_command.valid = 0;
    read_command.valid = 0;
    expected[0] = 64'ha000;
    expected[1] = 64'ha100;
    expected[2] = 64'ha200;
    expected[3] = 64'ha300;
    expected[4] = 64'ha400;
    seen = 0;
    repeat(160) begin
      tick();
      if(command_out.valid) begin
        if(seen < 8)
          observed[seen] = command_out.address;
        seen++;
      end
    end
    require(seen == 5, "round-robin arbitration command count");
    for(int index = 0; index < 5; index++) begin
      if(observed[index] != expected[index])
        $fatal(
          1,
          "afu_control requirement failed: round-robin arbitration index=%0d expected=%h actual=%h",
          index,
          expected[index],
          observed[index]
        );
      assertions_checked++;
    end
    $display("PASS afu_control_probe_round_robin assertions=%0d", assertions_checked);
  endtask

  task automatic restart_case(
      input string name,
      input psl_response_t fault
  );
    logic [0:7] original_tag;
    logic [0:7] restart_tag;
    logic [0:7] replay_tag;
    bit restart_seen;
    bit replay_seen;

    reset_dut(1, 8);
    pulse_channel(CMD_READ, 64'hb000);
    wait_command({name, "-original"}, 64'hb000, original_tag);
    send_response(original_tag, fault);
    restart_seen = 0;
    restart_tag = 0;
    repeat(360) begin
      tick();
      if(command_out.valid && command_out.command == RESTART && !restart_seen) begin
        restart_seen = 1;
        restart_tag = command_out.tag;
        require(command_out.address == 64'hb000, {name, ": restart address"});
        require(command_out.abt == STRICT, {name, ": restart ABT"});
      end
    end
    require(restart_seen, {name, ": restart command missing"});
    send_response(restart_tag, DONE);
    replay_seen = 0;
    replay_tag = 0;
    repeat(420) begin
      tick();
      if(
        command_out.valid &&
        command_out.command == READ_CL_NA &&
        command_out.address == 64'hb000
      ) begin
        require(!replay_seen, {name, ": original command replayed more than once"});
        replay_seen = 1;
        replay_tag = command_out.tag;
      end
    end
    require(replay_seen, {name, ": original command was not replayed"});
    send_response(replay_tag, DONE);
  endtask

  task automatic probe_restart;
    restart_case("PAGED", PAGED);
    restart_case("AERROR", AERROR);
    restart_case("DERROR", DERROR);
    $display("PASS afu_control_probe_restart assertions=%0d", assertions_checked);
  endtask

  initial begin
    bins_hit = 0;
    assertions_checked = 0;
    tag_capacity_observed = 0;
    rstn = 0;
    clear_inputs();

    if($test$plusargs("PROBE_FIXED_ARBITRATION")) begin
      probe_fixed_arbitration();
      $finish;
    end
    if($test$plusargs("PROBE_ROUND_ROBIN_ARBITRATION")) begin
      probe_round_robin_arbitration();
      $finish;
    end
    if($test$plusargs("PROBE_CREDIT_EXHAUSTION")) begin
      credit_exhaustion_case();
      $display("PASS afu_control_probe_credit assertions=%0d", assertions_checked);
      $finish;
    end
    if($test$plusargs("PROBE_RESTART")) begin
      probe_restart();
      $finish;
    end

    coverage_toggle_sweep();
    sequential_channels(0);
    sequential_channels(1);
    response_reorder_case();
    error_case();
    nlock_lifecycle_case();
    buffer_pressure_case();
    reset_no_leak_case();
    read_data_routing_case();
    tag_exhaustion_case();
    probe_fixed_arbitration();
    probe_round_robin_arbitration();
    credit_exhaustion_case();
    probe_restart();
    require(bins_hit == 18, "functional bin denominator");
    $display(
      "PASS afu_control_integration bins=%0d/18 assertions=%0d tag_capacity=%0d",
      bins_hit,
      assertions_checked,
      tag_capacity_observed
    );
    $finish;
  end

endmodule
