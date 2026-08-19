module parity_tb;

  logic         odd;
  logic [  0:0] data_1;
  logic [  0:7] data_8;
  logic [ 0:16] data_17;
  logic [ 0:63] data_64;
  logic [ 0:64] data_65;
  logic [0:127] data_dw2;
  logic [0:255] data_dw4;
  logic         par_1;
  logic         par_8;
  logic         par_17;
  logic         par_64;
  logic         par_65;
  logic [  0:1] par_dw2;
  logic [  0:3] par_dw4;

  int unsigned vectors;
  int unsigned bins_hit;
  bit parity_modes [0:1];
  bit data_classes [0:4][0:1];
  bit dw2_lane_classes [0:1][0:1];
  bit dw4_lane_classes [0:3][0:1];
  bit boundary_zero;
  bit boundary_ones;
  bit boundary_alternating_10;
  bit boundary_alternating_01;

  parity #(.BITS(1)) parity_1 (
    .data(data_1),
    .odd (odd   ),
    .par (par_1 )
  );

  parity #(.BITS(8)) parity_8 (
    .data(data_8),
    .odd (odd   ),
    .par (par_8 )
  );

  parity #(.BITS(17)) parity_17 (
    .data(data_17),
    .odd (odd    ),
    .par (par_17 )
  );

  parity #(.BITS(64)) parity_64 (
    .data(data_64),
    .odd (odd    ),
    .par (par_64 )
  );

  parity #(.BITS(65)) parity_65 (
    .data(data_65),
    .odd (odd    ),
    .par (par_65 )
  );

  dw_parity #(.DOUBLE_WORDS(2)) parity_dw2 (
    .data(data_dw2),
    .odd (odd     ),
    .par (par_dw2 )
  );

  dw_parity #(.DOUBLE_WORDS(4)) parity_dw4 (
    .data(data_dw4),
    .odd (odd     ),
    .par (par_dw4 )
  );

  function automatic logic oracle_bit(input int unsigned ones, input logic mode);
    oracle_bit = logic'((ones + mode) % 2);
  endfunction

  task automatic fail(
      input string instance_name,
      input int unsigned expected,
      input int unsigned actual
  );
    $error(
      "parity mismatch instance=%s vector=%0d expected=%0d actual=%0d",
      instance_name,
      vectors,
      expected,
      actual
    );
    $fatal(1);
  endtask

  task automatic check_current;
    logic expected;

    #1;
    parity_modes[odd] = 1;

    expected = oracle_bit($countones(data_1), odd);
    data_classes[0][$countones(data_1) % 2] = 1;
    if(par_1 !== expected)
      fail("parity-bits-1", expected, par_1);

    expected = oracle_bit($countones(data_8), odd);
    data_classes[1][$countones(data_8) % 2] = 1;
    if(par_8 !== expected)
      fail("parity-bits-8", expected, par_8);

    expected = oracle_bit($countones(data_17), odd);
    data_classes[2][$countones(data_17) % 2] = 1;
    if(par_17 !== expected)
      fail("parity-bits-17", expected, par_17);

    expected = oracle_bit($countones(data_64), odd);
    data_classes[3][$countones(data_64) % 2] = 1;
    if(par_64 !== expected)
      fail("parity-bits-64", expected, par_64);

    expected = oracle_bit($countones(data_65), odd);
    data_classes[4][$countones(data_65) % 2] = 1;
    if(par_65 !== expected)
      fail("parity-bits-65", expected, par_65);

    for(int lane = 0; lane < 2; lane++) begin
      expected = oracle_bit($countones(data_dw2[64*lane +: 64]), odd);
      dw2_lane_classes[lane][$countones(data_dw2[64*lane +: 64]) % 2] = 1;
      if(par_dw2[lane] !== expected)
        fail($sformatf("dw-parity-2-lane-%0d", lane), expected, par_dw2[lane]);
    end

    for(int lane = 0; lane < 4; lane++) begin
      expected = oracle_bit($countones(data_dw4[64*lane +: 64]), odd);
      dw4_lane_classes[lane][$countones(data_dw4[64*lane +: 64]) % 2] = 1;
      if(par_dw4[lane] !== expected)
        fail($sformatf("dw-parity-4-lane-%0d", lane), expected, par_dw4[lane]);
    end

    boundary_zero |= !(|data_dw4);
    boundary_ones |= &data_dw4;
    boundary_alternating_10 |= data_dw4 == {128{2'b10}};
    boundary_alternating_01 |= data_dw4 == {128{2'b01}};
    vectors++;
  endtask

  task automatic drive_wide(input logic [0:255] value);
    data_1   = value[0:0];
    data_8   = value[0:7];
    data_17  = value[0:16];
    data_64  = value[0:63];
    data_65  = value[0:64];
    data_dw2 = value[0:127];
    data_dw4 = value;
  endtask

  function automatic logic [0:255] next_pattern(input logic [0:255] value);
    logic feedback;

    feedback = value[0] ^ value[2] ^ value[5] ^ value[10];
    next_pattern = {value[1:255], feedback};
  endfunction

  initial begin
    logic [0:255] pattern;

    odd = 0;
    drive_wide('0);
    check_current();
    odd = 1;
    check_current();

    odd = 0;
    drive_wide('1);
    check_current();
    odd = 1;
    check_current();

    odd = 0;
    drive_wide({128{2'b10}});
    check_current();
    odd = 1;
    check_current();

    odd = 0;
    drive_wide({128{2'b01}});
    check_current();
    odd = 1;
    check_current();

    for(int value = 0; value < 256; value++) begin
      drive_wide('0);
      data_8 = value[7:0];
      data_1 = value[0];
      odd = 0;
      check_current();
      odd = 1;
      check_current();
    end

    pattern = 256'h1;
    for(int sample = 0; sample < 1024; sample++) begin
      pattern = next_pattern(pattern);
      drive_wide(pattern);
      odd = sample[0];
      check_current();
    end

    for(int mode = 0; mode < 2; mode++) begin
      if(!parity_modes[mode])
        $fatal(1, "missing parity mode bin %0d", mode);
      bins_hit++;
    end
    for(int instance_index = 0; instance_index < 5; instance_index++) begin
      for(int parity_class = 0; parity_class < 2; parity_class++) begin
        if(!data_classes[instance_index][parity_class])
          $fatal(
            1,
            "missing data class bin instance=%0d parity=%0d",
            instance_index,
            parity_class
          );
        bins_hit++;
      end
    end
    for(int lane = 0; lane < 2; lane++) begin
      for(int parity_class = 0; parity_class < 2; parity_class++) begin
        if(!dw2_lane_classes[lane][parity_class])
          $fatal(1, "missing DW2 lane bin lane=%0d parity=%0d", lane, parity_class);
        bins_hit++;
      end
    end
    for(int lane = 0; lane < 4; lane++) begin
      for(int parity_class = 0; parity_class < 2; parity_class++) begin
        if(!dw4_lane_classes[lane][parity_class])
          $fatal(1, "missing DW4 lane bin lane=%0d parity=%0d", lane, parity_class);
        bins_hit++;
      end
    end
    if(
      !boundary_zero ||
      !boundary_ones ||
      !boundary_alternating_10 ||
      !boundary_alternating_01
    )
      $fatal(1, "missing boundary bins");
    bins_hit += 4;

    $display("PASS parity_unit vectors=%0d bins=%0d", vectors, bins_hit);
    $finish;
  end

endmodule
