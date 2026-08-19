module cached_afu_tb;

  import GLOBALS_AFU_PKG::*;
  import GLOBALS_CU_PKG::*;
  import CAPI_PKG::*;
  import WED_PKG::*;
  import AFU_PKG::*;
  import CU_PKG::*;

  logic clock = 0;
  logic timebase_request;
  logic parity_enabled;
  JobInterfaceInput job_in;
  JobInterfaceOutput job_out;
  CommandInterfaceInput command_in;
  CommandInterfaceOutput command_out;
  BufferInterfaceInput buffer_in;
  BufferInterfaceOutput buffer_out;
  ResponseInterface response;
  MMIOInterfaceInput mmio_in;
  MMIOInterfaceOutput mmio_out;

  int unsigned bins_hit;
  int unsigned assertions_checked;

  always #5 clock = ~clock;

  cached_afu dut (
    .clock(clock),
    .timebase_request(timebase_request),
    .parity_enabled(parity_enabled),
    .job_in(job_in),
    .job_out(job_out),
    .command_in(command_in),
    .command_out(command_out),
    .buffer_in(buffer_in),
    .buffer_out(buffer_out),
    .response(response),
    .mmio_in(mmio_in),
    .mmio_out(mmio_out)
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
      $fatal(1, "cached_afu requirement failed: %s", message);
  endtask

  function automatic logic odd_parity_8(input logic [0:7] value);
    return logic'(($countones(value) + 1) % 2);
  endfunction

  function automatic logic odd_parity_24(input logic [0:23] value);
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
    job_in = '0;
    command_in = '0;
    buffer_in = '0;
    response = '0;
    mmio_in = '0;
  endtask

  task automatic coverage_toggle_sweep;
    clear_inputs();
    tick(3);
    job_in = '1;
    command_in = '1;
    buffer_in = '1;
    response = '1;
    mmio_in = '1;
    tick(4);
    clear_inputs();
    tick(4);
    send_job(RESET, 0);
    tick(30);
  endtask

  task automatic send_job(
      input job_command_t command,
      input logic [0:63] address
  );
    job_in.valid = 1;
    job_in.command = command;
    job_in.command_parity = odd_parity_8(command);
    job_in.address = address;
    job_in.address_parity = odd_parity_64(address);
    tick();
    job_in.valid = 0;
  endtask

  task automatic mmio_write(
      input logic [0:23] address,
      input logic [0:63] data
  );
    bit ack_seen;
    mmio_in = '0;
    mmio_in.valid = 1;
    mmio_in.read = 0;
    mmio_in.doubleword = 1;
    mmio_in.address = address;
    mmio_in.address_parity = odd_parity_24(address);
    mmio_in.data = data;
    mmio_in.data_parity = odd_parity_64(data);
    tick();
    mmio_in.valid = 0;
    ack_seen = 0;
    repeat(20) begin
      tick();
      ack_seen |= mmio_out.ack;
    end
    require(ack_seen, $sformatf("MMIO write ack address=%h", address));
  endtask

  task automatic mmio_read(
      input logic [0:23] address,
      output logic [0:63] data
  );
    bit ack_seen;
    mmio_in = '0;
    mmio_in.valid = 1;
    mmio_in.read = 1;
    mmio_in.doubleword = 1;
    mmio_in.address = address;
    mmio_in.address_parity = odd_parity_24(address);
    mmio_in.data = 0;
    mmio_in.data_parity = odd_parity_64(0);
    tick();
    mmio_in.valid = 0;
    ack_seen = 0;
    data = 0;
    repeat(20) begin
      tick();
      if(mmio_out.ack) begin
        ack_seen = 1;
        data = mmio_out.data;
        require(mmio_out.data_parity == odd_parity_64(mmio_out.data),
                "MMIO read parity");
      end
    end
    require(ack_seen, $sformatf("MMIO read ack address=%h", address));
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

  task automatic request_write_half(
      input logic [0:7] tag,
      input logic [0:5] half,
      input logic [0:511] expected
  );
    buffer_in.read_valid = 1;
    buffer_in.read_tag = tag;
    buffer_in.read_tag_parity = odd_parity_8(tag);
    buffer_in.read_address = half;
    tick();
    buffer_in.read_valid = 0;
    tick(buffer_out.read_latency + 4);
    require(buffer_out.read_data == expected,
            $sformatf("write buffer half=%0d data", half));
    require(buffer_out.read_parity == odd_parity_512(expected),
            $sformatf("write buffer half=%0d parity", half));
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

  task automatic wait_for_command(
      input string name,
      input afu_command_t expected_command,
      input logic [0:63] expected_address,
      output logic [0:7] tag
  );
    bit found;
    found = 0;
    tag = 0;
    repeat(500) begin
      tick();
      if(command_out.valid && !found) begin
        found = 1;
        tag = command_out.tag;
        require(command_out.command == expected_command, {name, ": command"});
        require(command_out.address == expected_address, {name, ": address"});
        require(command_out.tag_parity == odd_parity_8(command_out.tag),
                {name, ": tag parity"});
        require(command_out.command_parity == odd_parity_13(command_out.command),
                {name, ": command parity"});
        require(command_out.address_parity == odd_parity_64(command_out.address),
                {name, ": address parity"});
      end
    end
    require(found, {name, ": command missing"});
  endtask

  function automatic logic odd_parity_13(input logic [0:12] value);
    return logic'(($countones(value) + 1) % 2);
  endfunction

  task automatic configure_accelerator;
    logic [0:63] afu_word;
    logic [0:63] cu_word;

    afu_word = '0;
    afu_word[62] = 1;
    cu_word = '0;
    cu_word[22] = 1;
    cu_word[23] = 1;
    mmio_write(AFU_CONFIGURE, afu_word);
    mmio_write(CU_CONFIGURE, cu_word);
    mmio_write(CU_CONFIGURE_3, 1);
    mmio_write(CU_CONFIGURE_4, 1);
  endtask

  task automatic run_copy_job(
      input string name,
      input logic [0:63] wed_address,
      input logic [0:63] source_address,
      input logic [0:63] destination_address,
      input logic [0:511] lower,
      input logic [0:511] upper
  );
    logic [0:1023] wed_cacheline;
    logic [0:7] wed_tag;
    logic [0:7] read_tag;
    logic [0:7] write_tag;
    logic [0:63] done_1;
    logic [0:63] done_2;
    bit running_seen;

    send_job(RESET, 0);
    tick(30);
    send_job(START, wed_address);
    running_seen = 0;
    repeat(80) begin
      tick();
      running_seen |= job_out.running;
    end
    require(running_seen, {name, ": job did not enter running state"});
    require(parity_enabled, {name, ": parity not enabled"});
    require(!timebase_request, {name, ": unexpected timebase request"});

    command_in.room = 8;
    configure_accelerator();
    wait_for_command(name, READ_CL_NA, wed_address, wed_tag);

    wed_cacheline = '0;
    wed_cacheline[0:63] = swap_endianness_double_word(1);
    wed_cacheline[64:127] = swap_endianness_double_word(1);
    wed_cacheline[128:191] = swap_endianness_double_word(source_address);
    wed_cacheline[192:255] = swap_endianness_double_word(destination_address);
    send_buffer_half(wed_tag, 1, wed_cacheline[512:1023]);
    send_buffer_half(wed_tag, 0, wed_cacheline[0:511]);
    tick(6);
    send_response(wed_tag, DONE);

    wait_for_command(name, READ_PNA, source_address, read_tag);
    send_buffer_half(read_tag, 1, upper);
    send_buffer_half(read_tag, 0, lower);
    tick(6);
    send_response(read_tag, DONE);

    wait_for_command(name, WRITE_NA, destination_address, write_tag);
    request_write_half(write_tag, 0, lower);
    request_write_half(write_tag, 1, upper);
    send_response(write_tag, DONE);
    tick(120);

    mmio_read(CU_RETURN_DONE, done_1);
    mmio_read(CU_RETURN_DONE_2, done_2);
    require(done_1 == 1, {name, ": write completion counter"});
    require(done_2 == 1, {name, ": read completion counter"});
    mmio_write(CU_RETURN_DONE_ACK, 1);
    tick(20);
    send_job(RESET, 0);
    tick(40);
    require(!command_out.valid, {name, ": command leaked after completion reset"});
    bins_hit++;
  endtask

  task automatic cached_error_case;
    bit error_seen;

    send_job(RESET, 0);
    tick(30);
    job_in.valid = 1;
    job_in.command = START;
    job_in.command_parity = ~odd_parity_8(START);
    job_in.address = 64'h1400_0000;
    job_in.address_parity = ~odd_parity_64(64'h1400_0000);
    tick();
    job_in.valid = 0;
    error_seen = 0;
    repeat(80) begin
      tick();
      error_seen |= |dut.report_errors;
    end
    require(error_seen, "cached AFU did not aggregate job parity error");
    mmio_write(ERROR_REG_ACK, 1);
    send_job(RESET, 0);
    tick(40);
    bins_hit++;
  endtask

  initial begin
    bins_hit = 0;
    assertions_checked = 0;
    clear_inputs();
    command_in.room = 8;
    tick(10);
    coverage_toggle_sweep();

    run_copy_job(
      "copy-first",
      64'h0000_0000_1000_0000,
      64'h0000_0000_2000_0000,
      64'h0000_0000_3000_0000,
      {8{64'h0123_4567_89ab_cdef}},
      {8{64'hfedc_ba98_7654_3210}}
    );
    run_copy_job(
      "copy-repeat",
      64'h0000_0000_1100_0000,
      64'h0000_0000_2100_0000,
      64'h0000_0000_3100_0000,
      {8{64'ha5a5_5a5a_dead_beef}},
      {8{64'h5a5a_a5a5_cafe_f00d}}
    );
    cached_error_case();
    require(bins_hit == 3, "functional bin denominator");
    $display(
      "PASS cached_afu_integration bins=%0d/3 assertions=%0d",
      bins_hit,
      assertions_checked
    );
    $finish;
  end

endmodule
