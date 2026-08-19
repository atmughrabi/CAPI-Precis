// job family: job.sv
//
// Independent model: a cycle accurate job command ledger. The model owns the
// command decode, the reset handshake edge detector that produces the job done
// pulse, the sticky reported error latch and an independent odd parity
// reference for the command and address parity reports.
//
// Sampling contract, cycle c is the interval closed by the posedge that samples
// it:
//   * a job command presented at cycle T is decoded at cycle T+2.
//   * the job done pulse follows the internal reset release edge and publishes
//     the reported error word in the same cycle.
//   * a command or address parity fault is reported at cycle T+5 and stays
//     asserted while the faulty command is held.

import CAPI_PKG::*;

module job_tb (
  input  logic        clock   ,
  output logic        finished,
  output int unsigned checks  ,
  output int unsigned bin_hits,
  output int unsigned stalls
);

  localparam int unsigned HIST_DEPTH = 4;

  // Named bounded stall profiles.
  localparam int unsigned STALL_COMMAND_GAP_SHORT = 1;
  localparam int unsigned STALL_COMMAND_GAP_LONG  = 10;
  localparam int unsigned STALL_RESET_LOW         = 6;
  localparam int unsigned STALL_ERROR_HOLD        = 8;
  localparam int unsigned STALL_DONE_WAIT         = 12;
  localparam int unsigned STALL_PROFILES          = 5;
  localparam int unsigned DRAIN_CYCLES            = 10;

  localparam logic [0:7] COMMAND_INVALID_LOW  = 8'h00;
  localparam logic [0:7] COMMAND_INVALID_HIGH = 8'hFF;

  logic              rstn_in         ;
  JobInterfaceInput  job_in          ;
  logic [0:63]       report_errors   ;
  logic [0:1]        job_errors      ;
  JobInterfaceOutput job_out         ;
  logic              timebase_request;
  logic              parity_enabled  ;
  logic              reset_job       ;

  job dut (
    .clock           (clock           ),
    .rstn_in         (rstn_in         ),
    .job_in          (job_in          ),
    .report_errors   (report_errors   ),
    .job_errors      (job_errors      ),
    .job_out         (job_out         ),
    .timebase_request(timebase_request),
    .parity_enabled  (parity_enabled  ),
    .reset_job       (reset_job       )
  );

////////////////////////////////////////////////////////////////////////////
// independent parity reference
////////////////////////////////////////////////////////////////////////////

  function automatic logic odd_parity_of(input logic [0:63] value);
    odd_parity_of = (($countones(value) % 2) == 0);
  endfunction

////////////////////////////////////////////////////////////////////////////
// model state
////////////////////////////////////////////////////////////////////////////

  typedef struct packed {
    logic        rstn_in       ;
    logic        valid         ;
    logic [0:7]  command       ;
    logic        command_parity;
    logic [0:63] address       ;
    logic        address_parity;
    logic [0:63] report_errors ;
  } snapshot_t;

  snapshot_t hist [0:HIST_DEPTH-1];

  logic        model_start_job     ;
  logic        model_reset_job     ;
  logic        model_prev_rstn     ;
  logic        model_next_rstn     ;
  logic        model_done_job      ;
  logic        model_running       ;
  logic        model_done          ;
  logic [0:63] model_error         ;
  logic [0:7]  model_command       ;
  logic        model_command_parity;
  logic [0:63] model_address       ;
  logic        model_address_parity;
  logic [0:63] model_reported      ;
  logic        model_command_error ;
  logic        model_address_error ;
  logic [0:1]  model_detected      ;
  logic [0:1]  model_job_errors    ;
  int unsigned model_done_source   ;

  logic rstn_previous;
  logic rstn_reg     ;

  int unsigned cycle   ;
  logic        checking;
  string       phase   ;

  bit bin_command   [0:3];
  bit bin_parity    [0:3];
  bit bin_done      [0:2];
  bit bin_error_pub [0:1];
  bit bin_capture   [0:2];
  bit bin_running   [0:2];
  bit bin_gap       [0:2];
  bit bin_reset_job [0:1];
  bit bin_constant  [0:0];
  bit stall_used    [0:4];

////////////////////////////////////////////////////////////////////////////
// diagnostics
////////////////////////////////////////////////////////////////////////////

  task automatic fail(input string reason);
    $error(
      "job mismatch reason=%s phase=%s cycle=%0d",
      reason,
      phase,
      cycle
    );
    $fatal(1);
  endtask

