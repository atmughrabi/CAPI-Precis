module tag_control_tb;

  import CAPI_PKG::*;
  import AFU_PKG::*;
  import CU_PKG::*;
  import PROTOCOL_TB_PKG::*;

  logic clock;
  logic rstn_in;
  logic enabled_in;
  logic tag_response_valid;
  logic [0:7] response_tag;
  CommandTagLine response_tag_id_out;
  logic [0:7] data_read_tag;
  CommandTagLine data_read_tag_id_out;
  logic tag_command_valid;
  CommandTagLine tag_command_id;
  logic [0:7] command_tag_out;
  logic tag_buffer_ready;

  CommandTagLine metadata_model [0:255];
  bit metadata_valid [0:255];
  int unsigned checks;
  int unsigned bins_hit;
  bit initial_tag_bins [0:242];
  bit wrap_tag_bins [0:15];
  bit initialization_bin;
  bit exhaustion_bin;
  bit reuse_bin;
  bit dual_read_bin;
  bit unknown_bin;
  bit bounded_release_bin;

  tag_control dut (
    .clock(clock),
    .rstn_in(rstn_in),
    .enabled_in(enabled_in),
    .tag_response_valid(tag_response_valid),
    .response_tag(response_tag),
    .response_tag_id_out(response_tag_id_out),
    .data_read_tag(data_read_tag),
    .data_read_tag_id_out(data_read_tag_id_out),
    .tag_command_valid(tag_command_valid),
    .tag_command_id(tag_command_id),
    .command_tag_out(command_tag_out),
    .tag_buffer_ready(tag_buffer_ready)
  );

  always #5 clock = ~clock;

  task automatic tick;
    @(posedge clock);
    #1;
  endtask

  task automatic wait_ready(input string phase, input int unsigned bound);
    int unsigned waited;
    waited = 0;
    while(!tag_buffer_ready && waited < bound) begin
      tick();
      waited++;
    end
    if(waited == bound)
      $fatal(1, "tag allocator mismatch timeout phase=%s bound=%0d", phase, bound);
  endtask

  task automatic issue_expected_tag(
      input logic [0:7] expected_tag,
      input CommandTagLine expected_metadata
  );
    @(negedge clock);
    tag_command_id = expected_metadata;
    tag_command_valid = 1;
    #1;
    checks++;
    if(command_tag_out !== expected_tag)
      $fatal(
        1,
        "tag allocator mismatch expected_tag=%0d actual_tag=%0d",
        expected_tag,
        command_tag_out
      );
    @(posedge clock);
    #1;
    metadata_model[expected_tag] = expected_metadata;
    metadata_valid[expected_tag] = 1;
    @(negedge clock);
    tag_command_valid = 0;
  endtask

  task automatic return_tag_to_pool(input logic [0:7] returned_tag);
    @(negedge clock);
    response_tag = returned_tag;
    tag_response_valid = 1;
    tick();
    @(negedge clock);
    tag_response_valid = 0;
  endtask

  task automatic check_lookup(
      input logic [0:7] response_lookup_tag,
      input logic [0:7] data_lookup_tag,
      input bit response_known,
      input bit data_known
  );
    @(negedge clock);
    response_tag = response_lookup_tag;
    data_read_tag = data_lookup_tag;
    repeat(2) tick();
    checks++;
    if(
      (response_known && response_tag_id_out !== metadata_model[response_lookup_tag]) ||
      (!response_known && response_tag_id_out !== '0) ||
      (data_known && data_read_tag_id_out !== metadata_model[data_lookup_tag]) ||
      (!data_known && data_read_tag_id_out !== '0)
    )
      $fatal(
        1,
        "tag allocator mismatch lookup response_tag=%0d data_tag=%0d",
        response_lookup_tag,
        data_lookup_tag
      );
  endtask

  initial begin
    clock = 0;
    rstn_in = 0;
    enabled_in = 0;
    tag_response_valid = 0;
    response_tag = 0;
    data_read_tag = 0;
    tag_command_valid = 0;
    tag_command_id = '0;
    checks = 0;
    bins_hit = 0;
    for(int tag = 0; tag < 256; tag++) begin
      metadata_model[tag] = '0;
      metadata_valid[tag] = 0;
    end

    repeat(3) tick();
    rstn_in = 1;
    enabled_in = 1;
    wait_ready("initialization", 300);
    initialization_bin = 1;

    for(int tag = 0; tag < 243; tag++) begin
      CommandTagLine issued_metadata;
      issued_metadata = tag[0] ? '1 : '0;
      issued_metadata.cu_id_x = tag[7:0];
      issued_metadata.cu_id_y = ~tag[7:0];
      issued_metadata.array_struct = array_struct_type'((tag % 3) + 1);
      issued_metadata.cmd_type = command_type'((tag % 6) + 1);
      issued_metadata.real_size = tag[7:0] ^ 8'h96;
      issued_metadata.real_size_bytes = tag[7:0] ^ 8'h69;
      issued_metadata.cacheline_offset = tag[7:0] ^ 8'ha5;
      issued_metadata.address_offset =
        tag[0] ? 64'ha55a_f00f_9669_c33c : 64'h5aa5_0ff0_6996_3cc3;
      issued_metadata.aux_data = ~issued_metadata.address_offset;
      issued_metadata.size = tag[11:0] ^ 12'ha5a;
      issued_metadata.tag = tag[7:0];
      issued_metadata.abt = legal_abt(tag % 5);
      issue_expected_tag(tag[7:0], issued_metadata);
      initial_tag_bins[tag] = 1;
    end

    repeat(4) tick();
    checks++;
    if(tag_buffer_ready)
      $fatal(
        1,
        "tag allocator mismatch exhaustion did not stall count=%0d next=%0d",
        dut.tag_buffer_fifo_instant.count,
        command_tag_out
      );
    exhaustion_bin = 1;

    for(int stall_cycle = 0; stall_cycle < 4; stall_cycle++) begin
      tick();
      checks++;
      if(tag_buffer_ready)
        $fatal(1, "tag allocator mismatch exhaustion stall released early");
    end

    for(int index = 0; index < 16; index++)
      return_tag_to_pool((8'hef - index));
    wait_ready("bounded-return-release", 24);
    bounded_release_bin = 1;

    for(int index = 0; index < 16; index++) begin
      logic [0:7] expected_tag;
      CommandTagLine replacement_metadata;
      expected_tag = 8'hef - index;
      replacement_metadata = expected_tag[0] ? '1 : '0;
      replacement_metadata.cmd_type = CMD_WRITE;
      replacement_metadata.array_struct = WRITE_DATA;
      replacement_metadata.tag = expected_tag;
      replacement_metadata.abt = SPEC;
      replacement_metadata.real_size_bytes = 8'd16 + index;
      replacement_metadata.aux_data = 64'hfeed_0000_0000_0000 | index;
      issue_expected_tag(expected_tag, replacement_metadata);
      wrap_tag_bins[index] = 1;
    end
    reuse_bin = 1;

    check_lookup(8'hef, 8'he0, 1, 1);
    dual_read_bin = 1;
    for(int lookup = 0; lookup < 32; lookup++)
      check_lookup(lookup[7:0], (31-lookup), 1, 1);
    check_lookup(8'h80, 8'h80, 1, 1);
    check_lookup(8'hfa, 8'hfb, 0, 0);
    unknown_bin = 1;

    for(int tag = 0; tag < 243; tag++) begin
      if(!initial_tag_bins[tag])
        $fatal(1, "tag allocator mismatch missing initial tag bin=%0d", tag);
      bins_hit++;
    end
    for(int index = 0; index < 16; index++) begin
      if(!wrap_tag_bins[index])
        $fatal(1, "tag allocator mismatch missing wrap bin=%0d", index);
      bins_hit++;
    end
    if(
      !initialization_bin ||
      !exhaustion_bin ||
      !reuse_bin ||
      !dual_read_bin ||
      !unknown_bin ||
      !bounded_release_bin
    )
      $fatal(1, "tag allocator mismatch missing lifecycle bin");
    bins_hit += 6;

    $display(
      "PASS protocol_control dut=tag_control checks=%0d bins=%0d/265",
      checks,
      bins_hit
    );
    $finish;
  end

endmodule
