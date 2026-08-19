`timescale 1ns/1ps

module reset_tb;

  logic clock;
  logic clock_run;

  logic f1_enable;
  logic f1_raw;
  logic f1_filtered;
  logic f2_enable;
  logic f2_raw;
  logic f2_filtered;
  logic f3_enable;
  logic f3_raw;
  logic f3_filtered;
  logic f5_enable;
  logic f5_raw;
  logic f5_filtered;

  logic [0:0] ext1;
  logic [0:2] ext3;
  logic       control1_rstn;
  logic       control3_rstn;

  int unsigned checks;
  int unsigned bins_hit;
  bit functional_bins [0:17];

  reset_filter #(.PULSE_HOLD(1)) filter1 (
    .enable        (f1_enable  ),
    .rstn_raw      (f1_raw     ),
    .clock         (clock      ),
    .rstn_filtered (f1_filtered)
  );

  reset_filter #(.PULSE_HOLD(2)) filter2 (
    .enable        (f2_enable  ),
    .rstn_raw      (f2_raw     ),
    .clock         (clock      ),
    .rstn_filtered (f2_filtered)
  );

  reset_filter #(.PULSE_HOLD(3)) filter3 (
    .enable        (f3_enable  ),
    .rstn_raw      (f3_raw     ),
    .clock         (clock      ),
    .rstn_filtered (f3_filtered)
  );

  reset_filter #(.PULSE_HOLD(5)) filter5 (
    .enable        (f5_enable  ),
    .rstn_raw      (f5_raw     ),
    .clock         (clock      ),
    .rstn_filtered (f5_filtered)
  );

  reset_control #(.NUM_EXTERNAL_RESETS(1)) control1 (
    .clock         (clock        ),
    .external_rstn (ext1         ),
    .rstn          (control1_rstn)
  );

  reset_control #(.NUM_EXTERNAL_RESETS(3)) control3 (
    .clock         (clock        ),
    .external_rstn (ext3         ),
    .rstn          (control3_rstn)
  );

  always #5
    if(clock_run)
      clock = ~clock;

  task automatic expect_reset(
      input string instance_name,
      input string phase,
      input logic actual,
      input logic expected
  );
    checks++;
    if(actual !== expected) begin
      $error(
        "reset mismatch instance=%s phase=%s check=%0d expected=%0b actual=%0b",
        instance_name,
        phase,
        checks,
        expected,
        actual
      );
      $fatal(1);
    end
  endtask

  task automatic release_f1;
    f1_enable = 1;
    f1_raw = 1;
    @(posedge clock);
    #1 expect_reset("filter-P1", "release-edge-1", f1_filtered, 1);
    functional_bins[16] = 1;
  endtask

  task automatic release_f2;
    f2_enable = 1;
    f2_raw = 1;
    @(posedge clock);
    #1 expect_reset("filter-P2", "release-edge-1", f2_filtered, 0);
    @(posedge clock);
    #1 expect_reset("filter-P2", "release-edge-2", f2_filtered, 1);
    functional_bins[0] = 1;
  endtask

  task automatic release_f3;
    f3_enable = 1;
    f3_raw = 1;
    for(int edge_index = 1; edge_index <= 3; edge_index++) begin
      @(posedge clock);
      #1 expect_reset(
        "filter-P3",
        $sformatf("release-edge-%0d", edge_index),
        f3_filtered,
        edge_index == 3
      );
    end
    functional_bins[1] = 1;
  endtask

  task automatic release_f5;
    f5_enable = 1;
    f5_raw = 1;
    for(int edge_index = 1; edge_index <= 5; edge_index++) begin
      @(posedge clock);
      #1 expect_reset(
        "filter-P5",
        $sformatf("release-edge-%0d", edge_index),
        f5_filtered,
        edge_index == 5
      );
    end
    functional_bins[2] = 1;
  endtask

  task automatic release_control1;
    ext1 = '1;
    for(int edge_index = 1; edge_index <= 4; edge_index++) begin
      @(posedge clock);
      #1 expect_reset(
        "control-N1",
        $sformatf("release-edge-%0d", edge_index),
        control1_rstn,
        edge_index == 4
      );
    end
    functional_bins[7] = 1;
    functional_bins[13] = 1;
  endtask

  task automatic release_control3;
    ext3 = '1;
    for(int edge_index = 1; edge_index <= 4; edge_index++) begin
      @(posedge clock);
      #1 expect_reset(
        "control-N3",
        $sformatf("release-edge-%0d", edge_index),
        control3_rstn,
        edge_index == 4
      );
    end
    functional_bins[8] = 1;
    functional_bins[13] = 1;
  endtask

  initial begin
    clock = 0;
    clock_run = 1;
    f1_enable = 0;
    f1_raw = 0;
    f2_enable = 0;
    f2_raw = 0;
    f3_enable = 0;
    f3_raw = 0;
    f5_enable = 0;
    f5_raw = 0;
    ext1 = '0;
    ext3 = '0;

    #1;
    expect_reset("filter-P1", "initial-assert", f1_filtered, 0);
    expect_reset("filter-P2", "initial-assert", f2_filtered, 0);
    expect_reset("filter-P3", "initial-assert", f3_filtered, 0);
    expect_reset("filter-P5", "initial-assert", f5_filtered, 0);
    expect_reset("control-N1", "initial-assert", control1_rstn, 0);
    expect_reset("control-N3", "initial-assert", control3_rstn, 0);

    f1_raw = 1;
    repeat(2) begin
      @(posedge clock);
      #1 expect_reset("filter-P1", "enable-blocked", f1_filtered, 0);
    end
    release_f1();
    @(posedge clock);
    #2 f1_raw = 0;
    #1 expect_reset("filter-P1", "async-assert-high-phase", f1_filtered, 0);
    functional_bins[17] = 1;
    release_f1();

    release_f2();
    @(negedge clock);
    #1 f2_raw = 0;
    #1 expect_reset("filter-P2", "async-assert-low-phase", f2_filtered, 0);
    functional_bins[4] = 1;
    release_f2();

    @(posedge clock);
    #2 f2_raw = 0;
    #1 expect_reset("filter-P2", "async-assert-high-phase", f2_filtered, 0);
    functional_bins[5] = 1;
    release_f2();

    @(negedge clock);
    #1 clock_run = 0;
    f2_raw = 0;
    #12 expect_reset("filter-P2", "async-assert-clock-stopped", f2_filtered, 0);
    functional_bins[14] = 1;
    clock_run = 1;
    release_f2();

    f3_raw = 0;
    f3_enable = 0;
    #1 expect_reset("filter-P3", "enable-test-assert", f3_filtered, 0);
    f3_raw = 1;
    repeat(4) begin
      @(posedge clock);
      #1 expect_reset("filter-P3", "enable-blocked", f3_filtered, 0);
    end
    functional_bins[3] = 1;
    f3_enable = 1;
    for(int edge_index = 1; edge_index <= 3; edge_index++) begin
      @(posedge clock);
      #1 expect_reset(
        "filter-P3",
        "enable-release",
        f3_filtered,
        edge_index == 3
      );
    end
    functional_bins[1] = 1;

    release_f5();
    @(posedge clock);
    #2 f5_raw = 0;
    #1 expect_reset("filter-P5", "repeat-first-assert", f5_filtered, 0);
    f5_raw = 1;
    repeat(2) begin
      @(posedge clock);
      #1 expect_reset("filter-P5", "partial-release", f5_filtered, 0);
    end
    @(negedge clock);
    #1 f5_raw = 0;
    #1 expect_reset("filter-P5", "repeat-second-assert", f5_filtered, 0);
    functional_bins[6] = 1;
    release_f5();

    release_control1();
    @(posedge clock);
    #2 ext1[0] = 0;
    #1 expect_reset("control-N1", "async-assert-high-phase", control1_rstn, 0);
    functional_bins[12] = 1;
    release_control1();
    @(negedge clock);
    #1 ext1[0] = 0;
    #1 expect_reset("control-N1", "async-assert-low-phase", control1_rstn, 0);
    functional_bins[11] = 1;
    release_control1();

    release_control3();
    @(posedge clock);
    #2 ext3[0] = 0;
    #1 expect_reset("control-N3", "overlap-first-assert", control3_rstn, 0);
    ext3[0] = 1;
    @(posedge clock);
    #1 expect_reset("control-N3", "overlap-first-release", control3_rstn, 0);
    ext3[1] = 0;
    repeat(3) begin
      @(posedge clock);
      #1 expect_reset("control-N3", "overlap-held", control3_rstn, 0);
    end
    functional_bins[9] = 1;
    ext3[1] = 1;
    for(int edge_index = 1; edge_index <= 4; edge_index++) begin
      @(posedge clock);
      #1 expect_reset(
        "control-N3",
        "overlap-final-release",
        control3_rstn,
        edge_index == 4
      );
    end

    ext3[2] = 0;
    #1 expect_reset("control-N3", "repeat-first-assert", control3_rstn, 0);
    ext3[2] = 1;
    @(posedge clock);
    #1 expect_reset("control-N3", "repeat-partial-release", control3_rstn, 0);
    ext3[2] = 0;
    #1 expect_reset("control-N3", "repeat-second-assert", control3_rstn, 0);
    ext3[2] = 1;
    for(int edge_index = 1; edge_index <= 4; edge_index++) begin
      @(posedge clock);
      #1 expect_reset(
        "control-N3",
        "repeat-final-release",
        control3_rstn,
        edge_index == 4
      );
    end
    functional_bins[10] = 1;

    ext3 = '0;
    #1 expect_reset("control-N3", "simultaneous-assert", control3_rstn, 0);
    functional_bins[15] = 1;
    release_control3();

    for(int bin_index = 0; bin_index < 18; bin_index++) begin
      if(!functional_bins[bin_index])
        $fatal(1, "missing reset functional bin %0d", bin_index);
      bins_hit++;
    end

    $display("PASS reset_unit checks=%0d bins=%0d", checks, bins_hit);
    $finish;
  end

endmodule
