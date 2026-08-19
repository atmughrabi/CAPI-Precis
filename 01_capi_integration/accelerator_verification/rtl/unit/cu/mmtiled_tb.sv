module mmtiled_tb;

  import GLOBALS_AFU_PKG::*;
  import GLOBALS_CU_PKG::*;
  import CAPI_PKG::*;
  import WED_PKG::*;
  import AFU_PKG::*;
  import CU_PKG::*;

  logic clock = 0;
  logic rstn;
  logic enabled;
  logic [0:63] configure_2;
  logic [0:63] configure_3;
  WEDInterface wed;
  ResponseBufferLine read_response;
  ReadWriteDataLine read_data_0;
  ReadWriteDataLine read_data_1;
  BufferStatus read_status;
  logic matrix_request;
  logic command_grant;
  logic command_request;
  CommandBufferLine read_command;
  MatrixCInterface matrix_job;

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

  always @(posedge clock) begin
    if(full_rstn) begin
      if(full_write_data_0.valid && !full_write_command.valid)
        $fatal(1, "mmtiled invariant failed: data0.valid without command.valid");
      if(full_write_data_1.valid && !full_write_command.valid)
        $fatal(1, "mmtiled invariant failed: data1.valid without command.valid");
    end
  end

  cu_matrix_C_job_control matrix_job_dut (
    .clock(clock),
    .rstn(rstn),
    .enabled_in(enabled),
    .cu_configure_2(configure_2),
    .cu_configure_3(configure_3),
    .wed_request_in(wed),
    .read_response_in(read_response),
    .read_data_0_in(read_data_0),
    .read_data_1_in(read_data_1),
    .read_buffer_status(read_status),
    .matrix_C_request(matrix_request),
    .read_command_bus_grant(command_grant),
    .read_command_bus_request(command_request),
    .read_command_out(read_command),
    .matrix_C_job_out(matrix_job)
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
      $fatal(1, "mmtiled requirement failed: %s", message);
  endtask

  task automatic clear_direct_inputs;
    enabled = 0;
    configure_2 = '0;
    configure_3 = '0;
    wed = '0;
    read_response = '0;
    read_data_0 = '0;
    read_data_1 = '0;
    read_status = '0;
    matrix_request = 1;
    command_grant = 1;
  endtask

  task automatic reset_direct;
    rstn = 0;
    clear_direct_inputs();
    tick(5);
    rstn = 1;
    enabled = 1;
    tick(5);
  endtask

  task automatic matrix_load_case(
      input string name,
      input int unsigned n,
      input int unsigned tile,
      input int unsigned start_i,
      input int unsigned start_j,
      input logic stall_first
  );
    int unsigned expected_rows;
    int unsigned expected_columns;
    int unsigned commands_seen;
    int unsigned jobs_seen;
    int unsigned expected_words;
    int unsigned row;
    int unsigned column;
    int unsigned commands_per_row;
    logic [0:63] expected_address;
    logic [0:31] expected_first_word;

    reset_direct();
    configure_2 = '0;
    configure_3 = '0;
    configure_2[0:62] = start_i;
    configure_3[0:62] = start_j;
    configure_2[63] = 1;
    configure_3[63] = 1;
    wed.valid = 1;
    wed.payload.wed.size_n = n;
    wed.payload.wed.size_tile = tile;
    wed.payload.wed.Matrix_C = 64'h0000_0000_6600_0000;
    if(stall_first) begin
      read_status.alfull = 1;
      tick(15);
      require(!read_command.valid, {name, ": read command escaped backpressure"});
      read_status.alfull = 0;
    end

    expected_rows = (start_i < n) ? ((start_i + tile < n) ? tile : n - start_i) : 0;
    expected_columns = (start_j < n) ? ((start_j + tile < n) ? tile : n - start_j) : 0;
    commands_per_row =
        (expected_columns + CACHELINE_DATA_READ_NUM - 1) /
        CACHELINE_DATA_READ_NUM;
    commands_seen = 0;
    jobs_seen = 0;
    repeat(600) begin
      tick();
      read_response.valid = 0;
      read_data_0.valid = 0;
      read_data_1.valid = 0;
      if(read_command.valid) begin
        row = start_i + commands_seen / commands_per_row;
        column =
            start_j +
            (commands_seen % commands_per_row) * CACHELINE_DATA_READ_NUM;
        expected_address =
          64'h0000_0000_6600_0000 + ((row * n + column) * DATA_SIZE_READ);
        expected_words =
          (expected_columns -
           (commands_seen % commands_per_row) * CACHELINE_DATA_READ_NUM >
           CACHELINE_DATA_READ_NUM) ?
          CACHELINE_DATA_READ_NUM :
          expected_columns -
          (commands_seen % commands_per_row) * CACHELINE_DATA_READ_NUM;
        if(read_command.payload.address != expected_address)
          $fatal(
            1,
            "mmtiled requirement failed: %s Matrix-C address expected=%h actual=%h",
            name,
            expected_address,
            read_command.payload.address
          );
        assertions_checked++;
        require(read_command.payload.command == READ_CL_S,
                {name, ": Matrix-C command"});
        require(read_command.payload.size == 128, {name, ": Matrix-C command size"});
        require(read_command.payload.cmd.real_size == expected_words,
                {name, ": Matrix-C real_size"});
        require(read_command.payload.cmd.real_size_bytes == expected_words * DATA_SIZE_READ,
                {name, ": Matrix-C byte count"});
        require(read_command.payload.cmd.array_struct == MATRIX_C_DATA_READ,
                {name, ": Matrix-C routing metadata"});
        read_data_0.valid = 1;
        read_data_1.valid = 1;
        read_data_0.payload.cmd = read_command.payload.cmd;
        read_data_1.payload.cmd = read_command.payload.cmd;
        read_data_0.payload.data = '0;
        read_data_1.payload.data = '0;
        read_data_0.payload.data[0:31] = 32'h0102_0304 + commands_seen;
        read_data_1.payload.data[0:31] = 32'h1112_1314 + commands_seen;
        read_response.valid = 1;
        read_response.payload.cmd = read_command.payload.cmd;
        read_response.payload.response = DONE;
        read_response.payload.response_credits = 1;
        commands_seen++;
      end
      if(matrix_job.valid) begin
        if((jobs_seen % expected_columns) == 0) begin
          expected_first_word = 32'h0403_0201 + (jobs_seen / expected_columns) * 32'h0100_0000;
          require(matrix_job.payload.data == expected_first_word,
                  {name, ": Matrix-C first unpacked word"});
        end
        jobs_seen++;
      end
    end
    require(commands_seen == expected_rows * commands_per_row,
            {name, ": Matrix-C command count"});
    require(jobs_seen == expected_rows * expected_columns,
            {name, ": Matrix-C job count"});
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
    enabled = 1;
    configure_2 = '1;
    configure_3 = '1;
    wed = '1;
    read_response = '1;
    read_data_0 = '1;
    read_data_1 = '1;
    read_status = '1;
    matrix_request = 1;
    command_grant = 1;
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
    enabled = 1;
    configure_2 = '1;
    configure_3 = '1;
    wed = '1;
    read_response = '1;
    read_data_0 = '1;
    read_data_1 = '1;
    read_status = '1;
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
    rstn = 0;
    full_rstn = 0;
    clear_direct_inputs();
    clear_full_inputs();
    tick(3);
  endtask

  task automatic held_stall_case;
    reset_direct();
    configure_2[63] = 1;
    configure_3[63] = 1;
    wed.valid = 1;
    wed.payload.wed.size_n = 1;
    wed.payload.wed.size_tile = 1;
    wed.payload.wed.Matrix_C = 64'h6680_0000;
    read_status.alfull = 1;
    tick(80);
    require(!read_command.valid, "held read stall emitted a Matrix-C command");
    require(!matrix_job.valid, "held read stall emitted a Matrix-C job");
    bins_hit++;
  endtask

  task automatic matrix_buffer_pressure_case;
    bit alfull_seen;

    reset_direct();
    configure_2[0:62] = 63;
    configure_3[0:62] = 0;
    configure_2[63] = 1;
    configure_3[63] = 1;
    wed.valid = 1;
    wed.payload.wed.size_n = 64;
    wed.payload.wed.size_tile = 64;
    wed.payload.wed.Matrix_C = 64'h6690_0000;
    matrix_request = 0;
    alfull_seen = 0;
    repeat(1800) begin
      tick();
      read_response.valid = 0;
      read_data_0.valid = 0;
      read_data_1.valid = 0;
      if(read_command.valid) begin
        read_data_0.valid = 1;
        read_data_1.valid = 1;
        read_data_0.payload.cmd = read_command.payload.cmd;
        read_data_1.payload.cmd = read_command.payload.cmd;
        read_data_0.payload.data = '1;
        read_data_1.payload.data = '0;
        read_response.valid = 1;
        read_response.payload.cmd = read_command.payload.cmd;
        read_response.payload.response = DONE;
      end
      alfull_seen |= matrix_job_dut.matrix_C_buffer_status.alfull;
    end
    require(alfull_seen, "Matrix-C job FIFO almost-full was not reached");
    reset_direct();
    bins_hit++;
  endtask

  function automatic logic [0:31] matrix_a_golden(
      input int unsigned row,
      input int unsigned column,
      input int unsigned salt
  );
    return ((row + 1) * (column + 2)) + salt;
  endfunction

  function automatic logic [0:31] matrix_b_transposed_golden(
      input int unsigned row,
      input int unsigned column,
      input int unsigned salt
  );
    return ((column + 3) * (row + 1)) + salt;
  endfunction

  function automatic logic [0:31] matrix_c_initial_golden(
      input int unsigned row,
      input int unsigned column,
      input int unsigned n,
      input int unsigned salt
  );
    return salt + row * n + column;
  endfunction

  function automatic logic [0:31] matrix_c_expected_golden(
      input int unsigned row,
      input int unsigned column,
      input int unsigned n,
      input int unsigned k_begin,
      input int unsigned k_limit,
      input int unsigned salt
  );
    logic [0:31] value;
    value = matrix_c_initial_golden(row, column, n, salt);
    for(int unsigned kk = k_begin; kk < k_limit; kk++)
      value +=
          matrix_a_golden(row, kk, salt) *
          matrix_b_transposed_golden(column, kk, salt);
    return value;
  endfunction

  task automatic service_matrix_read(
      input CommandBufferLine command,
      input int unsigned n,
      input int unsigned salt,
      input int unsigned profile,
      ref int unsigned c_reads,
      ref int unsigned a_reads,
      ref int unsigned b_reads
  );
    logic [0:1023] line;
    logic [0:63] base;
    logic [0:63] byte_address;
    logic [0:31] value;
    int unsigned element_index;
    int unsigned row;
    int unsigned column;

    require(command.payload.command == READ_CL_NA, "matrix read command code");
    require(command.payload.size == CACHELINE_SIZE, "matrix read command size");
    require(command.payload.cmd.real_size == 1, "matrix read real_size");
    require(command.payload.cmd.real_size_bytes == DATA_SIZE_READ,
            "matrix read byte count");
    require(
      !(|command.payload.address[57:63]),
      "matrix read address is not cacheline aligned"
    );

    case(command.payload.cmd.array_struct)
      MATRIX_C_DATA_READ: begin
        base = full_wed.payload.wed.Matrix_C;
        c_reads++;
      end
      MATRIX_A_DATA_READ: begin
        base = full_wed.payload.wed.Matrix_A;
        a_reads++;
      end
      MATRIX_B_DATA_READ: begin
        base = full_wed.payload.wed.Matrix_B;
        b_reads++;
      end
      default: begin
        base = 0;
        require(0, "unexpected matrix read routing type");
      end
    endcase

    line = '0;
    for(int word = 0; word < CACHELINE_DATA_READ_NUM; word++) begin
      byte_address = command.payload.address + word * DATA_SIZE_READ;
      value = 0;
      if(byte_address >= base) begin
        element_index = (byte_address - base) >> $clog2(DATA_SIZE_READ);
        if(element_index < n * n) begin
          row = element_index / n;
          column = element_index % n;
          case(command.payload.cmd.array_struct)
            MATRIX_C_DATA_READ:
              value = matrix_c_initial_golden(row, column, n, salt);
            MATRIX_A_DATA_READ:
              value = matrix_a_golden(row, column, salt);
            MATRIX_B_DATA_READ:
              value = matrix_b_transposed_golden(row, column, salt);
            default: value = 0;
          endcase
        end
      end
      line[word * DATA_SIZE_READ_BITS +: DATA_SIZE_READ_BITS] =
          swap_endianness_data_read(value);
    end

    full_read_data_0.payload.cmd = command.payload.cmd;
    full_read_data_1.payload.cmd = command.payload.cmd;
    full_read_data_0.payload.data = line[0:511];
    full_read_data_1.payload.data = line[512:1023];
    full_read_response.payload.cmd = command.payload.cmd;
    full_read_response.payload.response = DONE;
    full_read_response.payload.response_credits = 1;

    if(n != 1) begin
      full_read_data_0.valid = 1;
      full_read_data_1.valid = 1;
      full_read_response.valid = 1;
    end else begin
      case(profile % 3)
        0: begin
          full_read_data_0.valid = 1;
          full_read_data_1.valid = 1;
          full_read_response.valid = 1;
          tick();
        end
        1: begin
          full_read_data_0.valid = 1;
          full_read_data_1.valid = 1;
          tick();
          full_read_data_0.valid = 0;
          full_read_data_1.valid = 0;
          full_read_response.valid = 1;
          tick();
        end
        default: begin
          full_read_response.valid = 1;
          tick();
          full_read_response.valid = 0;
          full_read_data_0.valid = 1;
          full_read_data_1.valid = 1;
          tick();
        end
      endcase
      full_read_data_0.valid = 0;
      full_read_data_1.valid = 0;
      full_read_response.valid = 0;
    end
  endtask

  task automatic service_matrix_write(
      input CommandBufferLine command,
      input int unsigned n,
      input int unsigned k_begin,
      input int unsigned k_limit,
      input int unsigned salt,
      ref int unsigned writes,
      ref int unsigned responses
  );
    logic [0:31] raw_value;
    logic [0:31] actual_value;
    logic [0:31] expected_value;
    int unsigned element_index;
    int unsigned row;
    int unsigned column;
    int unsigned word_offset;
    int unsigned half_offset;

    require(command.payload.command == WRITE_NA, "matrix write command code");
    require(command.payload.size == DATA_SIZE_WRITE, "matrix write command size");
    require(command.payload.cmd.real_size == 1, "matrix write real_size");
    require(command.payload.cmd.real_size_bytes == DATA_SIZE_WRITE,
            "matrix write byte count");
    require(command.payload.cmd.array_struct == MATRIX_C_DATA_WRITE,
            "matrix write routing type");
    require(full_write_data_0.valid && full_write_data_1.valid,
            "matrix write data valids");

    element_index =
        (command.payload.address - full_wed.payload.wed.Matrix_C) >>
        $clog2(DATA_SIZE_WRITE);
    row = element_index / n;
    column = element_index % n;
    word_offset = command.payload.cmd.cacheline_offset;
    half_offset = word_offset % CACHELINE_DATA_WRITE_NUM_HF;
    if(word_offset < CACHELINE_DATA_WRITE_NUM_HF)
      raw_value = full_write_data_0.payload.data[
          half_offset * DATA_SIZE_WRITE_BITS +: DATA_SIZE_WRITE_BITS
      ];
    else
      raw_value = full_write_data_1.payload.data[
          half_offset * DATA_SIZE_WRITE_BITS +: DATA_SIZE_WRITE_BITS
      ];
    actual_value = swap_endianness_data_write(raw_value);
    expected_value =
        matrix_c_expected_golden(row, column, n, k_begin, k_limit, salt);
    require(actual_value == expected_value, "matrix write golden mismatch");

    writes++;
    if(n == 1) begin
      repeat(8) begin
        if(
          full_dut.matrix_engine_x[0].matrix_engine_y[0].
            matrix_multiply_control_instant.state == 4'd8
        )
          break;
        tick();
      end
    end
    full_write_response.valid = 1;
    full_write_response.payload.cmd = command.payload.cmd;
    full_write_response.payload.response = DONE;
    full_write_response.payload.response_credits = 1;
    responses++;
    if(n == 1) begin
      tick();
      full_write_response.valid = 0;
    end
  endtask

  task automatic full_matrix_case(
      input string name,
      input int unsigned n,
      input int unsigned tile,
      input int unsigned start_i,
      input int unsigned start_j,
      input int unsigned start_k,
      input int unsigned salt,
      input int unsigned profile
  );
    int unsigned i_limit;
    int unsigned j_limit;
    int unsigned k_limit;
    int unsigned expected_writes;
    int unsigned expected_terms;
    int unsigned c_reads;
    int unsigned a_reads;
    int unsigned b_reads;
    int unsigned writes;
    int unsigned write_responses;
    int unsigned blocked_write_streak;
    int unsigned blocked_write_max;
    int unsigned write_hold_cycles;
    bit done_seen;
    bit stalled_c;
    bit stalled_a;
    bit stalled_b;
    bit stalled_write;
    bit stalled_pending_write;

    i_limit = (start_i + tile < n) ? start_i + tile : n;
    j_limit = (start_j + tile < n) ? start_j + tile : n;
    k_limit = (start_k + tile < n) ? start_k + tile : n;
    expected_writes =
        (start_i < n && start_j < n && start_k < n && tile != 0) ?
        (i_limit - start_i) * (j_limit - start_j) : 0;
    expected_terms = expected_writes * ((start_k < n) ? k_limit - start_k : 0);

    full_rstn = 0;
    clear_full_inputs();
    tick(6);
    full_rstn = 1;
    full_enabled = 1;
    tick(8);
    full_configure.var1 = 64'hffff_ffff_ffff_ffff;
    full_configure.var2 = '0;
    full_configure.var3 = '0;
    full_configure.var4 = '0;
    full_configure.var2[0:62] = start_i;
    full_configure.var3[0:62] = start_j;
    full_configure.var4[0:62] = start_k;
    full_configure.var2[63] = 1;
    full_configure.var3[63] = 1;
    full_configure.var4[63] = 1;
    full_wed.valid = 1;
    full_wed.payload.wed.size_n = n;
    full_wed.payload.wed.size_tile = tile;
    full_wed.payload.wed.Matrix_A = 64'h8100_0040;
    full_wed.payload.wed.Matrix_B = 64'h8200_0080;
    full_wed.payload.wed.Matrix_C = 64'h8300_00c0;
    c_reads = 0;
    a_reads = 0;
    b_reads = 0;
    writes = 0;
    write_responses = 0;
    blocked_write_streak = 0;
    blocked_write_max = 0;
    write_hold_cycles = 0;
    done_seen = 0;
    stalled_c = 0;
    stalled_a = 0;
    stalled_b = 0;
    stalled_write = 0;
    stalled_pending_write = 0;

    if(profile[0]) begin
      full_read_status.alfull = 1;
      tick(8);
      require(!full_read_command.valid, {name, ": read stall escaped"});
      full_read_status.alfull = 0;
    end

    for(int cycle = 0; cycle < 8000 && !done_seen; cycle++) begin
      full_read_status.alfull = 0;
      full_write_status.alfull = 0;
      if(
        profile >= 2 &&
        full_dut.matrix_engine_x[0].matrix_engine_y[0].matrix_multiply_control_instant.state == 4'd1 &&
        !stalled_c
      ) begin
        full_read_status.alfull = 1;
        stalled_c = 1;
      end else if(
        profile >= 2 &&
        full_dut.matrix_engine_x[0].matrix_engine_y[0].matrix_multiply_control_instant.state == 4'd3 &&
        !stalled_a
      ) begin
        full_read_status.alfull = 1;
        stalled_a = 1;
      end else if(
        profile >= 2 &&
        full_dut.matrix_engine_x[0].matrix_engine_y[0].matrix_multiply_control_instant.state == 4'd5 &&
        !stalled_b
      ) begin
        full_read_status.alfull = 1;
        stalled_b = 1;
      end
      if(
        profile >= 3 &&
        full_dut.matrix_engine_x[0].matrix_engine_y[0].matrix_multiply_control_instant.state == 4'd7 &&
        !stalled_write
      ) begin
        full_write_status.alfull = 1;
        stalled_write = 1;
      end
      if(
        profile >= 3 &&
        (
          (|full_dut.matrix_engine_write_valid) ||
          full_dut.matrix_engine_write_pending.valid
        ) &&
        !stalled_pending_write
      ) begin
        write_hold_cycles = 4;
        stalled_pending_write = 1;
      end
      if(write_hold_cycles > 0) begin
        full_write_status.alfull = 1;
        write_hold_cycles--;
      end
      tick();
      full_read_data_0.valid = 0;
      full_read_data_1.valid = 0;
      full_read_response.valid = 0;
      full_write_response.valid = 0;
      if(
        full_dut.matrix_engine_write_pending.valid &&
        full_dut.write_buffer_status_latched.alfull
      ) begin
        blocked_write_streak++;
        if(blocked_write_streak > blocked_write_max)
          blocked_write_max = blocked_write_streak;
        if(blocked_write_streak > 1)
          require(
            !full_write_command.valid &&
            !full_write_data_0.valid &&
            !full_write_data_1.valid,
            "write command escaped multi-cycle alfull"
          );
      end else begin
        blocked_write_streak = 0;
      end
      if(full_write_command.valid)
        require(
          !full_dut.matrix_engine_write_pending.valid &&
          !full_dut.matrix_engine_write_data_0_pending.valid &&
          !full_dut.matrix_engine_write_data_1_pending.valid,
          "pending write command/data valids did not clear together"
        );
      if(full_read_command.valid)
        service_matrix_read(
          full_read_command,
          n,
          salt,
          profile + c_reads + a_reads + b_reads,
          c_reads,
          a_reads,
          b_reads
        );
      if(full_write_command.valid)
        service_matrix_write(
          full_write_command,
          n,
          start_k,
          k_limit,
          salt,
          writes,
          write_responses
        );
      done_seen |= full_done;
    end

    if(!done_seen)
      $display(
        "matrix timeout name=%s reads=%0d/%0d/%0d writes=%0d states=%0d,%0d,%0d,%0d pending=%0d/%0d done=%b",
        name,
        c_reads,
        a_reads,
        b_reads,
        writes,
        full_dut.matrix_engine_x[0].matrix_engine_y[0].matrix_multiply_control_instant.state,
        full_dut.matrix_engine_x[0].matrix_engine_y[1].matrix_multiply_control_instant.state,
        full_dut.matrix_engine_x[1].matrix_engine_y[0].matrix_multiply_control_instant.state,
        full_dut.matrix_engine_x[1].matrix_engine_y[1].matrix_multiply_control_instant.state,
        full_dut.matrix_engine_read_pending.valid,
        full_dut.matrix_engine_write_pending.valid,
        full_dut.matrix_engine_done
      );
    require(done_seen, {name, ": matrix completion missing"});
    if(
      writes != expected_writes ||
      c_reads != expected_writes ||
      a_reads != expected_terms ||
      b_reads != expected_terms
    )
      $display(
        "matrix count mismatch name=%s expected=%0d/%0d actual c/a/b/w=%0d/%0d/%0d/%0d",
        name,
        expected_writes,
        expected_terms,
        c_reads,
        a_reads,
        b_reads,
        writes
      );
    require(writes == expected_writes, {name, ": write count"});
    require(write_responses == writes, {name, ": write response conservation"});
    require(c_reads == expected_writes, {name, ": C read count"});
    require(a_reads == expected_terms, {name, ": A read count"});
    require(b_reads == expected_terms, {name, ": B read count"});
    require(full_return.var1 == expected_writes, {name, ": return write count"});
    require(full_return.var2 == expected_terms, {name, ": return term count"});
    require(!full_prefetch_read_command.valid && !full_prefetch_write_command.valid,
            {name, ": unexpected prefetch"});
    if(profile >= 3)
      require(blocked_write_max > 1, {name, ": multi-cycle write stall missing"});
    bins_hit++;
  endtask

  task automatic full_legacy_routing_case;
    bit response_routed;
    bit data_0_routed;
    bit data_1_routed;

    full_rstn = 0;
    clear_full_inputs();
    tick(6);
    full_rstn = 1;
    full_enabled = 1;
    tick(8);
    full_read_response.valid = 1;
    full_read_response.payload.cmd.cu_id_x = MATRIX_C_CONTROL_ID;
    full_read_response.payload.cmd.cu_id_y = MATRIX_C_CONTROL_ID;
    full_read_response.payload.cmd.array_struct = MATRIX_C_DATA_READ;
    full_read_response.payload.response = DONE;
    full_read_data_0.valid = 1;
    full_read_data_1.valid = 1;
    full_read_data_0.payload.cmd = full_read_response.payload.cmd;
    full_read_data_1.payload.cmd = full_read_response.payload.cmd;
    response_routed = 0;
    data_0_routed = 0;
    data_1_routed = 0;
    repeat(8) begin
      tick();
      response_routed |= full_dut.read_response_in_matrix_C_job.valid;
      data_0_routed |= full_dut.read_data_0_in_matrix_C_job.valid;
      data_1_routed |= full_dut.read_data_1_in_matrix_C_job.valid;
    end
    require(response_routed && data_0_routed && data_1_routed,
            "legacy Matrix-C response routing");
    full_rstn = 0;
    clear_full_inputs();
    tick(3);
    bins_hit++;
  endtask

  task automatic outer_arbiter_delayed_ready_case;
    CommandBufferLine held_engine_command;
    bit pending_seen;
    bit loader_request_seen;
    int unsigned grants_seen;
    int unsigned publications_seen;

    full_rstn = 0;
    clear_full_inputs();
    tick(6);
    full_rstn = 1;
    full_enabled = 1;
    tick(8);

    force full_dut.enabled_matrix_C_job = 1'b1;
    force full_dut.ready[1] = 1'b0;

    full_configure.var1 = 64'h1;
    full_configure.var2[63] = 1;
    full_configure.var3[63] = 1;
    full_configure.var4[63] = 1;
    full_wed.valid = 1;
    full_wed.payload.wed.size_n = 1;
    full_wed.payload.wed.size_tile = 1;
    full_wed.payload.wed.Matrix_A = 64'h9100_0000;
    full_wed.payload.wed.Matrix_B = 64'h9200_0000;
    full_wed.payload.wed.Matrix_C = 64'h9300_0000;

    pending_seen = 0;
    loader_request_seen = 0;
    repeat(200) begin
      tick();
      loader_request_seen |= full_dut.requests[0];
      if(full_dut.matrix_engine_read_pending.valid && !pending_seen) begin
        pending_seen = 1;
        held_engine_command = full_dut.matrix_engine_read_pending;
      end
    end
    require(pending_seen, "engine read pending was not created");
    require(loader_request_seen, "legacy loader did not compete for read arbitration");
    repeat(6) begin
      tick();
      require(full_dut.matrix_engine_read_pending.valid,
              "pending dropped while ready was delayed");
      require(full_dut.matrix_engine_read_pending.payload ==
              held_engine_command.payload,
              "pending payload changed while ready was delayed");
      require(!( |full_dut.matrix_engine_read_grant),
              "lane granted before outer publication");
    end

    release full_dut.ready[1];
    grants_seen = 0;
    publications_seen = 0;
    repeat(80) begin
      tick();
      if(|full_dut.matrix_engine_read_grant) begin
        grants_seen++;
        require(full_dut.read_command_buffer_arbiter_out.valid,
                "lane grant did not coincide with arbiter publication");
        require(full_dut.read_command_buffer_arbiter_out.payload ==
                held_engine_command.payload,
                "published payload did not match pending owner");
      end
      if(
        full_read_command.valid &&
        full_read_command.payload.cmd.cu_id_x != MATRIX_C_CONTROL_ID
      )
        publications_seen++;
    end
    require(grants_seen == 1, "pending owner was not granted exactly once");
    require(publications_seen == 1,
            "engine command was not published exactly once");

    release full_dut.enabled_matrix_C_job;
    full_rstn = 0;
    clear_full_inputs();
    tick(4);
    bins_hit++;
  endtask

  task automatic probe_matrix_product;
    full_matrix_case("product-probe", 3, 2, 2, 1, 1, 7, 2);
    $display("PASS mmtiled_probe_matrix_product assertions=%0d", assertions_checked);
  endtask

  initial begin
    bins_hit = 0;
    assertions_checked = 0;
    rstn = 0;
    full_rstn = 0;
    clear_direct_inputs();
    clear_full_inputs();
    coverage_toggle_sweep();

    if($test$plusargs("PROBE_MATRIX_PRODUCT")) begin
      probe_matrix_product();
      $finish;
    end
    if($test$plusargs("PROBE_MATRIX_ADDRESS")) begin
      matrix_load_case("single", 1, 1, 0, 0, 0);
      $display("PASS mmtiled_probe_matrix_address assertions=%0d", assertions_checked);
      $finish;
    end

    matrix_load_case("zero", 0, 1, 0, 0, 0);
    held_stall_case();
    matrix_load_case("single", 1, 1, 0, 0, 0);
    matrix_load_case("full-tile", 4, 4, 0, 0, 0);
    matrix_load_case("edge-tile", 5, 3, 3, 3, 0);
    matrix_load_case("upper-half-17", 17, 17, 16, 0, 0);
    matrix_load_case("multiline-40", 40, 40, 39, 0, 0);
    matrix_buffer_pressure_case();
    full_matrix_case("product-zero", 0, 1, 0, 0, 0, 1, 0);
    full_matrix_case("product-single", 1, 1, 0, 0, 0, 7, 1);
    full_matrix_case("product-full-tile", 2, 2, 0, 0, 0, 11, 0);
    full_matrix_case("product-parallel-4x4", 4, 4, 0, 0, 0, 17, 0);
    full_matrix_case("product-edge-tile", 3, 2, 2, 1, 1, 13, 0);
    full_matrix_case("product-repeat", 1, 1, 0, 0, 0, 255, 4);
    full_legacy_routing_case();
    outer_arbiter_delayed_ready_case();

    require(bins_hit == 16, "functional bin denominator");
    $display(
      "PASS mmtiled_cu bins=%0d/16 assertions=%0d",
      bins_hit,
      assertions_checked
    );
    $finish;
  end

endmodule
