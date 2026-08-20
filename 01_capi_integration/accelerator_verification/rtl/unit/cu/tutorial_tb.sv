module tutorial_tb;

  import GLOBALS_AFU_PKG::*;
  import GLOBALS_CU_PKG::*;
  import CAPI_PKG::*;
  import WED_PKG::*;
  import AFU_PKG::*;
  import CU_PKG::*;

  logic clock = 0;
  logic rstn;
  logic read_enable;
  logic write_enable;
  WEDInterface wed;
  ResponseBufferLine read_response;
  ResponseBufferLine write_response;
  BufferStatus read_status;
  BufferStatus write_status;
  CommandBufferLine read_command;
  CommandBufferLine write_command;
  ReadWriteDataLine read_data_0;
  ReadWriteDataLine read_data_1;
  ReadWriteDataLine write_data_0;
  ReadWriteDataLine write_data_1;
  logic [0:(ARRAY_SIZE_BITS-1)] read_count;
  logic [0:(ARRAY_SIZE_BITS-1)] write_count;

  logic full_rstn;
  logic full_enabled;
  WEDInterface full_wed;
  ResponseBufferLine full_read_response;
  ResponseBufferLine full_write_response;
  ReadWriteDataLine full_read_data_0;
  ReadWriteDataLine full_read_data_1;
  BufferStatus full_read_status;
  BufferStatus full_write_status;
  cu_configure_type full_configure;
  cu_return_type full_return;
  logic full_done;
  logic [0:63] full_status;
  CommandBufferLine full_read_command;
  CommandBufferLine full_prefetch_read_command;
  CommandBufferLine full_prefetch_write_command;
  CommandBufferLine full_write_command;
  ReadWriteDataLine full_write_data_0;
  ReadWriteDataLine full_write_data_1;

  int unsigned bins_hit;
  int unsigned assertions_checked;

  always #5 clock = ~clock;

  read_engine read_dut (
    .clock(clock),
    .rstn(rstn),
    .read_enabled_in(read_enable),
    .wed_request_in(wed),
    .read_response_in(read_response),
    .read_command_buffer_status(read_status),
    .write_command_buffer_status(write_status),
    .read_command_out(read_command),
    .read_job_counter_done(read_count)
  );

  write_engine write_dut (
    .clock(clock),
    .rstn(rstn),
    .write_enabled_in(write_enable),
    .wed_request_in(wed),
    .write_response_in(write_response),
    .read_data_0_in(read_data_0),
    .read_data_1_in(read_data_1),
    .write_data_0_out(write_data_0),
    .write_data_1_out(write_data_1),
    .write_command_buffer_status(write_status),
    .write_command_out(write_command),
    .write_job_counter_done(write_count)
  );

  cu_control full_dut (
    .clock(clock),
    .rstn_in(full_rstn),
    .enabled_in(full_enabled),
    .wed_request_in(full_wed),
    .read_response_in(full_read_response),
    .prefetch_read_response_in('0),
    .prefetch_write_response_in('0),
    .write_response_in(full_write_response),
    .read_data_0_in(full_read_data_0),
    .read_data_1_in(full_read_data_1),
    .read_buffer_status(full_read_status),
    .prefetch_read_buffer_status('0),
    .prefetch_write_buffer_status('0),
    .write_buffer_status(full_write_status),
    .cu_configure(full_configure),
    .cu_return(full_return),
    .cu_done(full_done),
    .cu_status(full_status),
    .read_command_out(full_read_command),
    .prefetch_read_command_out(full_prefetch_read_command),
    .prefetch_write_command_out(full_prefetch_write_command),
    .write_command_out(full_write_command),
    .write_data_0_out(full_write_data_0),
    .write_data_1_out(full_write_data_1)
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
      $fatal(1, "tutorial requirement failed: %s", message);
  endtask

  function automatic logic odd_parity_512(input logic [0:511] value);
    return logic'(($countones(value) + 1) % 2);
  endfunction

  task automatic clear_direct_inputs;
    wed = '0;
    read_response = '0;
    write_response = '0;
    read_status = '0;
    write_status = '0;
    read_data_0 = '0;
    read_data_1 = '0;
    read_enable = 0;
    write_enable = 0;
  endtask

  task automatic reset_direct(input logic enable_read, input logic enable_write);
    rstn = 0;
    clear_direct_inputs();
    tick(4);
    rstn = 1;
    read_enable = enable_read;
    write_enable = enable_write;
    tick(5);
  endtask

  task automatic drive_direct_read_completion(
      input CommandTagLine completion_cmd,
      input logic [0:511] lower,
      input logic [0:511] upper
  );
    read_data_0.payload.cmd = completion_cmd;
    read_data_1.payload.cmd = completion_cmd;
    read_data_0.payload.data = lower;
    read_data_1.payload.data = upper;
    read_data_0.valid = 1;
    read_data_1.valid = 0;
    tick();
    read_data_0.valid = 0;
    read_data_1.valid = 1;
    tick();
    read_data_1.valid = 0;
  endtask

  task automatic read_case(
      input string name,
      input int unsigned elements,
      input logic stall_first
  );
    int unsigned expected_commands;
    int unsigned seen;
    int unsigned expected_real_size;
    logic [0:63] base;

    reset_direct(1, 0);
    base = 64'h0000_0000_1000_0000;
    wed.valid = 1;
    wed.payload.wed.size_send = elements;
    wed.payload.wed.size_recive = elements;
    wed.payload.wed.array_send = base;
    if(stall_first) begin
      read_status.alfull = 1;
      tick(8);
      require(!read_command.valid, {name, ": read command escaped read backpressure"});
      read_status.alfull = 0;
    end

    expected_commands = (elements + CACHELINE_ARRAY_NUM - 1) / CACHELINE_ARRAY_NUM;
    seen = 0;
    repeat(120) begin
      tick();
      if(read_command.valid) begin
        expected_real_size =
          (elements - seen * CACHELINE_ARRAY_NUM > CACHELINE_ARRAY_NUM) ?
          CACHELINE_ARRAY_NUM : elements - seen * CACHELINE_ARRAY_NUM;
        require(read_command.payload.address == base + seen * CACHELINE_SIZE,
                {name, ": read address"});
        require(read_command.payload.cmd.address_offset == seen * CACHELINE_SIZE,
                {name, ": read offset"});
        require(read_command.payload.cmd.real_size == expected_real_size,
                {name, ": read real_size"});
        require(read_command.payload.cmd.real_size_bytes == cmd_size_calculate(expected_real_size),
                {name, ": read byte size metadata"});
        require(read_command.payload.size == cmd_size_calculate(expected_real_size),
                {name, ": read command size"});
        require(read_command.payload.command ==
                ((elements - seen * CACHELINE_ARRAY_NUM > CACHELINE_ARRAY_NUM) ?
                 READ_CL_NA : READ_PNA),
                {name, ": read command"});
        require(read_command.payload.abt == STRICT, {name, ": read ABT"});
        require(read_command.payload.cmd.cmd_type == CMD_READ, {name, ": read type"});
        seen++;
      end
    end
    require(seen == expected_commands, {name, ": read command count"});
    if(elements == 0)
      require(read_count == 0, {name, ": zero counter"});
    bins_hit++;
  endtask

  task automatic write_case(
      input string name,
      input int unsigned elements,
      input logic [0:63] offset
  );
    logic [0:511] lower;
    logic [0:511] upper;
    CommandTagLine completion_cmd;
    int unsigned seen;

    reset_direct(0, 1);
    wed.valid = 1;
    wed.payload.wed.size_send = elements;
    wed.payload.wed.size_recive = elements;
    wed.payload.wed.array_receive = 64'h0000_0000_2000_0000;
    lower = {8{64'h0123_4567_89ab_cdef}};
    upper = {8{64'hfedc_ba98_7654_3210}};
    completion_cmd = 0;
    completion_cmd.real_size = elements;
    completion_cmd.real_size_bytes = cmd_size_calculate(elements);
    completion_cmd.address_offset = offset;
    drive_direct_read_completion(completion_cmd, lower, upper);

    seen = 0;
    repeat(40) begin
      tick();
      if(write_command.valid) begin
        seen++;
        require(write_command.payload.command == WRITE_NA, {name, ": write command"});
        require(write_command.payload.address ==
                64'h0000_0000_2000_0000 + offset, {name, ": write address"});
        require(write_command.payload.size == cmd_size_calculate(elements),
                {name, ": write size"});
        require(write_command.payload.cmd.real_size == elements,
                {name, ": write real_size"});
        require(write_data_0.valid && write_data_1.valid, {name, ": write data valids"});
        require(write_data_0.payload.data == lower, {name, ": lower data"});
        require(write_data_1.payload.data == upper, {name, ": upper data"});
        require(odd_parity_512(write_data_0.payload.data) == odd_parity_512(lower),
                {name, ": lower parity preservation"});
        require(odd_parity_512(write_data_1.payload.data) == odd_parity_512(upper),
                {name, ": upper parity preservation"});
        write_response.valid = 1;
        write_response.payload.cmd = write_command.payload.cmd;
      end else begin
        write_response.valid = 0;
      end
    end
    require(seen == 1, {name, ": write command count"});
    tick(5);
    require(write_count == elements, {name, ": write response counter"});
    bins_hit++;
  endtask

  task automatic clear_full_inputs;
    full_enabled = 0;
    full_wed = '0;
    full_read_response = '0;
    full_write_response = '0;
    full_read_data_0 = '0;
    full_read_data_1 = '0;
    full_read_status = '0;
    full_write_status = '0;
    full_configure = '0;
  endtask

  task automatic coverage_toggle_sweep;
    rstn = 0;
    full_rstn = 0;
    clear_direct_inputs();
    clear_full_inputs();
    tick(2);

    read_enable = 1;
    write_enable = 1;
    wed = '1;
    read_response = '1;
    write_response = '1;
    read_status = '1;
    write_status = '1;
    read_data_0 = '1;
    read_data_1 = '1;
    full_enabled = 1;
    full_wed = '1;
    full_read_response = '1;
    full_write_response = '1;
    full_read_data_0 = '1;
    full_read_data_1 = '1;
    full_read_status = '1;
    full_write_status = '1;
    full_configure = '1;
    tick(2);

    clear_direct_inputs();
    clear_full_inputs();
    tick(2);

    rstn = 1;
    full_rstn = 1;
    read_enable = 1;
    write_enable = 1;
    wed = '1;
    read_response = '1;
    write_response = '1;
    read_data_0 = '1;
    read_data_1 = '1;
    read_status = '1;
    write_status = '1;
    full_enabled = 1;
    full_wed = '1;
    full_read_response = '1;
    full_write_response = '1;
    full_read_data_0 = '1;
    full_read_data_1 = '1;
    full_read_status = '1;
    full_write_status = '1;
    full_configure = '1;
    tick(8);
    read_enable = 0;
    write_enable = 0;
    full_enabled = 0;
    full_configure = 0;
    tick(4);
    rstn = 0;
    full_rstn = 0;
    clear_direct_inputs();
    clear_full_inputs();
    tick(3);
  endtask

  task automatic full_copy_case(input string name, input int unsigned elements);
    logic [0:511] lower;
    logic [0:511] upper;
    ReadWriteDataLine delayed_upper;
    bit read_seen;
    bit write_seen;
    bit done_seen;
    bit upper_pending;

    full_rstn = 0;
    clear_full_inputs();
    tick(5);
    full_rstn = 1;
    full_enabled = 1;
    tick(3);
    full_configure.var1 = 64'h1;
    full_wed.valid = 1;
    full_wed.payload.wed.size_send = elements;
    full_wed.payload.wed.size_recive = elements;
    full_wed.payload.wed.array_send = 64'h3000_0000;
    full_wed.payload.wed.array_receive = 64'h4000_0000;
    lower = {8{64'h1357_9bdf_2468_ace0}};
    upper = {8{64'h0eca_8642_fdb9_7531}};
    read_seen = 0;
    write_seen = 0;
    done_seen = 0;
    upper_pending = 0;
    delayed_upper = 0;

    repeat(180) begin
      tick();
      full_read_response.valid = 0;
      full_write_response.valid = 0;
      full_read_data_0.valid = 0;
      full_read_data_1.valid = 0;
      if(upper_pending) begin
        full_read_data_1 = delayed_upper;
        upper_pending = 0;
      end
      if(full_read_command.valid && !read_seen) begin
        read_seen = 1;
        full_read_data_0.valid = 1;
        full_read_data_0.payload.cmd = full_read_command.payload.cmd;
        full_read_data_0.payload.data = lower;
        delayed_upper.valid = 1;
        delayed_upper.payload.cmd = full_read_command.payload.cmd;
        delayed_upper.payload.data = upper;
        upper_pending = 1;
        full_read_response.valid = 1;
        full_read_response.payload.cmd = full_read_command.payload.cmd;
        full_read_response.payload.response = DONE;
        full_read_response.payload.response_credits = 1;
      end
      if(full_write_command.valid && !write_seen) begin
        write_seen = 1;
        require(full_write_command.payload.address == 64'h4000_0000,
                {name, ": full CU write address"});
        require(full_write_data_0.payload.data == lower,
                {name, ": full CU lower data"});
        require(full_write_data_1.payload.data == upper,
                {name, ": full CU upper data"});
        full_write_response.valid = 1;
        full_write_response.payload.cmd = full_write_command.payload.cmd;
        full_write_response.payload.response = DONE;
        full_write_response.payload.response_credits = 1;
      end
      done_seen |= full_done;
    end
    if(elements == 0) begin
      require(!read_seen && !write_seen, {name, ": zero emitted command"});
    end else begin
      require(read_seen, {name, ": full CU read missing"});
      require(write_seen, {name, ": full CU write missing"});
    end
    require(done_seen, {name, ": full CU completion missing"});
    require(full_return.var1 == elements, {name, ": full CU read counter"});
    require(full_return.var2 == elements, {name, ": full CU write counter"});
    bins_hit++;
  endtask

  task automatic probe_write_backpressure;
    logic [0:63] offsets [0:2];
    logic [0:511] lower [0:2];
    logic [0:511] upper [0:2];
    int unsigned sizes [0:2];
    int unsigned commands_seen;
    int unsigned responses_sent;

    reset_direct(0, 1);
    wed.valid = 1;
    wed.payload.wed.size_send = 6;
    wed.payload.wed.size_recive = 6;
    wed.payload.wed.array_receive = 64'h5000_0000;
    offsets[0] = 0;
    offsets[1] = CACHELINE_SIZE;
    offsets[2] = 2 * CACHELINE_SIZE;
    sizes[0] = 1;
    sizes[1] = 2;
    sizes[2] = 3;
    lower[0] = {8{64'h1111_1111_1111_1111}};
    lower[1] = {8{64'h2222_2222_2222_2222}};
    lower[2] = {8{64'h3333_3333_3333_3333}};
    upper[0] = {8{64'haaaa_aaaa_aaaa_aaaa}};
    upper[1] = {8{64'hbbbb_bbbb_bbbb_bbbb}};
    upper[2] = {8{64'hcccc_cccc_cccc_cccc}};
    write_status.alfull = 1;
    for(int tuple = 0; tuple < 3; tuple++) begin
      read_data_0.valid = 1;
      read_data_1.valid = tuple != 0;
      read_data_0.payload.cmd.real_size = sizes[tuple];
      read_data_0.payload.cmd.real_size_bytes =
          cmd_size_calculate(sizes[tuple]);
      read_data_0.payload.cmd.address_offset = offsets[tuple];
      read_data_0.payload.data = lower[tuple];
      if(tuple != 0) begin
        read_data_1.payload.cmd.real_size = sizes[tuple - 1];
        read_data_1.payload.cmd.real_size_bytes =
            cmd_size_calculate(sizes[tuple - 1]);
        read_data_1.payload.cmd.address_offset = offsets[tuple - 1];
        read_data_1.payload.data = upper[tuple - 1];
      end
      tick();
    end
    read_data_0.valid = 0;
    read_data_1.valid = 1;
    read_data_1.payload.cmd.real_size = sizes[2];
    read_data_1.payload.cmd.real_size_bytes = cmd_size_calculate(sizes[2]);
    read_data_1.payload.cmd.address_offset = offsets[2];
    read_data_1.payload.data = upper[2];
    tick();
    read_data_1.valid = 0;
    repeat(20) begin
      tick();
      require(!write_command.valid,
              "write command escaped write_command_buffer_status.alfull");
    end
    write_status.alfull = 0;
    commands_seen = 0;
    responses_sent = 0;
    repeat(60) begin
      tick();
      write_response.valid = 0;
      if(write_command.valid) begin
        require(commands_seen < 3, "queued write command count overflow");
        require(write_data_0.valid && write_data_1.valid,
                "released write command lost data valids");
        require(
          write_command.payload.address ==
              64'h5000_0000 + offsets[commands_seen],
          "queued write address order"
        );
        require(
          write_command.payload.cmd.address_offset == offsets[commands_seen],
          "queued write metadata order"
        );
        require(
          write_command.payload.cmd.real_size == sizes[commands_seen],
          "queued write size order"
        );
        require(
          write_data_0.payload.data == lower[commands_seen],
          "queued lower write data order"
        );
        require(
          write_data_1.payload.data == upper[commands_seen],
          "queued upper write data order"
        );
        write_response.valid = 1;
        write_response.payload.cmd = write_command.payload.cmd;
        write_response.payload.response = DONE;
        commands_seen++;
        responses_sent++;
      end
    end
    write_response.valid = 0;
    tick(5);
    require(commands_seen == 3,
            "backpressured writes were not released exactly once");
    require(responses_sent == 3,
            "backpressured writes did not receive exactly one response each");
    require(write_count == 6,
            "backpressured write responses were not counted exactly once");
    bins_hit++;
    $display(
      "PASS tutorial_probe_write_backpressure commands=3 responses=3 assertions=%0d",
      assertions_checked
    );
  endtask

  task automatic metadata_and_status_coverage_case;
    CommandTagLine completion_cmd;
    int unsigned commands_seen;

    reset_direct(1, 1);
    read_status = '1;
    write_status = '1;
    tick(5);
    read_status = 0;
    write_status = 0;
    tick(5);

    wed.valid = 1;
    wed.payload.wed.size_send = 8'hff;
    wed.payload.wed.size_recive = 8'hff;
    wed.payload.wed.array_receive = 64'h6a00_0000;
    completion_cmd = 0;
    completion_cmd.cacheline_offset = 8'hff;
    completion_cmd.address_offset = 64'hffff_ffff_ffff_ff00;
    completion_cmd.real_size = 8'hff;
    completion_cmd.real_size_bytes = 8'hff;
    drive_direct_read_completion(completion_cmd, '1, '1);
    commands_seen = 0;
    repeat(50) begin
      tick();
      commands_seen += write_command.valid;
    end
    require(commands_seen == 1, "tutorial metadata write count");
    bins_hit++;
  endtask

  initial begin
    bins_hit = 0;
    assertions_checked = 0;
    rstn = 0;
    full_rstn = 0;
    clear_direct_inputs();
    clear_full_inputs();
    coverage_toggle_sweep();

    if($test$plusargs("PROBE_WRITE_BACKPRESSURE")) begin
      probe_write_backpressure();
      $finish;
    end

    read_case("zero", 0, 0);
    read_case("single", 1, 1);
    read_case("cacheline-tail", CACHELINE_ARRAY_NUM, 0);
    read_case("multiline", CACHELINE_ARRAY_NUM + 1, 0);
    write_case("single-write", 1, 0);
    write_case("tail-write", CACHELINE_ARRAY_NUM, CACHELINE_SIZE);
    full_copy_case("full-zero", 0);
    full_copy_case("full-copy-first", 1);
    full_copy_case("full-copy-repeat", 1);
    probe_write_backpressure();
    metadata_and_status_coverage_case();

    require(bins_hit == 11, "functional bin denominator");
    $display(
      "PASS tutorial_cu bins=%0d/11 assertions=%0d",
      bins_hit,
      assertions_checked
    );
    $finish;
  end

endmodule
