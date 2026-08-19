module memcpy_tb;

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
  logic prefetch_read_enable;
  logic prefetch_write_enable;
  WEDInterface wed;
  logic [0:63] configure;
  logic [0:63] tlb_size;
  logic [0:63] max_tlb_requests;
  ResponseBufferLine read_response;
  ResponseBufferLine write_response;
  ResponseBufferLine prefetch_read_response;
  ResponseBufferLine prefetch_write_response;
  ReadWriteDataLine read_data_in_0;
  ReadWriteDataLine read_data_in_1;
  ReadWriteDataLine read_data_out_0;
  ReadWriteDataLine read_data_out_1;
  ReadWriteDataLine write_data_in_0;
  ReadWriteDataLine write_data_in_1;
  ReadWriteDataLine write_data_out_0;
  ReadWriteDataLine write_data_out_1;
  BufferStatus read_command_status;
  BufferStatus read_data_status;
  BufferStatus write_command_status;
  BufferStatus prefetch_read_status;
  BufferStatus prefetch_write_status;
  BufferStatus write_data_status;
  CommandBufferLine read_command;
  CommandBufferLine write_command;
  CommandBufferLine prefetch_read_command;
  CommandBufferLine prefetch_write_command;
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

  cu_data_read_engine_control read_dut (
    .clock(clock),
    .rstn(rstn),
    .read_enabled_in(read_enable),
    .prefetch_enabled_in(prefetch_read_enable),
    .wed_request_in(wed),
    .cu_configure(configure),
    .read_response_in(read_response),
    .read_data_0_in(read_data_in_0),
    .read_data_1_in(read_data_in_1),
    .read_command_buffer_status(read_command_status),
    .read_data_out_buffer_status(read_data_status),
    .prefetch_response_in(prefetch_read_response),
    .prefetch_command_buffer_status(prefetch_read_status),
    .tlb_size(tlb_size),
    .max_tlb_cl_requests(max_tlb_requests),
    .prefetch_command_out(prefetch_read_command),
    .read_command_out(read_command),
    .read_data_0_out(read_data_out_0),
    .read_data_1_out(read_data_out_1),
    .read_job_counter_done(read_count)
  );

  cu_data_write_engine_control write_dut (
    .clock(clock),
    .rstn(rstn),
    .write_enabled_in(write_enable),
    .prefetch_enabled_in(prefetch_write_enable),
    .wed_request_in(wed),
    .cu_configure(configure),
    .write_response_in(write_response),
    .write_data_0_in(write_data_in_0),
    .write_data_1_in(write_data_in_1),
    .write_command_buffer_status(write_command_status),
    .prefetch_response_in(prefetch_write_response),
    .prefetch_command_buffer_status(prefetch_write_status),
    .tlb_size(tlb_size),
    .max_tlb_cl_requests(max_tlb_requests),
    .prefetch_command_out(prefetch_write_command),
    .write_data_in_buffer_status(write_data_status),
    .write_command_out(write_command),
    .write_data_0_out(write_data_out_0),
    .write_data_1_out(write_data_out_1),
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
      $fatal(1, "memcpy requirement failed: %s", message);
  endtask

  task automatic clear_direct_inputs;
    read_enable = 0;
    write_enable = 0;
    prefetch_read_enable = 0;
    prefetch_write_enable = 0;
    wed = '0;
    configure = '0;
    tlb_size = 64;
    max_tlb_requests = 64;
    read_response = '0;
    write_response = '0;
    prefetch_read_response = '0;
    prefetch_write_response = '0;
    read_data_in_0 = '0;
    read_data_in_1 = '0;
    write_data_in_0 = '0;
    write_data_in_1 = '0;
    read_command_status = '0;
    read_data_status = '0;
    write_command_status = '0;
    prefetch_read_status = '0;
    prefetch_write_status = '0;
  endtask

  task automatic reset_direct(input logic enable_read, input logic enable_write);
    rstn = 0;
    clear_direct_inputs();
    tick(5);
    rstn = 1;
    read_enable = enable_read;
    write_enable = enable_write;
    tick(6);
  endtask

  task automatic read_case(
      input string name,
      input int unsigned elements,
      input logic cached,
      input logic [0:2] cabt_bits,
      input logic prefetch,
      input logic stall_first
  );
    int unsigned read_seen;
    int unsigned prefetch_seen;
    int unsigned remaining;
    int unsigned expected_real_size;
    trans_order_behavior_t expected_abt;
    logic [0:63] base;

    reset_direct(1, 0);
    base = 64'h0000_0000_1100_0080;
    configure = '0;
    configure[0:2] = cabt_bits;
    configure[3] = cached;
    prefetch_read_enable = prefetch;
    wed.valid = 1;
    wed.payload.wed.size_send = elements;
    wed.payload.wed.size_recive = elements;
    wed.payload.wed.array_send = base;
    expected_abt = map_CABT(cabt_bits);
    if(stall_first) begin
      read_command_status.alfull = 1;
      tick(10);
      require(!read_command.valid, {name, ": command escaped read backpressure"});
      read_command_status.alfull = 0;
    end

    read_seen = 0;
    prefetch_seen = 0;
    remaining = elements;
    repeat(220) begin
      tick();
      read_response.valid = 0;
      prefetch_read_response.valid = 0;
      if(prefetch_read_command.valid) begin
        prefetch_seen++;
        require(prefetch_read_command.payload.command == TOUCH_I,
                {name, ": prefetch command"});
        require(prefetch_read_command.payload.address ==
                (base & ADDRESS_PAGE_ALIGN_MASK), {name, ": prefetch page address"});
        require(prefetch_read_command.payload.abt == STRICT, {name, ": prefetch ABT"});
        prefetch_read_response.valid = 1;
        prefetch_read_response.payload.cmd = prefetch_read_command.payload.cmd;
        prefetch_read_response.payload.response = DONE;
      end
      if(read_command.valid) begin
        expected_real_size =
          (remaining > CACHELINE_ARRAY_NUM) ? CACHELINE_ARRAY_NUM : remaining;
        require(read_command.payload.address == base + read_seen * CACHELINE_SIZE,
                {name, ": read address"});
        require(read_command.payload.cmd.address_offset == read_seen * CACHELINE_SIZE,
                {name, ": read offset"});
        require(read_command.payload.cmd.real_size == expected_real_size,
                {name, ": read real_size"});
        require(read_command.payload.cmd.cmd_type == CMD_READ, {name, ": read type"});
        require(read_command.payload.abt == expected_abt, {name, ": read CABT"});
        if(cached) begin
          require(read_command.payload.command == READ_CL_S, {name, ": cached command"});
          require(read_command.payload.size == 128, {name, ": cached size"});
          require(read_command.payload.cmd.real_size_bytes == 128,
                  {name, ": cached byte size"});
        end else if(remaining > CACHELINE_ARRAY_NUM) begin
          require(read_command.payload.command == READ_CL_NA, {name, ": line command"});
          require(read_command.payload.size == 128, {name, ": line size"});
        end else begin
          require(read_command.payload.command == READ_PNA, {name, ": tail command"});
          require(read_command.payload.size == cmd_size_calculate(expected_real_size),
                  {name, ": tail size"});
        end
        remaining -= expected_real_size;
        read_seen++;
        read_response.valid = 1;
        read_response.payload.cmd = read_command.payload.cmd;
        read_response.payload.response = DONE;
        read_response.payload.response_credits = 1;
      end
    end
    require(remaining == 0, {name, ": missing read commands"});
    require(read_seen == (elements + CACHELINE_ARRAY_NUM - 1) / CACHELINE_ARRAY_NUM,
            {name, ": read command count"});
    require(prefetch_seen == ((prefetch && elements != 0) ? 1 : 0),
            {name, ": prefetch count"});
    tick(5);
    require(read_count == elements, {name, ": read counter"});
    bins_hit++;
  endtask

  task automatic write_case(
      input string name,
      input int unsigned elements,
      input logic cached,
      input logic [0:2] cabt_bits,
      input logic stall_first,
      input logic prefetch
  );
    logic [0:511] lower;
    logic [0:511] upper;
    int unsigned seen;

    reset_direct(0, 1);
    configure = '0;
    configure[5:7] = cabt_bits;
    configure[9] = cached;
    prefetch_write_enable = prefetch;
    wed.valid = 1;
    wed.payload.wed.size_recive = elements;
    wed.payload.wed.array_receive = 64'h0000_0000_2200_0000;
    if(stall_first)
      write_command_status.alfull = 1;
    lower = {8{64'h0123_4567_89ab_cdef}};
    upper = {8{64'hfedc_ba98_7654_3210}};
    write_data_in_0.valid = 1;
    write_data_in_1.valid = 1;
    write_data_in_0.payload.cmd.real_size = elements;
    write_data_in_1.payload.cmd.real_size = elements;
    write_data_in_0.payload.cmd.real_size_bytes = cmd_size_calculate(elements);
    write_data_in_1.payload.cmd.real_size_bytes = cmd_size_calculate(elements);
    write_data_in_0.payload.cmd.address_offset = CACHELINE_SIZE;
    write_data_in_1.payload.cmd.address_offset = CACHELINE_SIZE;
    write_data_in_0.payload.data = lower;
    write_data_in_1.payload.data = upper;
    tick();
    write_data_in_0.valid = 0;
    write_data_in_1.valid = 0;
    if(stall_first) begin
      tick(14);
      require(!write_command.valid, {name, ": write escaped backpressure"});
      write_command_status.alfull = 0;
    end

    seen = 0;
    begin : write_wait
      int unsigned prefetch_seen;
      prefetch_seen = 0;
    repeat(80) begin
      tick();
      write_response.valid = 0;
      prefetch_write_response.valid = 0;
      if(prefetch_write_command.valid) begin
        prefetch_seen++;
        require(prefetch_write_command.payload.command == TOUCH_I,
                {name, ": write prefetch command"});
        require(prefetch_write_command.payload.address ==
                (64'h0000_0000_2200_0000 & ADDRESS_PAGE_ALIGN_MASK),
                {name, ": write prefetch address"});
        prefetch_write_response.valid = 1;
        prefetch_write_response.payload.cmd = prefetch_write_command.payload.cmd;
        prefetch_write_response.payload.response = DONE;
      end
      if(write_command.valid) begin
        seen++;
        require(write_command.payload.command == (cached ? WRITE_MS : WRITE_NA),
                {name, ": write command"});
        require(write_command.payload.address ==
                64'h0000_0000_2200_0000 + CACHELINE_SIZE,
                {name, ": write address"});
        require(write_command.payload.abt == map_CABT(cabt_bits),
                {name, ": write CABT"});
        require(write_command.payload.size == cmd_size_calculate(elements),
                {name, ": write size"});
        require(write_data_out_0.valid && write_data_out_1.valid,
                {name, ": write data valids"});
        require(write_data_out_0.payload.data == lower, {name, ": lower data"});
        require(write_data_out_1.payload.data == upper, {name, ": upper data"});
        write_response.valid = 1;
        write_response.payload.cmd = write_command.payload.cmd;
        write_response.payload.response = DONE;
        write_response.payload.response_credits = 1;
      end
    end
      require(prefetch_seen == ((prefetch && elements != 0) ? 1 : 0),
              {name, ": write prefetch count"});
    end
    require(seen == 1, {name, ": write command count"});
    tick(5);
    require(write_count == elements, {name, ": write counter"});
    bins_hit++;
  endtask

  task automatic tlb_limit_case;
    int unsigned commands_seen;
    CommandTagLine pending_cmd;

    reset_direct(1, 0);
    max_tlb_requests = 1;
    wed.valid = 1;
    wed.payload.wed.size_send = 2 * CACHELINE_ARRAY_NUM + 1;
    wed.payload.wed.size_recive = 2 * CACHELINE_ARRAY_NUM + 1;
    wed.payload.wed.array_send = 64'h0000_0000_2a00_0000;
    commands_seen = 0;
    repeat(180) begin
      tick();
      if(read_command.valid) begin
        commands_seen++;
        pending_cmd = read_command.payload.cmd;
        require(commands_seen == 1, "TLB limit issued a second command without response");
      end
      if(commands_seen == 1)
        break;
    end
    require(commands_seen == 1, "TLB limit first command missing");
    repeat(20) begin
      tick();
      require(!read_command.valid, "TLB limit did not hold while response was absent");
    end

    for(int burst = 0; burst < 3; burst++) begin
      if(burst != 0) begin
        bit found;
        found = 0;
        repeat(100) begin
          tick();
          if(read_command.valid && !found) begin
            found = 1;
            commands_seen++;
            pending_cmd = read_command.payload.cmd;
          end
        end
        if(!found)
          $fatal(
            1,
            "memcpy requirement failed: TLB limit next burst command missing state=%0d send=%0d resp=%0d done=%0d remaining=%0d",
            read_dut.current_state,
            read_dut.read_job_send_done_latched,
            read_dut.read_job_resp_done_latched,
            read_dut.done_read_pending,
            read_dut.wed_request_in_latched.payload.wed.size_send
          );
        assertions_checked++;
      end
      read_response.valid = 1;
      read_response.payload.cmd = pending_cmd;
      read_response.payload.response = DONE;
      tick();
      read_response.valid = 0;
    end
    tick(20);
    require(commands_seen == 3, "TLB limit command count");
    require(read_count == 2 * CACHELINE_ARRAY_NUM + 1, "TLB limit response counter");
    bins_hit++;
  endtask

  task automatic write_tlb_limit_case;
    int unsigned commands_seen;
    int unsigned real_size;
    CommandTagLine pending_cmd;
    bit found;

    reset_direct(0, 1);
    max_tlb_requests = 1;
    wed.valid = 1;
    wed.payload.wed.size_send = 0;
    wed.payload.wed.size_recive = 2 * CACHELINE_ARRAY_NUM + 1;
    wed.payload.wed.array_receive = 64'h0000_0000_2b00_0000;
    for(int index = 0; index < 3; index++) begin
      real_size = (index < 2) ? CACHELINE_ARRAY_NUM : 1;
      write_data_in_0.valid = 1;
      write_data_in_1.valid = 1;
      write_data_in_0.payload.cmd.real_size = real_size;
      write_data_in_1.payload.cmd.real_size = real_size;
      write_data_in_0.payload.cmd.real_size_bytes = cmd_size_calculate(real_size);
      write_data_in_1.payload.cmd.real_size_bytes = cmd_size_calculate(real_size);
      write_data_in_0.payload.cmd.address_offset = index * CACHELINE_SIZE;
      write_data_in_1.payload.cmd.address_offset = index * CACHELINE_SIZE;
      write_data_in_0.payload.data = '0;
      write_data_in_1.payload.data = '0;
      tick();
    end
    write_data_in_0.valid = 0;
    write_data_in_1.valid = 0;

    commands_seen = 0;
    for(int burst = 0; burst < 3; burst++) begin
      found = 0;
      repeat(120) begin
        tick();
        if(write_command.valid && !found) begin
          found = 1;
          commands_seen++;
          pending_cmd = write_command.payload.cmd;
          require(write_command.payload.address ==
                  64'h0000_0000_2b00_0000 + burst * CACHELINE_SIZE,
                  "write TLB burst address");
        end
      end
      require(found, "write TLB next burst command missing");
      if(burst == 0) begin
        repeat(20) begin
          tick();
          require(!write_command.valid,
                  "write TLB limit issued another command without response");
        end
      end
      write_response.valid = 1;
      write_response.payload.cmd = pending_cmd;
      write_response.payload.response = DONE;
      tick();
      write_response.valid = 0;
    end
    tick(20);
    require(commands_seen == 3, "write TLB command count");
    require(write_count == 2 * CACHELINE_ARRAY_NUM + 1,
            "write TLB response counter");
    bins_hit++;
  endtask

  task automatic prefetch_window_resume_case;
    bit first_prefetch;
    bit first_command;
    bit resumed_prefetch;
    CommandTagLine pending_cmd;

    reset_direct(1, 0);
    prefetch_read_enable = 1;
    tlb_size = 1;
    max_tlb_requests = 1;
    wed.valid = 1;
    wed.payload.wed.size_send = PAGE_ARRAY_NUM + 1;
    wed.payload.wed.size_recive = 0;
    wed.payload.wed.array_send = 64'h2c00_0000;
    prefetch_read_status.alfull = 1;
    tick(10);
    require(!prefetch_read_command.valid,
            "read prefetch escaped command-buffer backpressure");
    prefetch_read_status.alfull = 0;
    first_prefetch = 0;
    first_command = 0;
    resumed_prefetch = 0;
    repeat(500) begin
      tick();
      prefetch_read_response.valid = 0;
      read_response.valid = 0;
      if(prefetch_read_command.valid) begin
        if(!first_prefetch) begin
          first_prefetch = 1;
          prefetch_read_response.valid = 1;
          prefetch_read_response.payload.cmd = prefetch_read_command.payload.cmd;
          prefetch_read_response.payload.response = DONE;
        end else begin
          resumed_prefetch = 1;
        end
      end
      if(read_command.valid && !first_command) begin
        first_command = 1;
        pending_cmd = read_command.payload.cmd;
        read_response.valid = 1;
        read_response.payload.cmd = pending_cmd;
        read_response.payload.response = DONE;
      end
      if(resumed_prefetch)
        break;
    end
    require(first_prefetch && first_command && resumed_prefetch,
            "read prefetch window did not resume");

    reset_direct(0, 1);
    prefetch_write_enable = 1;
    tlb_size = 1;
    max_tlb_requests = 1;
    wed.valid = 1;
    wed.payload.wed.size_send = 0;
    wed.payload.wed.size_recive = PAGE_ARRAY_NUM + 1;
    wed.payload.wed.array_receive = 64'h2d00_0000;
    prefetch_write_status.alfull = 1;
    tick(10);
    require(!prefetch_write_command.valid,
            "write prefetch escaped command-buffer backpressure");
    prefetch_write_status.alfull = 0;
    write_data_in_0.valid = 1;
    write_data_in_1.valid = 1;
    write_data_in_0.payload.cmd.real_size = CACHELINE_ARRAY_NUM;
    write_data_in_1.payload.cmd.real_size = CACHELINE_ARRAY_NUM;
    write_data_in_0.payload.cmd.real_size_bytes = CACHELINE_SIZE;
    write_data_in_1.payload.cmd.real_size_bytes = CACHELINE_SIZE;
    write_data_in_0.payload.data = '1;
    write_data_in_1.payload.data = '0;
    tick();
    write_data_in_0.valid = 0;
    write_data_in_1.valid = 0;
    first_prefetch = 0;
    first_command = 0;
    resumed_prefetch = 0;
    repeat(600) begin
      tick();
      prefetch_write_response.valid = 0;
      write_response.valid = 0;
      if(prefetch_write_command.valid) begin
        if(!first_prefetch) begin
          first_prefetch = 1;
          prefetch_write_response.valid = 1;
          prefetch_write_response.payload.cmd = prefetch_write_command.payload.cmd;
          prefetch_write_response.payload.response = DONE;
        end else begin
          resumed_prefetch = 1;
        end
      end
      if(write_command.valid && !first_command) begin
        first_command = 1;
        pending_cmd = write_command.payload.cmd;
        write_response.valid = 1;
        write_response.payload.cmd = pending_cmd;
        write_response.payload.response = DONE;
      end
      if(resumed_prefetch)
        break;
    end
    require(first_prefetch && first_command && resumed_prefetch,
            "write prefetch window did not resume");
    bins_hit++;
  endtask

  task automatic metadata_and_status_coverage_case;
    bit command_seen;

    reset_direct(1, 1);
    read_data_status = '1;
    prefetch_read_status = '1;
    prefetch_write_status = '1;
    tick(5);
    read_data_status = 0;
    prefetch_read_status = 0;
    prefetch_write_status = 0;
    tick(5);

    reset_direct(0, 1);
    wed.valid = 1;
    wed.payload.wed.size_recive = 8'hff;
    wed.payload.wed.array_receive = 64'h2e00_0000;
    write_data_in_0.valid = 1;
    write_data_in_1.valid = 1;
    write_data_in_0.payload.cmd.cacheline_offset = 8'hff;
    write_data_in_1.payload.cmd.cacheline_offset = 8'hff;
    write_data_in_0.payload.cmd.address_offset = 64'hffff_ffff_ffff_ff00;
    write_data_in_1.payload.cmd.address_offset = 64'hffff_ffff_ffff_ff00;
    write_data_in_0.payload.cmd.real_size = 8'hff;
    write_data_in_1.payload.cmd.real_size = 8'hff;
    write_data_in_0.payload.cmd.real_size_bytes = 8'hff;
    write_data_in_1.payload.cmd.real_size_bytes = 8'hff;
    write_data_in_0.payload.data = '1;
    write_data_in_1.payload.data = '1;
    tick();
    write_data_in_0.valid = 0;
    write_data_in_1.valid = 0;
    command_seen = 0;
    repeat(100) begin
      tick();
      write_response.valid = 0;
      if(write_command.valid && !command_seen) begin
        command_seen = 1;
        write_response.valid = 1;
        write_response.payload.cmd = write_command.payload.cmd;
        write_response.payload.response = DONE;
      end
    end
    require(command_seen, "metadata coverage write missing");

    reset_direct(0, 1);
    write_command_status.alfull = 1;
    wed.valid = 1;
    wed.payload.wed.size_recive = 600;
    for(int index = 0; index < 530; index++) begin
      write_data_in_0.valid = 1;
      write_data_in_1.valid = 1;
      write_data_in_0.payload.cmd.real_size = 1;
      write_data_in_1.payload.cmd.real_size = 1;
      write_data_in_0.payload.cmd.address_offset = index * CACHELINE_SIZE;
      write_data_in_1.payload.cmd.address_offset = index * CACHELINE_SIZE;
      tick();
    end
    write_data_in_0.valid = 0;
    write_data_in_1.valid = 0;
    tick(5);
    require(write_data_status.alfull, "write FIFO almost-full was not reached");
    reset_direct(0, 1);
    bins_hit++;
  endtask

  task automatic copy_data_throttle_case;
    bit command_seen;

    reset_direct(1, 0);
    configure[22] = 1;
    wed.valid = 1;
    wed.payload.wed.size_send = 1;
    wed.payload.wed.array_send = 64'h2f00_0000;
    read_data_status.alfull = 1;
    tick(20);
    require(!read_command.valid, "copy read escaped write-data backpressure");
    read_data_status.alfull = 0;
    command_seen = 0;
    repeat(80) begin
      tick();
      if(read_command.valid)
        command_seen = 1;
    end
    require(command_seen, "copy read did not resume after write-data backpressure");
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
    prefetch_read_enable = 1;
    prefetch_write_enable = 1;
    wed = '1;
    configure = '1;
    tlb_size = '1;
    max_tlb_requests = '1;
    read_response = '1;
    write_response = '1;
    prefetch_read_response = '1;
    prefetch_write_response = '1;
    read_data_in_0 = '1;
    read_data_in_1 = '1;
    write_data_in_0 = '1;
    write_data_in_1 = '1;
    read_command_status = '1;
    read_data_status = '1;
    write_command_status = '1;
    prefetch_read_status = '1;
    prefetch_write_status = '1;
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
    prefetch_read_enable = 1;
    prefetch_write_enable = 1;
    wed = '1;
    configure = '1;
    tlb_size = '1;
    max_tlb_requests = '1;
    read_response = '1;
    write_response = '1;
    prefetch_read_response = '1;
    prefetch_write_response = '1;
    read_data_in_0 = '1;
    read_data_in_1 = '1;
    write_data_in_0 = '1;
    write_data_in_1 = '1;
    read_command_status = '1;
    read_data_status = '1;
    write_command_status = '1;
    prefetch_read_status = '1;
    prefetch_write_status = '1;
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
    prefetch_read_enable = 0;
    prefetch_write_enable = 0;
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
    bit read_seen;
    bit write_seen;
    bit done_seen;

    full_rstn = 0;
    clear_full_inputs();
    tick(6);
    full_rstn = 1;
    full_enabled = 1;
    full_configure.var1 = '0;
    full_configure.var1[22] = 1;
    full_configure.var1[23] = 1;
    full_configure.var3 = 1;
    full_configure.var4 = 1;
    full_wed.valid = 1;
    full_wed.payload.wed.size_send = elements;
    full_wed.payload.wed.size_recive = elements;
    full_wed.payload.wed.array_send = 64'h3300_0000;
    full_wed.payload.wed.array_receive = 64'h4400_0000;
    lower = {8{64'h1111_2222_3333_4444}};
    upper = {8{64'h5555_6666_7777_8888}};
    read_seen = 0;
    write_seen = 0;
    done_seen = 0;

    repeat(320) begin
      tick();
      full_read_response.valid = 0;
      full_write_response.valid = 0;
      full_read_data_0.valid = 0;
      full_read_data_1.valid = 0;
      if(full_read_command.valid && !read_seen) begin
        read_seen = 1;
        full_read_data_0.valid = 1;
        full_read_data_1.valid = 1;
        full_read_data_0.payload.cmd = full_read_command.payload.cmd;
        full_read_data_1.payload.cmd = full_read_command.payload.cmd;
        full_read_data_0.payload.data = lower;
        full_read_data_1.payload.data = upper;
        full_read_response.valid = 1;
        full_read_response.payload.cmd = full_read_command.payload.cmd;
        full_read_response.payload.response = DONE;
        full_read_response.payload.response_credits = 1;
      end
      if(full_write_command.valid && !write_seen) begin
        write_seen = 1;
        require(full_write_command.payload.address == 64'h4400_0000,
                {name, ": full write address"});
        require(full_write_data_0.payload.data == lower, {name, ": full lower data"});
        require(full_write_data_1.payload.data == upper, {name, ": full upper data"});
        full_write_response.valid = 1;
        full_write_response.payload.cmd = full_write_command.payload.cmd;
        full_write_response.payload.response = DONE;
        full_write_response.payload.response_credits = 1;
      end
      done_seen |= full_done;
    end
    if(elements == 0)
      require(!read_seen && !write_seen, {name, ": zero emitted command"});
    else begin
      require(read_seen, {name, ": read missing"});
      require(write_seen, {name, ": write missing"});
    end
    require(done_seen, {name, ": completion missing"});
    require(full_return.var1 == elements, {name, ": write return"});
    require(full_return.var2 == elements, {name, ": read return"});
    bins_hit++;
  endtask

  task automatic full_read_only_case;
    bit read_seen;
    bit done_seen;

    full_rstn = 0;
    clear_full_inputs();
    tick(6);
    full_rstn = 1;
    full_enabled = 1;
    full_configure.var1[23] = 1;
    full_configure.var3 = 1;
    full_configure.var4 = 1;
    full_wed.valid = 1;
    full_wed.payload.wed.size_send = 1;
    full_wed.payload.wed.size_recive = 0;
    full_wed.payload.wed.array_send = 64'h4a00_0000;
    read_seen = 0;
    done_seen = 0;
    repeat(260) begin
      tick();
      full_read_response.valid = 0;
      if(full_read_command.valid && !read_seen) begin
        read_seen = 1;
        full_read_response.valid = 1;
        full_read_response.payload.cmd = full_read_command.payload.cmd;
        full_read_response.payload.response = DONE;
        full_read_response.payload.response_credits = 1;
      end
      require(!full_write_command.valid, "read-only mode emitted a write");
      done_seen |= full_done;
    end
    require(read_seen, "read-only command missing");
    require(done_seen, "read-only completion missing");
    require(full_return.var1 == 1, "read-only completion counter");
    bins_hit++;
  endtask

  task automatic full_disabled_zero_case;
    bit done_seen;

    full_rstn = 0;
    clear_full_inputs();
    tick(6);
    full_rstn = 1;
    full_enabled = 1;
    full_configure.var1 = 1;
    full_configure.var3 = 1;
    full_configure.var4 = 1;
    full_wed.valid = 1;
    full_wed.payload.wed.size_send = 0;
    full_wed.payload.wed.size_recive = 0;
    done_seen = 0;
    repeat(80) begin
      tick();
      require(!full_read_command.valid && !full_write_command.valid,
              "disabled mode emitted a command");
      done_seen |= full_done;
    end
    require(done_seen, "disabled zero-length mode did not complete");
    bins_hit++;
  endtask

  task automatic full_write_only_multiline_case;
    int unsigned writes;
    bit done_seen;

    full_rstn = 0;
    clear_full_inputs();
    tick(6);
    full_rstn = 1;
    full_enabled = 1;
    full_configure.var1[21] = 1;
    full_configure.var3 = 1;
    full_configure.var4 = 1;
    full_wed.valid = 1;
    full_wed.payload.wed.size_send = 0;
    full_wed.payload.wed.size_recive = CACHELINE_ARRAY_NUM + 1;
    full_wed.payload.wed.array_receive = 64'h4b00_0000;
    writes = 0;
    done_seen = 0;
    repeat(500) begin
      tick();
      full_write_response.valid = 0;
      require(!full_read_command.valid, "multiline write-only emitted a read");
      if(full_write_command.valid) begin
        require(full_write_command.payload.address ==
                64'h4b00_0000 + writes * CACHELINE_SIZE,
                "multiline write-only address");
        require(full_write_command.payload.cmd.real_size ==
                ((writes == 0) ? CACHELINE_ARRAY_NUM : 1),
                "multiline write-only real_size");
        require(full_write_data_0.payload.data == '0 &&
                full_write_data_1.payload.data == '0,
                "multiline write-only data");
        writes++;
        full_write_response.valid = 1;
        full_write_response.payload.cmd = full_write_command.payload.cmd;
        full_write_response.payload.response = DONE;
        full_write_response.payload.response_credits = 1;
      end
      done_seen |= full_done;
    end
    require(writes == 2, "multiline write-only command count");
    require(done_seen, "multiline write-only completion");
    require(full_return.var1 == CACHELINE_ARRAY_NUM + 1,
            "multiline write-only counter");
    bins_hit++;
  endtask

  task automatic probe_write_only;
    bit write_seen;
    bit done_seen;

    full_rstn = 0;
    clear_full_inputs();
    tick(6);
    full_rstn = 1;
    full_enabled = 1;
    full_configure.var1 = '0;
    full_configure.var1[21] = 1;
    full_configure.var3 = 1;
    full_configure.var4 = 1;
    full_wed.valid = 1;
    full_wed.payload.wed.size_send = 0;
    full_wed.payload.wed.size_recive = 1;
    full_wed.payload.wed.array_receive = 64'h5500_0000;
    write_seen = 0;
    done_seen = 0;
    repeat(320) begin
      tick();
      full_write_response.valid = 0;
      require(!full_read_command.valid, "write-only mode emitted a read command");
      if(full_write_command.valid && !write_seen) begin
        write_seen = 1;
        require(full_write_command.payload.address == 64'h5500_0000,
                "write-only address");
        require(full_write_command.payload.cmd.real_size == 1,
                "write-only real_size");
        require(full_write_data_0.valid && full_write_data_1.valid,
                "write-only data valids");
        require(full_write_data_0.payload.data == '0,
                "write-only lower data is not zero-filled");
        require(full_write_data_1.payload.data == '0,
                "write-only upper data is not zero-filled");
        full_write_response.valid = 1;
        full_write_response.payload.cmd = full_write_command.payload.cmd;
        full_write_response.payload.response = DONE;
        full_write_response.payload.response_credits = 1;
      end
      done_seen |= full_done;
    end
    require(write_seen, "write-only mode issued no write");
    require(done_seen, "write-only mode did not complete");
    require(full_return.var1 == 1, "write-only completion counter");
    $display("PASS memcpy_probe_write_only assertions=%0d", assertions_checked);
  endtask

  initial begin
    bins_hit = 0;
    assertions_checked = 0;
    rstn = 0;
    full_rstn = 0;
    clear_direct_inputs();
    clear_full_inputs();
    coverage_toggle_sweep();

    if($test$plusargs("PROBE_WRITE_ONLY")) begin
      probe_write_only();
      $finish;
    end
    if($test$plusargs("PROBE_TLB_LIMIT")) begin
      tlb_limit_case();
      write_tlb_limit_case();
      $display("PASS memcpy_probe_tlb_limit assertions=%0d", assertions_checked);
      $finish;
    end

    read_case("zero", 0, 0, 3'b000, 0, 0);
    read_case("single-strict", 1, 0, 3'b000, 0, 1);
    read_case("cacheline-tail-page", CACHELINE_ARRAY_NUM, 0, 3'b010, 0, 0);
    read_case("multiline-abort", CACHELINE_ARRAY_NUM + 1, 0, 3'b100, 0, 0);
    read_case("cached-multiline", CACHELINE_ARRAY_NUM + 1, 1, 3'b000, 0, 0);
    read_case("cached-prefetch-pref", 1, 1, 3'b110, 1, 0);
    read_case("cached-spec", 1, 1, 3'b111, 0, 0);
    write_case("write-strict", 1, 0, 3'b000, 1, 0);
    write_case("write-cached-page", 1, 1, 3'b010, 0, 0);
    write_case("write-abort", 1, 0, 3'b100, 0, 0);
    write_case("write-pref", 1, 0, 3'b110, 0, 0);
    write_case("write-spec", 1, 0, 3'b111, 0, 0);
    write_case("write-prefetch", 1, 0, 3'b000, 0, 1);
    tlb_limit_case();
    write_tlb_limit_case();
    prefetch_window_resume_case();
    metadata_and_status_coverage_case();
    copy_data_throttle_case();
    full_copy_case("copy-zero", 0);
    full_copy_case("copy-single", 1);
    full_copy_case("copy-repeat", 1);
    full_read_only_case();
    full_disabled_zero_case();
    full_write_only_multiline_case();
    probe_write_only();

    require(bins_hit == 24, "functional bin denominator");
    $display(
      "PASS memcpy_cu bins=%0d/24 assertions=%0d",
      bins_hit,
      assertions_checked
    );
    $finish;
  end

endmodule
