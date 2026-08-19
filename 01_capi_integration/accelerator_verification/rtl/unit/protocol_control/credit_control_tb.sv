module credit_control_tb;

  import CREDIT_PKG::*;

  logic clock;
  logic rstn_in;
  logic enabled_in;
  CreditInterfaceInput credit_in;
  CreditInterfaceOutput credit_out;

  int unsigned checks;
  int unsigned bins_hit;
  logic [0:7] ledger;
  bit control_bins [0:3];
  bit zero_initial_bin;
  bit zero_starvation_bin;
  bit release_bin;
  bit same_cycle_bin;
  bit overflow_bin;
  bit negative_release_bin;
  bit negative_same_cycle_bin;

  credit_control dut (
    .clock(clock),
    .rstn_in(rstn_in),
    .enabled_in(enabled_in),
    .credit_in(credit_in),
    .credit_out(credit_out)
  );

  always #5 clock = ~clock;

  task automatic tick;
    @(posedge clock);
    #1;
  endtask

  task automatic check_ledger(input string phase);
    checks++;
    if(credit_out.credits !== ledger)
      $fatal(
        1,
        "credit ledger mismatch phase=%s expected=%0d actual=%0d",
        phase,
        ledger,
        credit_out.credits
      );
  endtask

  task automatic reset_with_room(input logic [0:7] room);
    rstn_in = 0;
    enabled_in = 0;
    credit_in = '0;
    ledger = 0;
    repeat(3) tick();
    rstn_in = 1;
    enabled_in = 1;
    credit_in.room = room;
    repeat(3) tick();
    ledger = room;
    check_ledger("initial-room");
  endtask

  task automatic apply_credit_event(
      input logic request,
      input logic response,
      input logic [0:8] returned,
      input string phase
  );
    logic signed [8:0] signed_returned;
    logic signed [9:0] next_value;

    credit_in.valid_request = request;
    credit_in.valid_response = response;
    credit_in.response_credits = returned;
    signed_returned = signed'(returned);
    next_value = $signed({1'b0, ledger});
    if(response)
      next_value += signed_returned;
    if(request)
      next_value -= 1;
    ledger = next_value[7:0];
    tick();
    check_ledger(phase);
    control_bins[{request, response}] = 1;
    credit_in.valid_request = 0;
    credit_in.valid_response = 0;
    credit_in.response_credits = 0;
  endtask

  initial begin
    clock = 0;
    rstn_in = 0;
    enabled_in = 0;
    credit_in = '0;
    checks = 0;
    bins_hit = 0;

    reset_with_room(8'd0);
    zero_initial_bin = 1;

    for(int stall_cycle = 0; stall_cycle < 3; stall_cycle++) begin
      tick();
      check_ledger("zero-credit-starvation");
    end
    zero_starvation_bin = 1;

    apply_credit_event(0, 1, 9'b0_00000001, "release-from-zero");
    release_bin = 1;
    apply_credit_event(1, 0, 9'b0, "issue-after-release");
    apply_credit_event(1, 1, 9'b0_00000001, "issue-return-same-cycle");
    same_cycle_bin = 1;
    apply_credit_event(0, 0, 9'b0, "idle");

    reset_with_room(8'hff);
    apply_credit_event(0, 1, 9'b0_00000001, "positive-overflow");
    overflow_bin = 1;

    reset_with_room(8'd3);
    apply_credit_event(0, 1, 9'b1_11111111, "negative-credit-release");
    negative_release_bin = 1;
    apply_credit_event(
      1,
      1,
      9'b1_11111111,
      "negative-credit-and-issue-same-cycle"
    );
    negative_same_cycle_bin = 1;

    for(int index = 0; index < 4; index++) begin
      if(!control_bins[index])
        $fatal(1, "credit ledger mismatch missing control bin=%0d", index);
      bins_hit++;
    end
    if(
      !zero_initial_bin ||
      !zero_starvation_bin ||
      !release_bin ||
      !same_cycle_bin ||
      !overflow_bin ||
      !negative_release_bin ||
      !negative_same_cycle_bin
    )
      $fatal(1, "credit ledger mismatch missing boundary bin");
    bins_hit += 7;

    $display(
      "PASS protocol_control dut=credit_control checks=%0d bins=%0d/11",
      checks,
      bins_hit
    );
    $finish;
  end

endmodule
