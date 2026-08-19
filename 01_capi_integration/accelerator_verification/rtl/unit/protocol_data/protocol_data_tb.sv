// Top level of the CAPI-Precis protocol data / register / lifecycle unit suite.
// Every family testbench owns one DUT set, drives its own stimulus and reports
// its own evidence line. This top only sequences the shared clock and folds the
// per family evidence into a single suite result.

module protocol_data_tb;

  localparam int unsigned FAMILY_COUNT   = 6      ;
  localparam int unsigned WATCHDOG_UNITS = 4000000;

  logic clock;

  logic        finished [0:FAMILY_COUNT-1];
  int unsigned checks   [0:FAMILY_COUNT-1];
  int unsigned bin_hits     [0:FAMILY_COUNT-1];
  int unsigned stalls   [0:FAMILY_COUNT-1];
  string       family_name [0:FAMILY_COUNT-1];

  int unsigned total_checks;
  int unsigned total_bins  ;
  int unsigned total_stalls;

  initial clock = 1'b0;
  always #5 clock = ~clock;

  read_data_control_tb read_data_family (
    .clock   (clock      ),
    .finished(finished[0]),
    .checks  (checks[0]  ),
    .bin_hits    (bin_hits[0]    ),
    .stalls  (stalls[0]  )
  );

  write_data_control_tb write_data_family (
    .clock   (clock      ),
    .finished(finished[1]),
    .checks  (checks[1]  ),
    .bin_hits    (bin_hits[1]    ),
    .stalls  (stalls[1]  )
  );

  wed_control_tb wed_family (
    .clock   (clock      ),
    .finished(finished[2]),
    .checks  (checks[2]  ),
    .bin_hits    (bin_hits[2]    ),
    .stalls  (stalls[2]  )
  );

  mmio_tb mmio_family (
    .clock   (clock      ),
    .finished(finished[3]),
    .checks  (checks[3]  ),
    .bin_hits    (bin_hits[3]    ),
    .stalls  (stalls[3]  )
  );

  job_tb job_family (
    .clock   (clock      ),
    .finished(finished[4]),
    .checks  (checks[4]  ),
    .bin_hits    (bin_hits[4]    ),
    .stalls  (stalls[4]  )
  );

  completion_error_tb completion_error_family (
    .clock   (clock      ),
    .finished(finished[5]),
    .checks  (checks[5]  ),
    .bin_hits    (bin_hits[5]    ),
    .stalls  (stalls[5]  )
  );

  initial begin
    total_checks = 0;
    total_bins   = 0;
    total_stalls = 0;

    family_name[0] = "read-data";
    family_name[1] = "write-data";
    family_name[2] = "wed";
    family_name[3] = "mmio";
    family_name[4] = "job";
    family_name[5] = "completion-error";

    wait (
      finished[0] && finished[1] && finished[2] &&
      finished[3] && finished[4] && finished[5]
    );

    for(int unsigned family = 0; family < FAMILY_COUNT; family++) begin
      $display(
        "EVIDENCE family=%s checks=%0d bins=%0d stalls=%0d",
        family_name[family],
        checks[family],
        bin_hits[family],
        stalls[family]
      );
      total_checks += checks[family];
      total_bins   += bin_hits[family];
      total_stalls += stalls[family];
    end

    $display(
      "PASS protocol_data families=%0d checks=%0d bins=%0d stalls=%0d",
      FAMILY_COUNT,
      total_checks,
      total_bins,
      total_stalls
    );
    $finish;
  end

  initial begin
    #WATCHDOG_UNITS;
    $error("protocol_data watchdog expired before every family finished");
    $fatal(1);
  end

endmodule
