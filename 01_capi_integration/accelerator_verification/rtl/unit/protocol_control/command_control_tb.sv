module command_control_tb;

  import CAPI_PKG::*;
  import AFU_PKG::*;
  import PROTOCOL_TB_PKG::*;

  logic clock;
  logic rstn_in;
  logic enabled_in;
  CommandBufferLine command_arbiter_in;
  logic [0:7] command_tag_in;
  CommandInterfaceOutput command_out;

  int unsigned checks;
  int unsigned bins_hit;
  bit command_bins [0:22];
  bit size_bins [0:7];
  bit address_bins [0:5];
  bit abt_bins [0:4];
  bit tag_bins [0:255];
  bit parity_bins [0:2][0:1];
  bit stall_bins [0:2];
  bit pipeline_bins [0:7];

  command_control dut (
    .clock(clock),
    .rstn_in(rstn_in),
    .enabled_in(enabled_in),
    .command_arbiter_in(command_arbiter_in),
    .command_tag_in(command_tag_in),
    .command_out(command_out)
  );

  always #5 clock = ~clock;

  task automatic tick;
    @(posedge clock);
    #1;
  endtask

  task automatic check_command(
      input afu_command_t expected_command,
      input logic [0:11] expected_size,
      input logic [0:63] expected_address,
      input trans_order_behavior_t expected_abt,
      input logic [0:7] expected_tag
  );
    checks++;
    if(
      command_out.valid !== 1'b1 ||
      command_out.command !== expected_command ||
      command_out.size !== expected_size ||
      command_out.address !== expected_address ||
      command_out.abt !== expected_abt ||
      command_out.tag !== expected_tag ||
      command_out.context_handle !== 16'h0000 ||
      command_out.tag_parity !== model_odd_parity8(expected_tag) ||
      command_out.command_parity !== model_odd_parity13(expected_command) ||
      command_out.address_parity !== model_odd_parity64(expected_address)
    )
      $fatal(
        1,
        "command encoder mismatch tag=%0d command=%h size=%0d address=%h abt=%0d",
        expected_tag,
        expected_command,
        expected_size,
        expected_address,
        expected_abt
      );
    parity_bins[0][command_out.tag_parity] = 1;
    parity_bins[1][command_out.command_parity] = 1;
    parity_bins[2][command_out.address_parity] = 1;
  endtask

  task automatic issue_vector(input int unsigned tag_value);
    int unsigned command_index;
    int unsigned size_index;
    int unsigned address_index;
    int unsigned abt_index;
    afu_command_t expected_command;
    logic [0:11] expected_size;
    logic [0:63] expected_address;
    trans_order_behavior_t expected_abt;

    command_index = tag_value % 23;
    size_index = tag_value % 8;
    address_index = tag_value % 6;
    abt_index = tag_value % 5;
    expected_command = legal_command(command_index);
    expected_size = legal_size(size_index);
    expected_address = legal_address(address_index);
    expected_abt = legal_abt(abt_index);

    @(negedge clock);
    command_arbiter_in.valid = 1;
    command_arbiter_in.payload = '0;
    command_arbiter_in.payload.command = expected_command;
    command_arbiter_in.payload.size = expected_size;
    command_arbiter_in.payload.address = expected_address;
    command_arbiter_in.payload.abt = expected_abt;
    command_tag_in = tag_value[7:0];
    tick();
    tick();
    check_command(
      expected_command,
      expected_size,
      expected_address,
      expected_abt,
      tag_value[7:0]
    );
    command_bins[command_index] = 1;
    size_bins[size_index] = 1;
    address_bins[address_index] = 1;
    abt_bins[abt_index] = 1;
    tag_bins[tag_value] = 1;
  endtask

  task automatic bounded_room_stall(
      input int unsigned stall_index,
      input int unsigned stall_cycles
  );
    @(negedge clock);
    command_arbiter_in.valid = 0;
    repeat(2) tick();
    repeat(stall_cycles) begin
      tick();
      checks++;
      if(command_out.valid !== 1'b0)
        $fatal(
          1,
          "command encoder mismatch stall=command-room-%0d did not quiesce",
          stall_cycles
        );
    end
    stall_bins[stall_index] = 1;
  endtask

  function automatic logic [0:7] pipeline_tag(input int unsigned index);
    return 8'h80 ^ (index * 8'h11);
  endfunction

  function automatic logic [0:63] pipeline_address(input int unsigned index);
    return legal_address(index % 6) ^ (64'h0101_0101_0101_0101 * index);
  endfunction

  task automatic drive_pipeline_vector(input int unsigned index);
    command_arbiter_in.valid = 1;
    command_arbiter_in.payload.command = legal_command((index * 3) % 23);
    command_arbiter_in.payload.size = legal_size((index + 3) % 8);
    command_arbiter_in.payload.address = pipeline_address(index);
    command_arbiter_in.payload.abt = legal_abt((index + 2) % 5);
    command_tag_in = pipeline_tag(index);
  endtask

  task automatic check_pipeline_vector(input int unsigned index);
    check_command(
      legal_command((index * 3) % 23),
      legal_size((index + 3) % 8),
      pipeline_address(index),
      legal_abt((index + 2) % 5),
      pipeline_tag(index)
    );
    pipeline_bins[index] = 1;
  endtask

  task automatic check_back_to_back_pipeline;
    for(int sample = 0; sample < 8; sample++) begin
      @(negedge clock);
      drive_pipeline_vector(sample);
      tick();
      if(sample > 0)
        check_pipeline_vector(sample - 1);
    end
    @(negedge clock);
    command_arbiter_in.valid = 0;
    tick();
    check_pipeline_vector(7);
    tick();
    checks++;
    if(command_out.valid !== 1'b0)
      $fatal(1, "command encoder mismatch back-to-back pipeline did not drain");
  endtask

  initial begin
    clock = 0;
    rstn_in = 0;
    enabled_in = 0;
    command_arbiter_in = '0;
    command_tag_in = 0;
    checks = 0;
    bins_hit = 0;
    repeat(3) tick();
    rstn_in = 1;
    enabled_in = 1;
    repeat(3) tick();

    for(int tag_value = 0; tag_value < 256; tag_value++)
      issue_vector(tag_value);

    bounded_room_stall(0, 1);
    bounded_room_stall(1, 3);
    bounded_room_stall(2, 7);
    check_back_to_back_pipeline();

    for(int index = 0; index < 23; index++) begin
      if(!command_bins[index])
        $fatal(1, "command encoder mismatch missing command bin=%0d", index);
      bins_hit++;
    end
    for(int index = 0; index < 8; index++) begin
      if(!size_bins[index])
        $fatal(1, "command encoder mismatch missing size bin=%0d", index);
      bins_hit++;
    end
    for(int index = 0; index < 6; index++) begin
      if(!address_bins[index])
        $fatal(1, "command encoder mismatch missing address bin=%0d", index);
      bins_hit++;
    end
    for(int index = 0; index < 5; index++) begin
      if(!abt_bins[index])
        $fatal(1, "command encoder mismatch missing ABT bin=%0d", index);
      bins_hit++;
    end
    for(int index = 0; index < 256; index++) begin
      if(!tag_bins[index])
        $fatal(1, "command encoder mismatch missing tag bin=%0d", index);
      bins_hit++;
    end
    for(int field_index = 0; field_index < 3; field_index++) begin
      for(int parity_value = 0; parity_value < 2; parity_value++) begin
        if(!parity_bins[field_index][parity_value])
          $fatal(
            1,
            "command encoder mismatch missing parity field=%0d value=%0d",
            field_index,
            parity_value
          );
        bins_hit++;
      end
    end
    for(int index = 0; index < 3; index++) begin
      if(!stall_bins[index])
        $fatal(1, "command encoder mismatch missing stall bin=%0d", index);
      bins_hit++;
    end
    for(int index = 0; index < 8; index++) begin
      if(!pipeline_bins[index])
        $fatal(1, "command encoder mismatch missing pipeline bin=%0d", index);
      bins_hit++;
    end

    $display(
      "PASS protocol_control dut=command_control checks=%0d bins=%0d/315",
      checks,
      bins_hit
    );
    $finish;
  end

endmodule