////////////////////////////////////////////////////////////////////////////
// model and checker
////////////////////////////////////////////////////////////////////////////

  always @(posedge clock) begin
    snapshot_t   snapshot            ;
    logic        next_start_job      ;
    logic        next_reset_job      ;
    logic        next_prev_rstn      ;
    logic        next_next_rstn      ;
    logic        next_done_job       ;
    logic        next_running        ;
    logic [0:7]  next_command        ;
    logic        next_command_parity ;
    logic [0:63] next_address        ;
    logic        next_address_parity ;
    logic [0:63] next_reported       ;
    logic        latched_valid       ;
    logic [0:7]  latched_command     ;
    logic        was_running         ;

    for(int position = HIST_DEPTH-1; position > 0; position--)
      hist[position] = hist[position-1];

    snapshot                = '0;
    snapshot.rstn_in        = rstn_in;
    snapshot.valid          = job_in.valid;
    snapshot.command        = job_in.command;
    snapshot.command_parity = job_in.command_parity;
    snapshot.address        = job_in.address;
    snapshot.address_parity = job_in.address_parity;
    snapshot.report_errors  = report_errors;
    hist[0]                 = snapshot;

    rstn_reg      = rstn_in ? rstn_previous : 1'b0;
    rstn_previous = rstn_in;
    cycle++;

    was_running = model_running;
    if(!rstn_reg)
      model_running = 1'b0;

    // -------------------------------------------------------------------
    // compare the outputs published in this cycle
    // -------------------------------------------------------------------
    if(checking) begin
      checks++;
      if(job_out.running !== model_running)
        fail("job running");
      checks++;
      if(job_out.done !== model_done)
        fail("job done pulse");
      checks++;
      if(job_out.error !== model_error)
        fail("job error publication");
      checks++;
      if(job_errors !== model_job_errors)
        fail($sformatf(
          "job parity report expected=%2b actual=%2b",
          model_job_errors,
          job_errors
        ));
      checks++;
      if(reset_job !== model_reset_job)
        fail("job reset request");
      checks++;
      if(job_out.cack !== 1'b0 || job_out.yield !== 1'b0 ||
         timebase_request !== 1'b0 || parity_enabled !== 1'b1)
        fail("dedicated mode constant outputs");
      bin_constant[0] = 1;

      if(model_done)
        bin_error_pub[(|model_error) ? 1 : 0] = 1;
      bin_parity[{model_job_errors[0], model_job_errors[1]}] = 1;
      bin_reset_job[model_reset_job] = 1;
      if(model_running)
        bin_running[1] = 1;
    end

    // -------------------------------------------------------------------
    // advance the independent model
    // -------------------------------------------------------------------
    latched_valid   = hist[1].valid;
    latched_command = hist[1].command;

    next_start_job = model_start_job;
    next_reset_job = model_reset_job;
    next_prev_rstn = model_prev_rstn;
    next_next_rstn = model_next_rstn;
    next_done_job  = model_done_job;

    if(latched_valid) begin
      case (latched_command)
        RESET : begin
          next_start_job = 1'b0;
          next_reset_job = 1'b0;
          next_prev_rstn = 1'b0;
          next_next_rstn = 1'b0;
          next_done_job  = 1'b0;
        end
        START : begin
          next_start_job = 1'b1;
          next_reset_job = 1'b1;
        end
        default : begin
          next_start_job = 1'b0;
          next_reset_job = 1'b1;
          next_prev_rstn = 1'b0;
          next_next_rstn = 1'b0;
        end
      endcase
    end else begin
      next_start_job = 1'b0;
      next_reset_job = 1'b1;
      next_next_rstn = rstn_reg;
      next_prev_rstn = model_next_rstn;
      next_done_job  = (~model_prev_rstn) && model_next_rstn;
    end

    next_running = model_running;
    if(!rstn_reg)
      next_running = 1'b0;
    else if(model_start_job || model_running)
      next_running = 1'b1;

    next_command        = model_command;
    next_command_parity = model_command_parity;
    next_address        = model_address;
    next_address_parity = model_address_parity;
    if(latched_valid) begin
      next_command        = hist[1].command;
      next_command_parity = hist[1].command_parity;
      next_address        = hist[1].address;
      next_address_parity = hist[1].address_parity;
    end else if(model_done_job) begin
      next_command        = 8'h00;
      next_command_parity = 1'b1;
      next_address        = 64'h0;
      next_address_parity = 1'b1;
    end

    next_reported = model_reported;
    if(latched_valid && (latched_command == RESET))
      next_reported = 64'h0;
    else if(~(|model_reported))
      next_reported = hist[0].report_errors;

    if(checking) begin
      if(latched_valid)
        bin_command[
          (latched_command == RESET) ? 0 :
          (latched_command == START) ? 1 :
          (latched_command == COMMAND_INVALID_LOW) ? 2 : 3
        ] = 1;
      if(model_done_job)
        bin_done[model_done_source] = 1;
      if(!(|model_reported) && (|hist[0].report_errors))
        bin_capture[model_running ? 1 : 0] = 1;
      if((|model_reported) && (|hist[0].report_errors) &&
         (model_reported != hist[0].report_errors))
        bin_capture[2] = 1;
      if(!model_running && model_start_job)
        bin_running[0] = 1;
      if(was_running && !rstn_reg)
        bin_running[2] = 1;
    end

    model_job_errors = model_detected;
    model_detected   = rstn_reg ? {model_command_error, model_address_error} : 2'b00;
    model_command_error = rstn_reg ?
      (odd_parity_of({56'h0, model_command}) ^ model_command_parity) : 1'b0;
    model_address_error = rstn_reg ?
      (odd_parity_of(model_address) ^ model_address_parity) : 1'b0;

    model_done  = model_done_job;
    model_error = model_done_job ? model_reported : 64'h0;

    model_start_job      = next_start_job;
    model_reset_job      = next_reset_job;
    model_prev_rstn      = next_prev_rstn;
    model_next_rstn      = next_next_rstn;
    model_done_job       = next_done_job;
    model_running        = next_running;
    model_command        = next_command;
    model_command_parity = next_command_parity;
    model_address        = next_address;
    model_address_parity = next_address_parity;
    model_reported       = next_reported;

    // the source that armed the reset release edge detector
    if(!rstn_reg)
      model_done_source = 2;
    else if(latched_valid && (latched_command == RESET))
      model_done_source = 0;
    else if(latched_valid && (latched_command != START))
      model_done_source = 1;
  end

////////////////////////////////////////////////////////////////////////////
// stimulus
////////////////////////////////////////////////////////////////////////////

  task automatic step(input int unsigned count);
    for(int unsigned index = 0; index < count; index++)
      @(negedge clock);
  endtask

  task automatic command(
      input logic [0:7]  code          ,
      input logic [0:63] address       ,
      input logic        command_fault ,
      input logic        address_fault
  );
    job_in.valid          = 1'b1;
    job_in.command        = job_command_t'(code);
    job_in.command_parity = odd_parity_of({56'h0, code}) ^ command_fault;
    job_in.address        = address;
    job_in.address_parity = odd_parity_of(address) ^ address_fault;
    step(1);
    job_in = '0;
  endtask

  task automatic check_bins();
    bin_hits = 0;
    for(int index = 0; index < 4; index++) begin
      if(!bin_command[index])
        $fatal(1, "job missing command class bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 4; index++) begin
      if(!bin_parity[index])
        $fatal(1, "job missing parity bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_done[index])
        $fatal(1, "job missing done source bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 2; index++) begin
      if(!bin_error_pub[index])
        $fatal(1, "job missing error publication bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_capture[index])
        $fatal(1, "job missing error capture bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_running[index])
        $fatal(1, "job missing running bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_gap[index])
        $fatal(1, "job missing command gap bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 2; index++) begin
      if(!bin_reset_job[index])
        $fatal(1, "job missing reset request bin %0d", index);
      bin_hits++;
    end
    if(!bin_constant[0])
      $fatal(1, "job missing constant output bin");
    bin_hits++;
    stalls = 0;
    for(int index = 0; index < STALL_PROFILES; index++) begin
      if(!stall_used[index])
        $fatal(1, "job missing stall profile %0d", index);
      stalls++;
    end
  endtask

  initial begin
    finished             = 1'b0;
    bin_hits             = 0;
    stalls               = 0;
    cycle                = 0;
    checking             = 1'b0;
    phase                = "reset";
    rstn_in              = 1'b0;
    job_in               = '0;
    report_errors        = 64'h0;
    model_start_job      = 1'b0;
    model_reset_job      = 1'b0;
    model_prev_rstn      = 1'b0;
    model_next_rstn      = 1'b0;
    model_done_job       = 1'b0;
    model_running        = 1'b0;
    model_done           = 1'b0;
    model_error          = 64'h0;
    model_command        = 8'h00;
    model_command_parity = 1'b0;
    model_address        = 64'h0;
    model_address_parity = 1'b0;
    model_reported       = 64'h0;
    model_command_error  = 1'b0;
    model_address_error  = 1'b0;
    model_detected       = 2'b00;
    model_job_errors     = 2'b00;
    model_done_source    = 0;
    rstn_previous        = 1'b0;
    rstn_reg             = 1'b0;
    foreach(hist[position]) hist[position] = '0;

    step(4);
    rstn_in = 1'b1;
    step(DRAIN_CYCLES);

    // the model and the DUT hold a deterministic command image once the first
    // job command has been decoded
    phase = "prime";
    command(RESET, 64'h0, 1'b0, 1'b0);
    step(DRAIN_CYCLES);
    checking = 1'b1;

    // ---------------------------------------------------------------------
    phase = "reset-command-done-handshake";
    command(RESET, 64'h0000_0000_1000_0000, 1'b0, 1'b0);
    step(STALL_DONE_WAIT);
    stall_used[4] = 1;

    // ---------------------------------------------------------------------
    phase = "start-command";
    command(START, 64'h0000_0000_2000_0000, 1'b0, 1'b0);
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase         = "error-capture-while-running";
    report_errors = 64'h0000_0000_0000_0011;
    step(STALL_ERROR_HOLD);
    stall_used[3] = 1;
    report_errors = 64'h0000_0000_0000_00FF;
    step(DRAIN_CYCLES);
    report_errors = 64'h0;
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "reset-release-done-with-errors";
    rstn_in = 1'b0;
    step(STALL_RESET_LOW);
    stall_used[2] = 1;
    rstn_in = 1'b1;
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "error-capture-while-idle";
    command(RESET, 64'h0000_0000_2800_0000, 1'b0, 1'b0);
    step(DRAIN_CYCLES);
    report_errors = {64{1'b1}};
    step(STALL_ERROR_HOLD);
    report_errors = 64'h0;
    step(DRAIN_CYCLES);

    // a command that arrives while an error is already latched must not
    // overwrite the reported error word
    command(START, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0, 1'b0);
    step(DRAIN_CYCLES);
    command(COMMAND_INVALID_HIGH, 64'h0, 1'b0, 1'b0);
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    // a reset command clears the reported error word even when an external
    // error is asserted in the very cycle the command is decoded
    phase = "reset-command-clears-a-concurrent-error";
    command(RESET, 64'h0000_0000_2900_0000, 1'b0, 1'b0);
    report_errors = {64{1'b1}};
    step(1);
    report_errors = 64'h0;
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "repeat-job";
    command(RESET, 64'h0000_0000_3000_0000, 1'b0, 1'b0);
    step(DRAIN_CYCLES);
    command(START, 64'h0000_0000_4000_0000, 1'b0, 1'b0);
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "back-to-back-commands";
    command(RESET, 64'h0000_0000_5000_0000, 1'b0, 1'b0);
    command(START, 64'h0000_0000_6000_0000, 1'b0, 1'b0);
    bin_gap[0] = 1;
    step(DRAIN_CYCLES);

    command(RESET, 64'h0000_0000_7000_0000, 1'b0, 1'b0);
    step(STALL_COMMAND_GAP_SHORT);
    stall_used[0] = 1;
    command(START, 64'h0000_0000_8000_0000, 1'b0, 1'b0);
    bin_gap[1] = 1;
    step(DRAIN_CYCLES);

    command(RESET, 64'h0000_0000_9000_0000, 1'b0, 1'b0);
    step(STALL_COMMAND_GAP_LONG);
    stall_used[1] = 1;
    command(START, 64'h0000_0000_A000_0000, 1'b0, 1'b0);
    bin_gap[2] = 1;
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "invalid-commands";
    command(COMMAND_INVALID_LOW, 64'h0000_0000_B000_0000, 1'b0, 1'b0);
    step(DRAIN_CYCLES);
    command(COMMAND_INVALID_HIGH, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0, 1'b0);
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "command-parity-fault";
    command(START, 64'h0000_0000_C000_0000, 1'b1, 1'b0);
    step(DRAIN_CYCLES);
    command(RESET, 64'h0000_0000_C000_0000, 1'b0, 1'b0);
    step(DRAIN_CYCLES);

    phase = "address-parity-fault";
    command(START, 64'h0000_0000_D000_0000, 1'b0, 1'b1);
    step(DRAIN_CYCLES);
    command(RESET, 64'h0000_0000_D000_0000, 1'b0, 1'b0);
    step(DRAIN_CYCLES);

    phase = "command-and-address-parity-fault";
    command(START, 64'h0000_0000_E000_0000, 1'b1, 1'b1);
    step(DRAIN_CYCLES);
    command(RESET, 64'h0, 1'b0, 1'b0);
    step(DRAIN_CYCLES);

    check_bins();
    checking = 1'b0;
    finished = 1'b1;
  end

endmodule
