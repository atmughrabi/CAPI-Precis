module afu_wrapper_tb;

  import GLOBALS_AFU_PKG::*;
  import CAPI_PKG::*;

  logic clock = 0;
  logic ah_cvalid;
  logic [0:7] ah_ctag;
  logic ah_ctagpar;
  logic [0:12] ah_com;
  logic ah_compar;
  logic [0:2] ah_cabt;
  logic [0:63] ah_cea;
  logic ah_ceapar;
  logic [0:15] ah_cch;
  logic [0:11] ah_csize;
  logic [0:7] ha_croom;
  logic ha_brvalid;
  logic [0:7] ha_brtag;
  logic ha_brtagpar;
  logic [0:5] ha_brad;
  logic [0:3] ah_brlat;
  logic [0:511] ah_brdata;
  logic [0:7] ah_brpar;
  logic ha_bwvalid;
  logic [0:7] ha_bwtag;
  logic ha_bwtagpar;
  logic [0:5] ha_bwad;
  logic [0:511] ha_bwdata;
  logic [0:7] ha_bwpar;
  logic ha_rvalid;
  logic [0:7] ha_rtag;
  logic ha_rtagpar;
  logic [0:7] ha_response;
  logic [0:8] ha_rcredits;
  logic [0:1] ha_rcachestate;
  logic [0:12] ha_rcachepos;
  logic ha_mmval;
  logic ha_mmcfg;
  logic ha_mmrnw;
  logic ha_mmdw;
  logic [0:23] ha_mmad;
  logic ha_mmadpar;
  logic [0:63] ha_mmdata;
  logic ha_mmdatapar;
  logic ah_mmack;
  logic [0:63] ah_mmdata;
  logic ah_mmdatapar;
  logic ha_jval;
  logic [0:7] ha_jcom;
  logic ha_jcompar;
  logic [0:63] ha_jea;
  logic ha_jeapar;
  logic ah_jrunning;
  logic ah_jdone;
  logic ah_jcack;
  logic [0:63] ah_jerror;
  logic ah_jyield;
  logic ah_tbreq;
  logic ah_paren;

  int unsigned bins_hit;
  int unsigned assertions_checked;

  always #5 clock = ~clock;

  afu dut (
    .ah_cvalid(ah_cvalid),
    .ah_ctag(ah_ctag),
    .ah_ctagpar(ah_ctagpar),
    .ah_com(ah_com),
    .ah_compar(ah_compar),
    .ah_cabt(ah_cabt),
    .ah_cea(ah_cea),
    .ah_ceapar(ah_ceapar),
    .ah_cch(ah_cch),
    .ah_csize(ah_csize),
    .ha_croom(ha_croom),
    .ha_brvalid(ha_brvalid),
    .ha_brtag(ha_brtag),
    .ha_brtagpar(ha_brtagpar),
    .ha_brad(ha_brad),
    .ah_brlat(ah_brlat),
    .ah_brdata(ah_brdata),
    .ah_brpar(ah_brpar),
    .ha_bwvalid(ha_bwvalid),
    .ha_bwtag(ha_bwtag),
    .ha_bwtagpar(ha_bwtagpar),
    .ha_bwad(ha_bwad),
    .ha_bwdata(ha_bwdata),
    .ha_bwpar(ha_bwpar),
    .ha_rvalid(ha_rvalid),
    .ha_rtag(ha_rtag),
    .ha_rtagpar(ha_rtagpar),
    .ha_response(ha_response),
    .ha_rcredits(ha_rcredits),
    .ha_rcachestate(ha_rcachestate),
    .ha_rcachepos(ha_rcachepos),
    .ha_mmval(ha_mmval),
    .ha_mmcfg(ha_mmcfg),
    .ha_mmrnw(ha_mmrnw),
    .ha_mmdw(ha_mmdw),
    .ha_mmad(ha_mmad),
    .ha_mmadpar(ha_mmadpar),
    .ha_mmdata(ha_mmdata),
    .ha_mmdatapar(ha_mmdatapar),
    .ah_mmack(ah_mmack),
    .ah_mmdata(ah_mmdata),
    .ah_mmdatapar(ah_mmdatapar),
    .ha_jval(ha_jval),
    .ha_jcom(ha_jcom),
    .ha_jcompar(ha_jcompar),
    .ha_jea(ha_jea),
    .ha_jeapar(ha_jeapar),
    .ah_jrunning(ah_jrunning),
    .ah_jdone(ah_jdone),
    .ah_jcack(ah_jcack),
    .ah_jerror(ah_jerror),
    .ah_jyield(ah_jyield),
    .ah_tbreq(ah_tbreq),
    .ah_paren(ah_paren),
    .ha_pclock(clock)
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
      $fatal(1, "afu wrapper requirement failed: %s", message);
  endtask

  function automatic logic [0:7] odd_parity_512(input logic [0:511] value);
    logic [0:7] result;
    for(int lane = 0; lane < 8; lane++)
      result[lane] = logic'(($countones(value[lane * 64 +: 64]) + 1) % 2);
    return result;
  endfunction

  task automatic clear_inputs;
    ha_croom = 8;
    ha_brvalid = 0;
    ha_brtag = 0;
    ha_brtagpar = 0;
    ha_brad = 0;
    ha_bwvalid = 0;
    ha_bwtag = 0;
    ha_bwtagpar = 0;
    ha_bwad = 0;
    ha_bwdata = 0;
    ha_bwpar = 0;
    ha_rvalid = 0;
    ha_rtag = 0;
    ha_rtagpar = 0;
    ha_response = DONE;
    ha_rcredits = 0;
    ha_rcachestate = 0;
    ha_rcachepos = 0;
    ha_mmval = 0;
    ha_mmcfg = 0;
    ha_mmrnw = 0;
    ha_mmdw = 1;
    ha_mmad = 0;
    ha_mmadpar = 0;
    ha_mmdata = 0;
    ha_mmdatapar = 0;
    ha_jval = 0;
    ha_jcom = RESET;
    ha_jcompar = 0;
    ha_jea = 0;
    ha_jeapar = 0;
  endtask

  task automatic coverage_toggle_sweep;
    clear_inputs();
    tick(3);
    ha_croom = '1;
    ha_brvalid = 1;
    ha_brtag = '1;
    ha_brtagpar = 1;
    ha_brad = '1;
    ha_bwvalid = 1;
    ha_bwtag = '1;
    ha_bwtagpar = 1;
    ha_bwad = '1;
    ha_bwdata = '1;
    ha_bwpar = '1;
    ha_rvalid = 1;
    ha_rtag = '1;
    ha_rtagpar = 1;
    ha_response = '1;
    ha_rcredits = '1;
    ha_rcachestate = '1;
    ha_rcachepos = '1;
    ha_mmval = 1;
    ha_mmcfg = 1;
    ha_mmrnw = 1;
    ha_mmdw = 1;
    ha_mmad = '1;
    ha_mmadpar = 1;
    ha_mmdata = '1;
    ha_mmdatapar = 1;
    ha_jval = 1;
    ha_jcom = '1;
    ha_jcompar = 1;
    ha_jea = '1;
    ha_jeapar = 1;
    tick(4);
    clear_inputs();
    tick(4);
    send_job(RESET, 0);
    tick(30);
  endtask

  task automatic send_job(input job_command_t command, input logic [0:63] address);
    ha_jval = 1;
    ha_jcom = command;
    ha_jcompar = logic'(($countones(command) + 1) % 2);
    ha_jea = address;
    ha_jeapar = logic'(($countones(address) + 1) % 2);
    tick();
    ha_jval = 0;
  endtask

  task automatic mmio_write(input logic [0:23] address, input logic [0:63] data);
    bit ack_seen;
    ha_mmval = 1;
    ha_mmrnw = 0;
    ha_mmdw = 1;
    ha_mmad = address;
    ha_mmadpar = logic'(($countones(address) + 1) % 2);
    ha_mmdata = data;
    ha_mmdatapar = logic'(($countones(data) + 1) % 2);
    tick();
    ha_mmval = 0;
    ack_seen = 0;
    repeat(20) begin
      tick();
      ack_seen |= ah_mmack;
    end
    require(ack_seen, "wrapper MMIO write ack");
  endtask

  task automatic mmio_read(input logic [0:23] address, output logic [0:63] data);
    bit ack_seen;
    ha_mmval = 1;
    ha_mmrnw = 1;
    ha_mmdw = 1;
    ha_mmad = address;
    ha_mmadpar = logic'(($countones(address) + 1) % 2);
    ha_mmdata = 0;
    ha_mmdatapar = 1;
    tick();
    ha_mmval = 0;
    ack_seen = 0;
    data = 0;
    repeat(20) begin
      tick();
      if(ah_mmack) begin
        ack_seen = 1;
        data = ah_mmdata;
        require(ah_mmdatapar == logic'(($countones(ah_mmdata) + 1) % 2),
                "wrapper MMIO parity");
      end
    end
    require(ack_seen, "wrapper MMIO read ack");
  endtask

  task automatic wait_command(
      input afu_command_t command,
      input logic [0:63] address,
      output logic [0:7] tag
  );
    bit found;
    found = 0;
    tag = 0;
    repeat(500) begin
      tick();
      if(ah_cvalid && !found) begin
        found = 1;
        tag = ah_ctag;
        require(ah_com == command, "wrapper command code");
        require(ah_cea == address, "wrapper command address");
        require(ah_ctagpar == logic'(($countones(ah_ctag) + 1) % 2),
                "wrapper tag parity");
        require(ah_compar == logic'(($countones(ah_com) + 1) % 2),
                "wrapper command parity");
        require(ah_ceapar == logic'(($countones(ah_cea) + 1) % 2),
                "wrapper address parity");
        require(ah_cch == 0, "wrapper context handle");
      end
    end
    require(found, "wrapper command missing");
  endtask

  task automatic send_half(
      input logic [0:7] tag,
      input logic [0:5] half,
      input logic [0:511] data
  );
    ha_bwvalid = 1;
    ha_bwtag = tag;
    ha_bwtagpar = logic'(($countones(tag) + 1) % 2);
    ha_bwad = half;
    ha_bwdata = data;
    ha_bwpar = odd_parity_512(data);
    tick();
    ha_bwvalid = 0;
  endtask

  task automatic send_response(input logic [0:7] tag);
    ha_rvalid = 1;
    ha_rtag = tag;
    ha_rtagpar = logic'(($countones(tag) + 1) % 2);
    ha_response = DONE;
    ha_rcredits = 1;
    tick();
    ha_rvalid = 0;
  endtask

  task automatic request_half(
      input logic [0:7] tag,
      input logic [0:5] half,
      input logic [0:511] expected
  );
    ha_brvalid = 1;
    ha_brtag = tag;
    ha_brtagpar = logic'(($countones(tag) + 1) % 2);
    ha_brad = half;
    tick();
    ha_brvalid = 0;
    tick(ah_brlat + 4);
    require(ah_brdata == expected, "wrapper write-buffer data");
    require(ah_brpar == odd_parity_512(expected), "wrapper write-buffer parity");
  endtask

  task automatic run_job;
    logic [0:1023] wed_cacheline;
    logic [0:511] lower;
    logic [0:511] upper;
    logic [0:63] afu_word;
    logic [0:63] cu_word;
    logic [0:63] done_1;
    logic [0:63] done_2;
    logic [0:7] wed_tag;
    logic [0:7] read_tag;
    logic [0:7] write_tag;
    bit running_seen;

    send_job(RESET, 0);
    tick(30);
    send_job(START, 64'h1200_0000);
    running_seen = 0;
    repeat(80) begin
      tick();
      running_seen |= ah_jrunning;
    end
    require(running_seen, "wrapper job running");
    require(ah_paren, "wrapper parity enable");
    require(!ah_tbreq && !ah_jcack && !ah_jyield, "wrapper fixed control outputs");

    afu_word = '0;
    afu_word[62] = 1;
    cu_word = '0;
    cu_word[22] = 1;
    cu_word[23] = 1;
    mmio_write(AFU_CONFIGURE, afu_word);
    mmio_write(CU_CONFIGURE, cu_word);
    mmio_write(CU_CONFIGURE_3, 1);
    mmio_write(CU_CONFIGURE_4, 1);

    wait_command(READ_CL_NA, 64'h1200_0000, wed_tag);
    wed_cacheline = '0;
    wed_cacheline[0:63] = swap_endianness_double_word(1);
    wed_cacheline[64:127] = swap_endianness_double_word(1);
    wed_cacheline[128:191] = swap_endianness_double_word(64'h2200_0000);
    wed_cacheline[192:255] = swap_endianness_double_word(64'h3200_0000);
    send_half(wed_tag, 1, wed_cacheline[512:1023]);
    send_half(wed_tag, 0, wed_cacheline[0:511]);
    tick(6);
    send_response(wed_tag);

    lower = {8{64'h1234_5678_9abc_def0}};
    upper = {8{64'h0fed_cba9_8765_4321}};
    wait_command(READ_PNA, 64'h2200_0000, read_tag);
    send_half(read_tag, 1, upper);
    send_half(read_tag, 0, lower);
    tick(6);
    send_response(read_tag);

    wait_command(WRITE_NA, 64'h3200_0000, write_tag);
    request_half(write_tag, 0, lower);
    request_half(write_tag, 1, upper);
    send_response(write_tag);
    tick(120);
    mmio_read(CU_RETURN_DONE, done_1);
    mmio_read(CU_RETURN_DONE_2, done_2);
    require(done_1 == 1 && done_2 == 1, "wrapper completion counters");
    mmio_write(CU_RETURN_DONE_ACK, 1);
    send_job(RESET, 0);
    tick(40);
    require(!ah_cvalid, "wrapper command leaked after reset");
    bins_hit++;
  endtask

  task automatic wrapper_error_case;
    bit error_seen;

    send_job(RESET, 0);
    tick(30);
    ha_jval = 1;
    ha_jcom = START;
    ha_jcompar = ~logic'(($countones(START) + 1) % 2);
    ha_jea = 64'h1500_0000;
    ha_jeapar = ~logic'(($countones(64'h1500_0000) + 1) % 2);
    tick();
    ha_jval = 0;
    tick(60);
    send_job(RESET, 0);
    error_seen = 0;
    repeat(100) begin
      tick();
      error_seen |= |ah_jerror;
    end
    require(error_seen, "wrapper did not publish job parity error");
    bins_hit++;
  endtask

  task automatic run_context_smoke;
    logic [0:1023] wed_cacheline;
    logic [0:63] afu_word;
    logic [0:63] cu_word;
    logic [0:63] tile_index;
    logic [0:7] wed_tag;
    bit cu_command_seen;
    string context_name;

    if(!$value$plusargs("CONTEXT=%s", context_name))
      context_name = "unknown";
    send_job(RESET, 0);
    tick(30);
    send_job(START, 64'h1600_0000);
    tick(40);
    afu_word = 0;
    afu_word[62] = 1;
    cu_word = 0;
    cu_word[22] = 1;
    cu_word[23] = 1;
    tile_index = 0;
    tile_index[63] = 1;
    mmio_write(AFU_CONFIGURE, afu_word);
    mmio_write(CU_CONFIGURE, cu_word);
    mmio_write(CU_CONFIGURE_2, tile_index);
    mmio_write(CU_CONFIGURE_3, tile_index);
    mmio_write(CU_CONFIGURE_4, tile_index);

    wait_command(READ_CL_NA, 64'h1600_0000, wed_tag);
    wed_cacheline = 0;
    wed_cacheline[0:63] = swap_endianness_double_word(1);
    wed_cacheline[64:127] = swap_endianness_double_word(1);
    wed_cacheline[128:191] =
        swap_endianness_double_word(64'h2600_0000);
    wed_cacheline[192:255] =
        swap_endianness_double_word(64'h3600_0000);
    wed_cacheline[256:319] =
        swap_endianness_double_word(64'h4600_0000);
    send_half(wed_tag, 1, wed_cacheline[512:1023]);
    send_half(wed_tag, 0, wed_cacheline[0:511]);
    tick(6);
    send_response(wed_tag);

    cu_command_seen = 0;
    repeat(700) begin
      tick();
      if(ah_cvalid && ah_cea != 64'h1600_0000) begin
        cu_command_seen = 1;
        require(ah_ctagpar == logic'(($countones(ah_ctag) + 1) % 2),
                "context command tag parity");
        require(ah_compar == logic'(($countones(ah_com) + 1) % 2),
                "context command parity");
        require(ah_ceapar == logic'(($countones(ah_cea) + 1) % 2),
                "context command address parity");
      end
      if(cu_command_seen)
        break;
    end
    require(cu_command_seen, "context CU command missing");
    send_job(RESET, 0);
    tick(40);
    require(!ah_cvalid, "context command leaked after reset");
    $display(
      "PASS afu_wrapper_context context=%s commands=1 assertions=%0d",
      context_name,
      assertions_checked
    );
  endtask

  initial begin
    bins_hit = 0;
    assertions_checked = 0;
    clear_inputs();
    tick(10);
    if($test$plusargs("CONTEXT_SMOKE")) begin
      run_context_smoke();
      $finish;
    end
    coverage_toggle_sweep();
    run_job();
    wrapper_error_case();
    require(bins_hit == 2, "functional bin denominator");
    $display(
      "PASS afu_wrapper_integration bins=%0d/2 assertions=%0d",
      bins_hit,
      assertions_checked
    );
    $finish;
  end

endmodule
