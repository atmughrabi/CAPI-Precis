`timescale 1ns/1ps

module storage_tb;

  logic clock;

  logic       r1_we;
  logic [0:0] r1_wr_addr;
  logic [0:0] r1_data_in;
  logic [0:0] r1_rd_addr;
  logic [0:0] r1_data_out;

  logic       r3_we;
  logic [0:1] r3_wr_addr;
  logic [0:7] r3_data_in;
  logic [0:1] r3_rd_addr;
  logic [0:7] r3_data_out;

  logic        r2_we;
  logic [0:2]  r2_wr_addr;
  logic [0:16] r2_data_in;
  logic [0:2]  r2_rd_addr1;
  logic [0:16] r2_data_out1;
  logic [0:2]  r2_rd_addr2;
  logic [0:16] r2_data_out2;

  logic        mw_we;
  logic [0:1]  mw_wr_addr;
  logic [0:31] mw_data_in;
  logic [0:3]  mw_rd_addr;
  logic [0:7]  mw_data_out;

  logic        mr_we;
  logic [0:3]  mr_wr_addr;
  logic [0:7]  mr_data_in;
  logic [0:1]  mr_rd_addr;
  logic [0:31] mr_data_out;

  logic       me_we;
  logic [0:1] me_wr_addr;
  logic [0:7] me_data_in;
  logic [0:1] me_rd_addr;
  logic [0:7] me_data_out;

  logic       fifo_rstn;
  logic       fifo_push;
  logic [7:0] fifo_data_in;
  logic       fifo_full;
  logic       fifo_alfull;
  logic       fifo_pop;
  logic       fifo_valid;
  logic [7:0] fifo_data_out;
  logic       fifo_empty;

  logic       fifo1_rstn;
  logic       fifo1_push;
  logic [0:0] fifo1_data_in;
  logic       fifo1_full;
  logic       fifo1_alfull;
  logic       fifo1_pop;
  logic       fifo1_valid;
  logic [0:0] fifo1_data_out;
  logic       fifo1_empty;

  logic       fifo5_rstn;
  logic       fifo5_push;
  logic [7:0] fifo5_data_in;
  logic       fifo5_full;
  logic       fifo5_alfull;
  logic       fifo5_pop;
  logic       fifo5_valid;
  logic [7:0] fifo5_data_out;
  logic       fifo5_empty;

  logic [0:0]  r1_model;
  logic [0:7]  r3_model [0:2];
  logic [0:16] r2_model [0:4];
  logic [0:7]  mw_model [0:11];
  logic [0:7]  mr_model [0:11];
  logic [0:7]  me_model [0:2];

  logic [7:0] fifo_model [0:7];
  int fifo_head;
  int fifo_tail;
  int fifo_count;
  bit fifo_p0_valid;
  bit fifo_p1_valid;
  logic [7:0] fifo_p0_data;
  logic [7:0] fifo_p1_data;
  bit model_empty;
  bit model_full;
  bit model_alfull;

  logic [0:0] fifo1_model;
  int fifo1_count;
  bit fifo1_p0_valid;
  bit fifo1_p1_valid;
  logic [0:0] fifo1_p0_data;
  logic [0:0] fifo1_p1_data;
  bit model1_empty;
  bit model1_full;
  bit model1_alfull;

  logic [7:0] fifo5_model [0:4];
  int fifo5_head;
  int fifo5_tail;
  int fifo5_count;
  bit fifo5_p0_valid;
  bit fifo5_p1_valid;
  logic [7:0] fifo5_p0_data;
  logic [7:0] fifo5_p1_data;
  bit model5_empty;
  bit model5_full;
  bit model5_alfull;

  int unsigned vectors;
  int unsigned checks;
  int unsigned bins_hit;
  bit functional_bins [0:32];

  ram #(
    .WIDTH(1),
    .DEPTH(1)
  ) ram_depth1 (
    .clock    (clock      ),
    .we       (r1_we      ),
    .wr_addr  (r1_wr_addr ),
    .data_in  (r1_data_in ),
    .rd_addr  (r1_rd_addr ),
    .data_out (r1_data_out)
  );

  ram #(
    .WIDTH(8),
    .DEPTH(3),
    .ADDR_BITS(2)
  ) ram_depth3 (
    .clock    (clock      ),
    .we       (r3_we      ),
    .wr_addr  (r3_wr_addr ),
    .data_in  (r3_data_in ),
    .rd_addr  (r3_rd_addr ),
    .data_out (r3_data_out)
  );

  ram_2xrd #(
    .WIDTH(17),
    .DEPTH(5),
    .ADDR_BITS(3)
  ) ram_dual (
    .clock     (clock       ),
    .we        (r2_we       ),
    .wr_addr   (r2_wr_addr  ),
    .data_in   (r2_data_in  ),
    .rd_addr1  (r2_rd_addr1 ),
    .data_out1 (r2_data_out1),
    .rd_addr2  (r2_rd_addr2 ),
    .data_out2 (r2_data_out2)
  );

  mixed_width_ram #(
    .WORDS(3),
    .RW(8),
    .WW(32)
  ) mixed_read_narrow (
    .we       (mw_we      ),
    .clock    (clock      ),
    .wr_addr  (mw_wr_addr ),
    .data_in  (mw_data_in ),
    .rd_addr  (mw_rd_addr ),
    .data_out (mw_data_out)
  );

  mixed_width_ram #(
    .WORDS(3),
    .RW(32),
    .WW(8)
  ) mixed_write_narrow (
    .we       (mr_we      ),
    .clock    (clock      ),
    .wr_addr  (mr_wr_addr ),
    .data_in  (mr_data_in ),
    .rd_addr  (mr_rd_addr ),
    .data_out (mr_data_out)
  );

  mixed_width_ram #(
    .WORDS(3),
    .RW(8),
    .WW(8)
  ) mixed_equal (
    .we       (me_we      ),
    .clock    (clock      ),
    .wr_addr  (me_wr_addr ),
    .data_in  (me_data_in ),
    .rd_addr  (me_rd_addr ),
    .data_out (me_data_out)
  );

  fifo #(
    .WIDTH(8),
    .DEPTH(8),
    .ADDR_BITS(3),
    .HEADROOM(3)
  ) fifo_depth8 (
    .clock    (clock        ),
    .rstn     (fifo_rstn    ),
    .push     (fifo_push    ),
    .data_in  (fifo_data_in ),
    .full     (fifo_full    ),
    .alFull   (fifo_alfull  ),
    .pop      (fifo_pop     ),
    .valid    (fifo_valid   ),
    .data_out (fifo_data_out),
    .empty    (fifo_empty   )
  );

  fifo #(
    .WIDTH(1),
    .DEPTH(1),
    .HEADROOM(0)
  ) fifo_depth1 (
    .clock    (clock         ),
    .rstn     (fifo1_rstn    ),
    .push     (fifo1_push    ),
    .data_in  (fifo1_data_in ),
    .full     (fifo1_full    ),
    .alFull   (fifo1_alfull  ),
    .pop      (fifo1_pop     ),
    .valid    (fifo1_valid   ),
    .data_out (fifo1_data_out),
    .empty    (fifo1_empty   )
  );

  fifo #(
    .WIDTH(8),
    .DEPTH(5),
    .HEADROOM(3)
  ) fifo_depth5 (
    .clock    (clock         ),
    .rstn     (fifo5_rstn    ),
    .push     (fifo5_push    ),
    .data_in  (fifo5_data_in ),
    .full     (fifo5_full    ),
    .alFull   (fifo5_alfull  ),
    .pop      (fifo5_pop     ),
    .valid    (fifo5_valid   ),
    .data_out (fifo5_data_out),
    .empty    (fifo5_empty   )
  );

  always #5 clock = ~clock;

  task automatic expect_word(
      input string instance_name,
      input string behavior,
      input logic [0:31] actual,
      input logic [0:31] expected
  );
    checks++;
    if(actual !== expected) begin
      $error(
        "storage mismatch instance=%s behavior=%s vector=%0d expected=%0h actual=%0h",
        instance_name,
        behavior,
        vectors,
        expected,
        actual
      );
      $fatal(1);
    end
  endtask

  task automatic r1_cycle(
      input logic we_value,
      input logic data_value,
      input logic expected
  );
    @(negedge clock);
    r1_we = we_value;
    r1_wr_addr = 0;
    r1_data_in = data_value;
    r1_rd_addr = 0;
    @(posedge clock);
    #1;
    expect_word("ram-depth1", "registered-read", r1_data_out, expected);
    if(we_value)
      r1_model = data_value;
    vectors++;
  endtask

  task automatic r3_cycle(
      input logic we_value,
      input int wr_addr,
      input logic [0:7] data_value,
      input int rd_addr,
      input logic [0:7] expected
  );
    @(negedge clock);
    r3_we = we_value;
    r3_wr_addr = wr_addr[1:0];
    r3_data_in = data_value;
    r3_rd_addr = rd_addr[1:0];
    @(posedge clock);
    #1;
    expect_word("ram-depth3", "registered-read", r3_data_out, expected);
    if(we_value)
      r3_model[wr_addr] = data_value;
    vectors++;
  endtask

  task automatic r2_cycle(
      input logic we_value,
      input int wr_addr,
      input logic [0:16] data_value,
      input int rd_addr1,
      input int rd_addr2,
      input logic [0:16] expected1,
      input logic [0:16] expected2
  );
    @(negedge clock);
    r2_we = we_value;
    r2_wr_addr = wr_addr[2:0];
    r2_data_in = data_value;
    r2_rd_addr1 = rd_addr1[2:0];
    r2_rd_addr2 = rd_addr2[2:0];
    @(posedge clock);
    #1;
    expect_word("ram-2xrd-port1", "registered-read", r2_data_out1, expected1);
    expect_word("ram-2xrd-port2", "registered-read", r2_data_out2, expected2);
    if(we_value)
      r2_model[wr_addr] = data_value;
    vectors++;
  endtask

  task automatic mw_cycle(
      input logic we_value,
      input int wr_addr,
      input logic [0:31] data_value,
      input int rd_addr,
      input logic check_output,
      input logic [0:7] expected
  );
    @(negedge clock);
    mw_we = we_value;
    mw_wr_addr = wr_addr[1:0];
    mw_data_in = data_value;
    mw_rd_addr = rd_addr[3:0];
    @(posedge clock);
    #1;
    if(check_output)
      expect_word("mixed-read-narrow", "registered-read", mw_data_out, expected);
    if(we_value)
      for(int lane = 0; lane < 4; lane++)
        mw_model[wr_addr * 4 + lane] = data_value[8 * lane +: 8];
    vectors++;
  endtask

  function automatic logic [0:31] mr_word(input int rd_addr);
    for(int lane = 0; lane < 4; lane++)
      mr_word[8 * lane +: 8] = mr_model[rd_addr * 4 + lane];
  endfunction

  task automatic mr_cycle(
      input logic we_value,
      input int wr_addr,
      input logic [0:7] data_value,
      input int rd_addr,
      input logic check_output,
      input logic [0:31] expected
  );
    @(negedge clock);
    mr_we = we_value;
    mr_wr_addr = wr_addr[3:0];
    mr_data_in = data_value;
    mr_rd_addr = rd_addr[1:0];
    @(posedge clock);
    #1;
    if(check_output)
      expect_word("mixed-write-narrow", "registered-read", mr_data_out, expected);
    if(we_value)
      mr_model[wr_addr] = data_value;
    vectors++;
  endtask

  task automatic me_cycle(
      input logic we_value,
      input int wr_addr,
      input logic [0:7] data_value,
      input int rd_addr,
      input logic check_output,
      input logic [0:7] expected
  );
    @(negedge clock);
    me_we = we_value;
    me_wr_addr = wr_addr[1:0];
    me_data_in = data_value;
    me_rd_addr = rd_addr[1:0];
    @(posedge clock);
    #1;
    if(check_output)
      expect_word("mixed-equal-width", "registered-read", me_data_out, expected);
    if(we_value)
      me_model[wr_addr] = data_value;
    vectors++;
  endtask

  task automatic check_fifo_flags(input string behavior);
    expect_word("fifo-depth8", {behavior, "-empty"}, fifo_empty, model_empty);
    expect_word("fifo-depth8", {behavior, "-valid"}, fifo_valid, !model_empty);
    expect_word("fifo-depth8", {behavior, "-full"}, fifo_full, model_full);
    expect_word("fifo-depth8", {behavior, "-almost-full"}, fifo_alfull, model_alfull);
  endtask

  task automatic fifo_step(
      input logic push_value,
      input logic pop_value,
      input logic [7:0] data_value
  );
    int old_count;
    bit pop_accepted;
    bit push_accepted;
    bit old_p1_valid;
    logic [7:0] old_p1_data;

    @(negedge clock);
    fifo_push = push_value;
    fifo_pop = pop_value;
    fifo_data_in = data_value;
    #1;
    check_fifo_flags("pre-edge");
    if(pop_value && !model_empty)
      expect_word(
        "fifo-depth8",
        "queue-order",
        fifo_data_out,
        fifo_model[fifo_head]
      );
    else
      expect_word("fifo-depth8", "blocked-pop-output", fifo_data_out, 0);

    old_count = fifo_count;
    pop_accepted = pop_value && !model_empty;
    push_accepted = push_value && !model_full;
    old_p1_valid = fifo_p1_valid;
    old_p1_data = fifo_p1_data;

    @(posedge clock);
    #1;

    if(pop_accepted) begin
      fifo_head = (fifo_head + 1) % 8;
      fifo_count--;
    end
    if(old_p1_valid) begin
      fifo_model[fifo_tail] = old_p1_data;
      fifo_tail = (fifo_tail + 1) % 8;
      fifo_count++;
    end

    model_empty = fifo_count == 0;
    model_alfull = old_count >= 5;
    model_full =
      (old_count == 8 && !pop_accepted) ||
      (old_count == 7 && old_p1_valid && !pop_accepted);

    fifo_p1_valid = fifo_p0_valid;
    fifo_p1_data = fifo_p0_data;
    fifo_p0_valid = push_accepted;
    fifo_p0_data = data_value;

    check_fifo_flags("post-edge");
    vectors++;
  endtask

  task automatic reset_fifo_model;
    fifo_head = 0;
    fifo_tail = 0;
    fifo_count = 0;
    fifo_p0_valid = 0;
    fifo_p1_valid = 0;
    fifo_p0_data = 0;
    fifo_p1_data = 0;
    model_empty = 1;
    model_full = 0;
    model_alfull = 0;
  endtask

  task automatic assert_fifo_reset(input string phase);
    fifo_rstn = 0;
    #1;
    reset_fifo_model();
    check_fifo_flags(phase);
    expect_word("fifo-depth8", {phase, "-data"}, fifo_data_out, 0);
  endtask

  task automatic check_fifo1_flags(input string behavior);
    expect_word("fifo-depth1", {behavior, "-empty"}, fifo1_empty, model1_empty);
    expect_word("fifo-depth1", {behavior, "-valid"}, fifo1_valid, !model1_empty);
    expect_word("fifo-depth1", {behavior, "-full"}, fifo1_full, model1_full);
    expect_word(
      "fifo-depth1",
      {behavior, "-almost-full"},
      fifo1_alfull,
      model1_alfull
    );
  endtask

  task automatic fifo1_step(
      input logic push_value,
      input logic pop_value,
      input logic data_value
  );
    int old_count;
    bit pop_accepted;
    bit push_accepted;
    bit old_p1_valid;
    logic old_p1_data;

    @(negedge clock);
    fifo1_push = push_value;
    fifo1_pop = pop_value;
    fifo1_data_in = data_value;
    #1;
    check_fifo1_flags("pre-edge");
    if(pop_value && !model1_empty)
      expect_word("fifo-depth1", "queue-order", fifo1_data_out, fifo1_model);
    else
      expect_word("fifo-depth1", "blocked-pop-output", fifo1_data_out, 0);

    old_count = fifo1_count;
    pop_accepted = pop_value && !model1_empty;
    push_accepted = push_value && !model1_full;
    old_p1_valid = fifo1_p1_valid;
    old_p1_data = fifo1_p1_data;

    @(posedge clock);
    #1;
    if(pop_accepted)
      fifo1_count--;
    if(old_p1_valid) begin
      fifo1_model = old_p1_data;
      fifo1_count++;
    end

    model1_empty = fifo1_count == 0;
    model1_alfull = old_count >= 1;
    model1_full =
      (old_count == 1 && !pop_accepted) ||
      (old_count == 0 && old_p1_valid && !pop_accepted);
    fifo1_p1_valid = fifo1_p0_valid;
    fifo1_p1_data = fifo1_p0_data;
    fifo1_p0_valid = push_accepted;
    fifo1_p0_data = data_value;

    check_fifo1_flags("post-edge");
    vectors++;
  endtask

  task automatic reset_fifo1_model;
    fifo1_model = 0;
    fifo1_count = 0;
    fifo1_p0_valid = 0;
    fifo1_p1_valid = 0;
    fifo1_p0_data = 0;
    fifo1_p1_data = 0;
    model1_empty = 1;
    model1_full = 0;
    model1_alfull = 0;
  endtask

  task automatic assert_fifo1_reset(input string phase);
    fifo1_rstn = 0;
    #1;
    reset_fifo1_model();
    check_fifo1_flags(phase);
    expect_word("fifo-depth1", {phase, "-data"}, fifo1_data_out, 0);
  endtask

  task automatic check_fifo5_flags(input string behavior);
    expect_word("fifo-depth5", {behavior, "-empty"}, fifo5_empty, model5_empty);
    expect_word("fifo-depth5", {behavior, "-valid"}, fifo5_valid, !model5_empty);
    expect_word("fifo-depth5", {behavior, "-full"}, fifo5_full, model5_full);
    expect_word(
      "fifo-depth5",
      {behavior, "-almost-full"},
      fifo5_alfull,
      model5_alfull
    );
  endtask

  task automatic fifo5_step(
      input logic push_value,
      input logic pop_value,
      input logic [7:0] data_value
  );
    int old_count;
    bit pop_accepted;
    bit push_accepted;
    bit old_p1_valid;
    logic [7:0] old_p1_data;

    @(negedge clock);
    fifo5_push = push_value;
    fifo5_pop = pop_value;
    fifo5_data_in = data_value;
    #1;
    check_fifo5_flags("pre-edge");
    if(pop_value && !model5_empty)
      expect_word(
        "fifo-depth5",
        "queue-order",
        fifo5_data_out,
        fifo5_model[fifo5_head]
      );
    else
      expect_word("fifo-depth5", "blocked-pop-output", fifo5_data_out, 0);

    old_count = fifo5_count;
    pop_accepted = pop_value && !model5_empty;
    push_accepted = push_value && !model5_full;
    old_p1_valid = fifo5_p1_valid;
    old_p1_data = fifo5_p1_data;

    @(posedge clock);
    #1;
    if(pop_accepted) begin
      fifo5_head = (fifo5_head + 1) % 5;
      fifo5_count--;
    end
    if(old_p1_valid) begin
      fifo5_model[fifo5_tail] = old_p1_data;
      fifo5_tail = (fifo5_tail + 1) % 5;
      fifo5_count++;
    end

    model5_empty = fifo5_count == 0;
    model5_alfull = old_count >= 2;
    model5_full =
      (old_count == 5 && !pop_accepted) ||
      (old_count == 4 && old_p1_valid && !pop_accepted);
    fifo5_p1_valid = fifo5_p0_valid;
    fifo5_p1_data = fifo5_p0_data;
    fifo5_p0_valid = push_accepted;
    fifo5_p0_data = data_value;

    check_fifo5_flags("post-edge");
    vectors++;
  endtask

  task automatic reset_fifo5_model;
    fifo5_head = 0;
    fifo5_tail = 0;
    fifo5_count = 0;
    fifo5_p0_valid = 0;
    fifo5_p1_valid = 0;
    fifo5_p0_data = 0;
    fifo5_p1_data = 0;
    model5_empty = 1;
    model5_full = 0;
    model5_alfull = 0;
  endtask

  task automatic assert_fifo5_reset(input string phase);
    fifo5_rstn = 0;
    #1;
    reset_fifo5_model();
    check_fifo5_flags(phase);
    expect_word("fifo-depth5", {phase, "-data"}, fifo5_data_out, 0);
  endtask

  initial begin
    logic [0:31] old_word;

    clock = 0;
    r1_we = 0;
    r1_wr_addr = 0;
    r1_data_in = 0;
    r1_rd_addr = 0;
    r3_we = 0;
    r3_wr_addr = 0;
    r3_data_in = 0;
    r3_rd_addr = 0;
    r2_we = 0;
    r2_wr_addr = 0;
    r2_data_in = 0;
    r2_rd_addr1 = 0;
    r2_rd_addr2 = 0;
    mw_we = 0;
    mw_wr_addr = 0;
    mw_data_in = 0;
    mw_rd_addr = 0;
    mr_we = 0;
    mr_wr_addr = 0;
    mr_data_in = 0;
    mr_rd_addr = 0;
    me_we = 0;
    me_wr_addr = 0;
    me_data_in = 0;
    me_rd_addr = 0;
    fifo_rstn = 0;
    fifo_push = 0;
    fifo_pop = 0;
    fifo_data_in = 0;
    fifo1_rstn = 0;
    fifo1_push = 0;
    fifo1_pop = 0;
    fifo1_data_in = 0;
    fifo5_rstn = 0;
    fifo5_push = 0;
    fifo5_pop = 0;
    fifo5_data_in = 0;
    r1_model = 0;
    for(int address = 0; address < 3; address++) begin
      r3_model[address] = 0;
      me_model[address] = 0;
    end
    for(int address = 0; address < 5; address++)
      r2_model[address] = 0;
    reset_fifo_model();
    reset_fifo1_model();
    reset_fifo5_model();

    r1_cycle(1, 1, 0);
    r1_cycle(1, 0, 1);
    r1_cycle(0, 0, 0);
    functional_bins[0] = 1;

    for(int address = 0; address < 3; address++)
      r3_cycle(0, 0, 0, address, 0);
    functional_bins[2] = 1;
    for(int address = 0; address < 3; address++) begin
      r3_cycle(1, address, 8'hff, address, r3_model[address]);
      r3_cycle(1, address, 8'h00, address, r3_model[address]);
      r3_cycle(1, address, 8'h31 + address, address, r3_model[address]);
    end
    for(int address = 0; address < 3; address++)
      r3_cycle(0, 0, 0, address, r3_model[address]);
    functional_bins[1] = 1;
    functional_bins[3] = 1;
    r3_cycle(1, 1, 8'he7, 1, r3_model[1]);
    r3_cycle(0, 0, 0, 1, r3_model[1]);
    functional_bins[4] = 1;
    r3_cycle(0, 2, 8'haa, 2, r3_model[2]);
    r3_cycle(0, 0, 0, 2, r3_model[2]);
    functional_bins[5] = 1;

    for(int address = 0; address < 5; address++) begin
      r2_cycle(
        1,
        address,
        17'h1ffff,
        address,
        (address + 1) % 5,
        r2_model[address],
        r2_model[(address + 1) % 5]
      );
      r2_cycle(
        0,
        0,
        0,
        address,
        address,
        r2_model[address],
        r2_model[address]
      );
      r2_cycle(
        1,
        address,
        17'h00000,
        address,
        (address + 1) % 5,
        r2_model[address],
        r2_model[(address + 1) % 5]
      );
      r2_cycle(
        1,
        address,
        17'h10101 + address,
        address,
        (address + 1) % 5,
        r2_model[address],
        r2_model[(address + 1) % 5]
      );
    end
    for(int address = 0; address < 5; address++)
      r2_cycle(
        0,
        0,
        0,
        address,
        4 - address,
        r2_model[address],
        r2_model[4 - address]
      );
    functional_bins[6] = 1;
    functional_bins[7] = 1;
    for(int address = 0; address < 5; address++)
      r2_cycle(
        0,
        0,
        0,
        address,
        address,
        r2_model[address],
        r2_model[address]
      );
    functional_bins[8] = 1;
    r2_cycle(1, 2, 17'h15555, 2, 2, r2_model[2], r2_model[2]);
    r2_cycle(0, 0, 0, 2, 2, r2_model[2], r2_model[2]);
    functional_bins[9] = 1;

    for(int address = 0; address < 3; address++)
      mw_cycle(1, address, 32'h00000000, 0, address != 0, mw_model[0]);
    for(int address = 0; address < 3; address++)
      mw_cycle(1, address, 32'hffffffff, 0, 1, mw_model[0]);
    mw_cycle(1, 0, 32'h10203040, 0, 1, mw_model[0]);
    mw_cycle(1, 1, 32'h50607080, 4, 1, mw_model[4]);
    mw_cycle(1, 2, 32'h90a0b0c0, 8, 1, mw_model[8]);
    for(int address = 0; address < 12; address++)
      mw_cycle(0, 0, 0, address, 1, mw_model[address]);
    functional_bins[10] = 1;
    functional_bins[13] = 1;
    mw_cycle(1, 1, 32'hdeadbeef, 5, 1, mw_model[5]);
    for(int address = 4; address < 8; address++)
      mw_cycle(0, 0, 0, address, 1, mw_model[address]);
    functional_bins[16] = 1;

    for(int address = 0; address < 12; address++)
      mr_cycle(1, address, 8'h00, 0, address >= 4, mr_word(0));
    for(int address = 0; address < 12; address++)
      mr_cycle(1, address, 8'hff, 0, 1, mr_word(0));
    for(int address = 0; address < 12; address++)
      mr_cycle(1, address, 8'h20 + address, address / 4, 1, mr_word(address / 4));
    for(int address = 0; address < 3; address++)
      mr_cycle(0, 0, 0, address, 1, mr_word(address));
    functional_bins[11] = 1;
    functional_bins[14] = 1;
    old_word = mr_word(1);
    mr_cycle(1, 5, 8'haa, 1, 1, old_word);
    mr_cycle(0, 0, 0, 1, 1, mr_word(1));
    functional_bins[17] = 1;

    for(int address = 0; address < 3; address++)
      me_cycle(1, address, 8'h00, 0, address != 0, me_model[0]);
    for(int address = 0; address < 3; address++)
      me_cycle(1, address, 8'hff, 0, 1, me_model[0]);
    for(int address = 0; address < 3; address++)
      me_cycle(1, address, 8'h40 + address, address, 1, me_model[address]);
    for(int address = 0; address < 3; address++)
      me_cycle(0, 0, 0, address, 1, me_model[address]);
    me_cycle(1, 1, 8'h5a, 1, 1, me_model[1]);
    me_cycle(0, 0, 0, 1, 1, me_model[1]);
    functional_bins[12] = 1;
    functional_bins[15] = 1;

    @(posedge clock);
    #2 assert_fifo_reset("async-reset-high-phase");
    functional_bins[26] = 1;
    @(negedge clock);
    fifo_rstn = 1;

    repeat(2)
      fifo_step(0, 1, 0);
    functional_bins[18] = 1;
    functional_bins[23] = 1;

    for(int index = 0; index < 8; index++)
      fifo_step(1, 0, 8'hff);
    repeat(2)
      fifo_step(0, 0, 0);
    if(fifo_count != 8 || !model_full || !model_alfull)
      $fatal(1, "FIFO model did not reach full state");
    functional_bins[19] = 1;
    functional_bins[20] = 1;

    fifo_step(1, 0, 8'hee);
    fifo_step(0, 0, 0);
    fifo_step(0, 0, 0);
    functional_bins[24] = 1;
    while(fifo_count > 0)
      fifo_step(0, 1, 0);
    functional_bins[25] = 1;

    for(int index = 0; index < 8; index++)
      fifo_step(1, 0, 8'h00);
    repeat(2)
      fifo_step(0, 0, 0);
    while(fifo_count > 0)
      fifo_step(0, 1, 0);
    functional_bins[21] = 1;

    for(int index = 0; index < 4; index++)
      fifo_step(1, 0, 8'h60 + index);
    repeat(2)
      fifo_step(0, 0, 0);
    for(int index = 0; index < 6; index++)
      fifo_step(1, 1, 8'ha0 + index);
    repeat(2)
      fifo_step(0, 0, 0);
    while(fifo_count > 0)
      fifo_step(0, 1, 0);
    functional_bins[22] = 1;

    fifo_step(1, 0, 8'h12);
    fifo_step(1, 0, 8'h34);
    @(posedge clock);
    #2 assert_fifo_reset("async-reset-with-pending-pushes");
    @(negedge clock);
    fifo_rstn = 1;
    fifo_push = 0;
    fifo_pop = 0;
    fifo_step(0, 0, 0);

    @(posedge clock);
    #2 assert_fifo1_reset("async-reset-high-phase");
    expect_word(
      "fifo-depth1",
      "default-address-width",
      $bits(fifo_depth1.wr_addr),
      1
    );
    functional_bins[27] = 1;
    fifo1_rstn = 1;
    fifo1_step(0, 1, 0);
    fifo1_step(1, 0, 1);
    repeat(3)
      fifo1_step(0, 0, 0);
    if(fifo1_count != 1 || !model1_full || !model1_alfull)
      $fatal(1, "depth-one FIFO model did not reach full state");
    fifo1_step(1, 0, 0);
    repeat(2)
      fifo1_step(0, 0, 0);
    fifo1_step(0, 1, 0);
    fifo1_step(1, 0, 0);
    repeat(2)
      fifo1_step(0, 0, 0);
    fifo1_step(0, 1, 0);
    functional_bins[28] = 1;
    fifo1_step(1, 1, 1);
    repeat(2)
      fifo1_step(0, 0, 0);
    fifo1_step(0, 1, 0);
    functional_bins[29] = 1;

    @(posedge clock);
    #2 assert_fifo5_reset("async-reset-high-phase");
    fifo5_rstn = 1;
    fifo5_step(0, 1, 0);
    for(int index = 0; index < 5; index++)
      fifo5_step(1, 0, 8'hff);
    repeat(2)
      fifo5_step(0, 0, 0);
    if(fifo5_count != 5 || !model5_full || !model5_alfull)
      $fatal(1, "depth-five FIFO model did not reach full state");
    fifo5_step(1, 0, 8'hee);
    repeat(2)
      fifo5_step(0, 0, 0);
    while(fifo5_count > 0)
      fifo5_step(0, 1, 0);
    functional_bins[30] = 1;
    functional_bins[31] = 1;

    for(int index = 0; index < 5; index++)
      fifo5_step(1, 0, 8'h00);
    repeat(2)
      fifo5_step(0, 0, 0);
    while(fifo5_count > 0)
      fifo5_step(0, 1, 0);
    for(int index = 0; index < 3; index++)
      fifo5_step(1, 0, 8'h30 + index);
    repeat(2)
      fifo5_step(0, 0, 0);
    for(int index = 0; index < 5; index++)
      fifo5_step(1, 1, 8'ha0 + index);
    repeat(2)
      fifo5_step(0, 0, 0);
    while(fifo5_count > 0)
      fifo5_step(0, 1, 0);
    functional_bins[32] = 1;

    for(int bin_index = 0; bin_index < 33; bin_index++) begin
      if(!functional_bins[bin_index])
        $fatal(1, "missing storage functional bin %0d", bin_index);
      bins_hit++;
    end

    $display(
      "PASS storage_unit vectors=%0d checks=%0d bins=%0d",
      vectors,
      checks,
      bins_hit
    );
    $finish;
  end

endmodule
