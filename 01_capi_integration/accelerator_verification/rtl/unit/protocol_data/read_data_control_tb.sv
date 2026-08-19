// read-data family: read_data_control.sv
//
// Independent model: a tag indexed half-association scoreboard over the sampled
// interface trace. The model owns its own store of cacheline halves, decides
// routing and storage from the command metadata, predicts the publication cycle
// of both halves and recomputes every parity by counting ones, never by reusing
// the DUT parity primitives.
//
// Sampling contract, cycle c is the interval closed by the posedge that samples
// it and stimulus is driven on the preceding negedge:
//   * a buffer beat at cycle T carries valid/tag/tag parity/address/data.
//   * the doubleword data parity of that beat is presented with the beat at
//     cycle T. afu_control latches valid, tag, tag parity, address, data and
//     data parity of one beat into this interface with a single common delay,
//     so every field of a beat is accepted in the same cycle.
//   * the command metadata of that beat is presented at cycle T+1.
//   * a stored beat becomes visible to a response lookup from cycle T+3.
//   * a qualified response at cycle R publishes half 0 at R+2, half 1 at R+3.
//   * a beat at cycle T reports its parity result at cycle T+4.
//   * the interface accepts a beat only while the block is enabled, so a beat
//     that was accepted just before the enable falls stays frozen with its own
//     tag, data and parity for the whole disabled window.

import GLOBALS_AFU_PKG::*;
import CAPI_PKG::*;
import AFU_PKG::*;
import CU_PKG::*;

module read_data_control_tb (
  input  logic        clock   ,
  output logic        finished,
  output int unsigned checks  ,
  output int unsigned bin_hits    ,
  output int unsigned stalls
);

  localparam int unsigned HALF_BITS  = CACHELINE_SIZE_BITS_HF;
  localparam int unsigned HIST_DEPTH = 6                     ;
  localparam int unsigned EXP_DEPTH  = 5                     ;
  localparam int unsigned COMMIT_DEPTH = 3                   ;
  localparam int unsigned ERROR_DEPTH  = 4                   ;

  // Named bounded stall profiles.
  localparam int unsigned STALL_HALF_GAP_SHORT = 1;
  localparam int unsigned STALL_HALF_GAP_LONG  = 8;
  localparam int unsigned STALL_RESPONSE_DELAY = 16;
  localparam int unsigned STALL_ENABLE_LOW     = 4;
  localparam int unsigned STALL_RESET_LOW      = 6;
  localparam int unsigned STALL_PROFILES       = 5;
  localparam int unsigned DRAIN_CYCLES         = 8;

  // Response distance from the beat that must, and must not, be visible.
  localparam int unsigned RESPONSE_GAP_COMMITTED = 3;
  localparam int unsigned RESPONSE_GAP_PRECOMMIT = 2;

  logic                       rstn_in                ;
  logic                       enabled_in             ;
  ReadDataControlInterface    buffer_in              ;
  CommandTagLine              data_read_tag_id_in    ;
  ResponseControlInterfaceOut response_control_in    ;
  logic [0:1]                 data_read_error        ;
  DataControlInterfaceOut     read_data_control_out_0;
  DataControlInterfaceOut     read_data_control_out_1;

  read_data_control dut (
    .clock                  (clock                  ),
    .rstn_in                (rstn_in                ),
    .enabled_in             (enabled_in             ),
    .buffer_in              (buffer_in              ),
    .data_read_tag_id_in    (data_read_tag_id_in    ),
    .response_control_in    (response_control_in    ),
    .data_read_error        (data_read_error        ),
    .read_data_control_out_0(read_data_control_out_0),
    .read_data_control_out_1(read_data_control_out_1)
  );

////////////////////////////////////////////////////////////////////////////
// independent parity reference
////////////////////////////////////////////////////////////////////////////

  function automatic logic odd_parity_of(input logic [0:63] value);
    odd_parity_of = (($countones(value) % 2) == 0);
  endfunction

  function automatic logic [0:7] dw_odd_parity(input logic [0:(HALF_BITS-1)] value);
    logic [0:7] result;
    for(int unsigned lane = 0; lane < 8; lane++)
      result[lane] = odd_parity_of(value[64*lane +: 64]);
    return result;
  endfunction

////////////////////////////////////////////////////////////////////////////
// stimulus and model types
////////////////////////////////////////////////////////////////////////////

  typedef struct packed {
    logic                   valid     ;
    logic [0:7]             tag       ;
    logic [0:5]             address   ;
    logic [0:(HALF_BITS-1)] data      ;
    logic                   tag_fault ;
    logic                   data_fault;
    CommandTagLine          cmd       ;
  } beat_t;

  typedef struct packed {
    logic          valid   ;
    logic [0:7]    tag     ;
    logic          read    ;
    logic          wed     ;
    logic          write   ;
    psl_response_t response;
  } resp_t;

  typedef struct packed {
    logic                   line_valid;
    logic                   read_data ;
    logic                   wed_data  ;
    CommandTagLine          cmd       ;
    logic [0:(HALF_BITS-1)] data      ;
  } entry_t;

  typedef struct packed {
    logic                   enabled_in ;
    logic                   rstn_in    ;
    logic                   rstn_reg   ;
    logic                   en_reg     ;
    logic                   valid      ;
    logic [0:7]             tag        ;
    logic                   tag_parity ;
    logic [0:5]             address    ;
    logic [0:(HALF_BITS-1)] data       ;
    logic [0:7]             data_parity;
    CommandTagLine          cmd        ;
    logic                   resp_valid ;
    logic [0:7]             resp_tag   ;
    logic                   resp_read  ;
    logic                   resp_wed   ;
    logic                   resp_write ;
    psl_response_t          resp_code  ;
  } sample_t;

  sample_t hist [0:HIST_DEPTH-1];

  entry_t model_memory [0:1][0:255];

  // Independent model of the accepted beat. Every field of a beat is accepted
  // together while the block is enabled and freezes together when it is not,
  // so the model keeps one accepted beat image instead of reading the raw bus
  // history.
  logic [0:7]             accepted_tag       ;
  logic [0:5]             accepted_address   ;
  logic [0:(HALF_BITS-1)] accepted_data      ;
  logic [0:7]             accepted_parity    ;
  logic                   accepted_valid     ;
  logic                   accepted_tag_parity;

  logic       commit_pending [0:COMMIT_DEPTH-1];
  logic       commit_half_id [0:COMMIT_DEPTH-1];
  logic [0:7] commit_tag     [0:COMMIT_DEPTH-1];
  entry_t     commit_entry   [0:COMMIT_DEPTH-1];

  logic [0:1] error_pipe [0:ERROR_DEPTH-1];

  logic   exp0_publish [0:EXP_DEPTH-1];
  entry_t exp0_entry   [0:EXP_DEPTH-1];
  logic   exp1_publish [0:EXP_DEPTH-1];
  entry_t exp1_entry   [0:EXP_DEPTH-1];

  int unsigned cycle    ;
  logic        checking ;
  string       phase    ;
  beat_t       prev_beat;

  bit bin_half_order      [0:3]     ;
  bit bin_route           [0:2][0:1];
  bit bin_response_class  [0:5]     ;
  bit bin_parity          [0:3]     ;
  bit bin_address         [0:4]     ;
  bit bin_gap             [0:2]     ;
  bit bin_response_timing [0:2]     ;
  bit bin_tag             [0:3]     ;
  bit bin_control         [0:2]     ;
  bit bin_parity_association [0:1]  ;
  bit bin_enable_window   [0:1]     ;
  bit stall_used          [0:4]     ;

////////////////////////////////////////////////////////////////////////////
// diagnostics
////////////////////////////////////////////////////////////////////////////

  task automatic fail(input string reason);
    $error(
      "read_data mismatch reason=%s phase=%s cycle=%0d",
      reason,
      phase,
      cycle
    );
    $fatal(1);
  endtask

////////////////////////////////////////////////////////////////////////////
// stimulus helpers
////////////////////////////////////////////////////////////////////////////

  function automatic CommandTagLine make_cmd(
      input command_type ctype,
      input logic [0:7]  tag  ,
      input logic [0:7]  salt
  );
    CommandTagLine cmd;
    cmd                  = '0;
    cmd.cu_id_x          = salt;
    cmd.cu_id_y          = ~salt;
    cmd.array_struct     = array_struct_type'(1);
    cmd.cmd_type         = ctype;
    cmd.real_size        = 8'h20;
    cmd.real_size_bytes  = 8'h80;
    cmd.cacheline_offset = salt;
    cmd.address_offset   = {56'h0, tag};
    cmd.aux_data         = {tag, 56'h5A5A5A5A5A5A5A};
    cmd.size             = 12'h080;
    cmd.tag              = ~tag; // the DUT must overwrite this with the buffer tag
    cmd.abt              = STRICT;
    return cmd;
  endfunction

  function automatic logic [0:(HALF_BITS-1)] make_pattern(
      input logic [0:7] tag ,
      input logic       half,
      input logic [0:7] salt
  );
    logic [0:(HALF_BITS-1)] result;
    for(int unsigned lane = 0; lane < 8; lane++)
      result[64*lane +: 64] = {
        tag,
        salt,
        7'h00,
        half,
        8'(lane),
        32'hC0DE_0000 ^ (32'(lane) << 12)
      };
    return result;
  endfunction

  function automatic beat_t make_beat(
      input logic [0:7]             tag       ,
      input logic [0:5]             address   ,
      input logic [0:(HALF_BITS-1)] data      ,
      input command_type            ctype     ,
      input logic                   tag_fault ,
      input logic                   data_fault,
      input logic [0:7]             salt
  );
    beat_t beat;
    beat.valid      = 1'b1;
    beat.tag        = tag;
    beat.address    = address;
    beat.data       = data;
    beat.tag_fault  = tag_fault;
    beat.data_fault = data_fault;
    beat.cmd        = make_cmd(ctype, tag, salt);
    return beat;
  endfunction

  function automatic beat_t idle_beat();
    beat_t beat;
    beat     = '0;
    beat.cmd = make_cmd(CMD_INVALID, 8'h00, 8'h00);
    return beat;
  endfunction

  // An idle cycle whose parity byte is corrupted. A device that associates the
  // parity of a beat with the parity input of the following cycle reports an
  // error for the previous beat, a device that associates the parity with the
  // accepted beat stays quiet.
  function automatic beat_t corrupt_idle_beat();
    beat_t beat;
    beat            = idle_beat();
    beat.data_fault = 1'b1;
    return beat;
  endfunction

  function automatic resp_t idle_resp();
    resp_t response;
    response          = '0;
    response.response = DONE;
    return response;
  endfunction

  function automatic resp_t make_resp(
      input logic          valid   ,
      input logic [0:7]    tag     ,
      input logic          read    ,
      input logic          wed     ,
      input logic          write   ,
      input psl_response_t code
  );
    resp_t response;
    response.valid    = valid;
    response.tag      = tag;
    response.read     = read;
    response.wed      = wed;
    response.write    = write;
    response.response = code;
    return response;
  endfunction

  task automatic drive(input beat_t beat, input resp_t response);
    CommandTagLine response_cmd;

    @(negedge clock);

    buffer_in.write_valid      = beat.valid;
    buffer_in.write_tag        = beat.tag;
    buffer_in.write_tag_parity = odd_parity_of({56'h0, beat.tag}) ^ beat.tag_fault;
    buffer_in.write_address    = beat.address;
    buffer_in.write_data       = beat.data;
    buffer_in.write_parity     =
      dw_odd_parity(beat.data) ^ (beat.data_fault ? 8'h20 : 8'h00);

    data_read_tag_id_in = prev_beat.cmd;

    response_cmd     = make_cmd(CMD_READ, response.tag, 8'h11);
    response_cmd.tag = response.tag;

    response_control_in                                   = '0;
    response_control_in.read_response                     = response.read;
    response_control_in.wed_response                      = response.wed;
    response_control_in.write_response                    = response.write;
    response_control_in.response.valid                    = response.valid;
    response_control_in.response.payload.cmd              = response_cmd;
    response_control_in.response.payload.response_credits = 9'h001;
    response_control_in.response.payload.response         = response.response;

    prev_beat = beat;
  endtask

  task automatic idle_cycles(input int unsigned count);
    for(int unsigned index = 0; index < count; index++)
      drive(idle_beat(), idle_resp());
  endtask

////////////////////////////////////////////////////////////////////////////
// model and checker
////////////////////////////////////////////////////////////////////////////

  function automatic entry_t quiet_entry();
    entry_t entry;
    entry = '0;
    return entry;
  endfunction

  task automatic check_half(
      input int unsigned            half    ,
      input logic                   publish ,
      input entry_t                 expected,
      input DataControlInterfaceOut actual
  );
    checks++;
    if(publish) begin
      if(actual.line.valid !== expected.line_valid)
        fail($sformatf("half %0d publication valid", half));
      if(actual.read_data !== expected.read_data)
        fail($sformatf("half %0d read destination", half));
      if(actual.wed_data !== expected.wed_data)
        fail($sformatf("half %0d wed destination", half));
      if(actual.line.payload.cmd !== expected.cmd)
        fail($sformatf("half %0d tag metadata association", half));
      if(actual.line.payload.data !== expected.data)
        fail($sformatf("half %0d cacheline payload", half));
    end else begin
      if(actual.line.valid !== 1'b0 || actual.read_data !== 1'b0 || actual.wed_data !== 1'b0)
        fail($sformatf("half %0d published without a qualified response", half));
    end
  endtask

  always @(posedge clock) begin
    sample_t    snapshot      ;
    entry_t     entry       ;
    logic       half        ;
    logic [0:1] compare_now ;
    logic       qualified   ;

    for(int index = HIST_DEPTH-1; index > 0; index--)
      hist[index] = hist[index-1];

    snapshot             = '0;
    snapshot.enabled_in  = enabled_in;
    snapshot.rstn_in     = rstn_in;
    snapshot.rstn_reg    = rstn_in ? hist[1].rstn_in : 1'b0;
    snapshot.en_reg      = (rstn_in && hist[1].rstn_in) ? hist[1].enabled_in : 1'b0;
    snapshot.valid       = buffer_in.write_valid;
    snapshot.tag         = buffer_in.write_tag;
    snapshot.tag_parity  = buffer_in.write_tag_parity;
    snapshot.address     = buffer_in.write_address;
    snapshot.data        = buffer_in.write_data;
    snapshot.data_parity = buffer_in.write_parity;
    snapshot.cmd         = data_read_tag_id_in;
    snapshot.resp_valid  = response_control_in.response.valid;
    snapshot.resp_tag    = response_control_in.response.payload.cmd.tag;
    snapshot.resp_read   = response_control_in.read_response;
    snapshot.resp_wed    = response_control_in.wed_response;
    snapshot.resp_write  = response_control_in.write_response;
    snapshot.resp_code   = response_control_in.response.payload.response;
    hist[0]            = snapshot;
    cycle++;

    // the accepted beat registers follow the asynchronous reset immediately
    if(!hist[0].rstn_reg) begin
      accepted_tag        = 8'h00;
      accepted_address    = 6'h00;
      accepted_data       = '0;
      accepted_parity     = 8'h00;
      accepted_valid      = 1'b0;
      accepted_tag_parity = 1'b1;
    end

    // the entry that was formed two cycles ago reaches the tag indexed store
    if(commit_pending[0])
      model_memory[commit_half_id[0]][commit_tag[0]] = commit_entry[0];

    // the accepted beat is routed and stored while the block is enabled
    if(accepted_valid && hist[0].en_reg) begin
      entry            = '0;
      entry.line_valid = 1'b1;
      case (hist[0].cmd.cmd_type)
        CMD_READ : begin
          entry.read_data = 1'b1;
        end
        CMD_WED : begin
          entry.wed_data = 1'b1;
        end
        default : begin
          entry.read_data = 1'b0;
          entry.wed_data  = 1'b0;
        end
      endcase
      entry.cmd     = hist[0].cmd;
      entry.cmd.tag = accepted_tag;
      entry.data    = accepted_data;
      half          = |accepted_address;
      if(entry.read_data || entry.wed_data) begin
        commit_pending[COMMIT_DEPTH-1] = 1'b1;
        commit_half_id[COMMIT_DEPTH-1] = half;
        commit_tag[COMMIT_DEPTH-1]     = accepted_tag;
        commit_entry[COMMIT_DEPTH-1]   = entry;
      end
      if(checking) begin
        bin_route[entry.read_data ? 0 : (entry.wed_data ? 1 : 2)][half] = 1;
        bin_tag[
          accepted_tag == 8'h00 ? 0 :
          accepted_tag == 8'h01 ? 1 :
          accepted_tag == 8'h7F ? 2 : 3
        ] = 1;
        bin_address[
          accepted_address == 6'h00 ? 0 :
          accepted_address == 6'h01 ? 1 :
          accepted_address == 6'h02 ? 2 :
          accepted_address == 6'h20 ? 3 : 4
        ] = 1;
      end
    end

    // the parity of the accepted beat is compared in this cycle and reported
    // three cycles later
    compare_now = 2'b00;
    if(accepted_valid)
      compare_now = {
        odd_parity_of({56'h0, accepted_tag}) ^ accepted_tag_parity,
        |(dw_odd_parity(accepted_data) ^ accepted_parity)
      };

    if(checking) begin
      check_half(0, exp0_publish[0], exp0_entry[0], read_data_control_out_0);
      check_half(1, exp1_publish[0], exp1_entry[0], read_data_control_out_1);

      checks++;
      if(data_read_error !== error_pipe[0])
        fail($sformatf(
          "parity report expected=%2b actual=%2b",
          error_pipe[0],
          data_read_error
        ));
      if(accepted_valid)
        bin_parity[{compare_now[0], compare_now[1]}] = 1;

      // A cycle only distinguishes the two candidate parity associations when
      // the parity accepted with the beat differs from the parity byte the bus
      // presents in the compare cycle. Both bins require a discriminating cycle.
      if(accepted_valid && (accepted_parity != hist[0].data_parity))
        bin_parity_association[compare_now[1]] = 1;

      // The enabled falling edge window. While the block is disabled the bus
      // keeps presenting payloads that the interface must not accept, so a
      // cycle only discriminates when the presented payload would parity differ
      // from the frozen beat.
      if(accepted_valid && !hist[0].en_reg &&
         (dw_odd_parity(accepted_data) != dw_odd_parity(hist[0].data)))
        bin_enable_window[compare_now[1]] = 1;

      if(hist[0].resp_valid) begin
        bin_response_class[
          (hist[0].resp_code == NLOCK) ? 4 :
          (hist[0].resp_read && hist[0].resp_wed) ? 2 :
          hist[0].resp_read ? 0 :
          hist[0].resp_wed ? 1 : 3
        ] = 1;
      end else if(hist[0].resp_read || hist[0].resp_wed || hist[0].resp_write) begin
        bin_response_class[5] = 1;
      end
    end

    // the aggregation stage also needs the enable in the cycle after a response
    if(!hist[0].en_reg) begin
      exp0_publish[1] = 1'b0;
      exp0_entry[1]   = quiet_entry();
      exp1_publish[2] = 1'b0;
      exp1_entry[2]   = quiet_entry();
    end

    qualified = hist[0].resp_valid && hist[0].en_reg &&
      (hist[0].resp_read || hist[0].resp_wed) && (hist[0].resp_code != NLOCK);
    if(qualified) begin
      exp0_publish[2] = 1'b1;
      exp0_entry[2]   = model_memory[0][hist[0].resp_tag];
      exp1_publish[3] = 1'b1;
      exp1_entry[3]   = model_memory[1][hist[0].resp_tag];
    end

    for(int index = 0; index < EXP_DEPTH-1; index++) begin
      exp0_publish[index] = exp0_publish[index+1];
      exp0_entry[index]   = exp0_entry[index+1];
      exp1_publish[index] = exp1_publish[index+1];
      exp1_entry[index]   = exp1_entry[index+1];
    end
    exp0_publish[EXP_DEPTH-1] = 1'b0;
    exp0_entry[EXP_DEPTH-1]   = quiet_entry();
    exp1_publish[EXP_DEPTH-1] = 1'b0;
    exp1_entry[EXP_DEPTH-1]   = quiet_entry();

    error_pipe[ERROR_DEPTH-1] = compare_now;
    for(int index = 0; index < ERROR_DEPTH-1; index++)
      error_pipe[index] = error_pipe[index+1];
    error_pipe[ERROR_DEPTH-1] = 2'b00;

    for(int index = 0; index < COMMIT_DEPTH-1; index++) begin
      commit_pending[index] = commit_pending[index+1];
      commit_half_id[index] = commit_half_id[index+1];
      commit_tag[index]     = commit_tag[index+1];
      commit_entry[index]   = commit_entry[index+1];
    end
    commit_pending[COMMIT_DEPTH-1] = 1'b0;

    // the interface accepts a new beat only while the block is enabled
    if(!hist[0].rstn_reg) begin
      accepted_tag        = 8'h00;
      accepted_address    = 6'h00;
      accepted_data       = '0;
      accepted_parity     = 8'h00;
      accepted_valid      = 1'b0;
      accepted_tag_parity = 1'b1;
    end else begin
      if(hist[0].en_reg) begin
        accepted_tag     = hist[0].tag;
        accepted_address = hist[0].address;
        accepted_data    = hist[0].data;
        accepted_parity  = hist[0].data_parity;
        accepted_valid   = hist[0].valid;
      end
      accepted_tag_parity =
        (hist[0].en_reg && hist[0].valid) ? hist[0].tag_parity : 1'b1;
    end
  end

////////////////////////////////////////////////////////////////////////////
// scenarios
////////////////////////////////////////////////////////////////////////////

  task automatic drive_cacheline(
      input logic [0:7]  tag        ,
      input command_type ctype      ,
      input logic        high_first ,
      input logic [0:5]  high_encode,
      input int unsigned half_gap   ,
      input logic [0:7]  salt
  );
    logic [0:5] first_address ;
    logic [0:5] second_address;

    first_address  = high_first ? high_encode : 6'h00;
    second_address = high_first ? 6'h00 : high_encode;

    drive(
      make_beat(
        tag,
        first_address,
        make_pattern(tag, high_first, salt),
        ctype,
        1'b0,
        1'b0,
        salt
      ),
      idle_resp()
    );
    idle_cycles(half_gap);
    drive(
      make_beat(
        tag,
        second_address,
        make_pattern(tag, !high_first, salt),
        ctype,
        1'b0,
        1'b0,
        salt
      ),
      idle_resp()
    );

    bin_half_order[high_first ? 1 : 0] = 1;
    bin_gap[half_gap == 0 ? 0 : (half_gap == STALL_HALF_GAP_SHORT ? 1 : 2)] = 1;
  endtask

  task automatic publish(input logic [0:7] tag, input command_type ctype);
    drive(
      idle_beat(),
      make_resp(1'b1, tag, ctype == CMD_READ, ctype == CMD_WED, 1'b0, DONE)
    );
    idle_cycles(DRAIN_CYCLES);
  endtask

  task automatic check_bins();
    bin_hits = 0;
    for(int index = 0; index < 4; index++) begin
      if(!bin_half_order[index])
        $fatal(1, "read_data missing half order bin %0d", index);
      bin_hits++;
    end
    for(int route = 0; route < 3; route++)
      for(int half = 0; half < 2; half++) begin
        if(!bin_route[route][half])
          $fatal(1, "read_data missing route bin %0d half %0d", route, half);
        bin_hits++;
      end
    for(int index = 0; index < 6; index++) begin
      if(!bin_response_class[index])
        $fatal(1, "read_data missing response class bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 4; index++) begin
      if(!bin_parity[index])
        $fatal(1, "read_data missing parity bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 5; index++) begin
      if(!bin_address[index])
        $fatal(1, "read_data missing address bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_gap[index])
        $fatal(1, "read_data missing gap bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_response_timing[index])
        $fatal(1, "read_data missing response timing bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 4; index++) begin
      if(!bin_tag[index])
        $fatal(1, "read_data missing tag bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_control[index])
        $fatal(1, "read_data missing control bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 2; index++) begin
      if(!bin_parity_association[index])
        $fatal(1, "read_data missing parity association bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 2; index++) begin
      if(!bin_enable_window[index])
        $fatal(1, "read_data missing enabled window bin %0d", index);
      bin_hits++;
    end
    stalls = 0;
    for(int index = 0; index < STALL_PROFILES; index++) begin
      if(!stall_used[index])
        $fatal(1, "read_data missing stall profile %0d", index);
      stalls++;
    end
  endtask

  initial begin
    beat_t      beat     ;
    beat_t      ones_beat;
    logic [0:(HALF_BITS-1)] frozen_data;
    logic [0:(HALF_BITS-1)] window_data;
    logic [0:7] tags [0:3];

    finished            = 1'b0;
    bin_hits                = 0;
    stalls              = 0;
    cycle               = 0;
    checking            = 1'b0;
    phase               = "reset";
    rstn_in             = 1'b0;
    enabled_in          = 1'b0;
    prev_beat           = idle_beat();
    buffer_in           = '0;
    data_read_tag_id_in = '0;
    response_control_in = '0;
    accepted_tag        = 8'h00;
    accepted_address    = 6'h00;
    accepted_data       = '0;
    accepted_parity     = 8'h00;
    accepted_valid      = 1'b0;
    accepted_tag_parity = 1'b1;
    foreach(hist[index]) hist[index] = '0;
    for(int index = 0; index < COMMIT_DEPTH; index++) begin
      commit_pending[index] = 1'b0;
      commit_half_id[index] = 1'b0;
      commit_tag[index]     = 8'h00;
      commit_entry[index]   = quiet_entry();
    end
    for(int index = 0; index < ERROR_DEPTH; index++)
      error_pipe[index] = 2'b00;
    for(int index = 0; index < EXP_DEPTH; index++) begin
      exp0_publish[index] = 1'b0;
      exp0_entry[index]   = quiet_entry();
      exp1_publish[index] = 1'b0;
      exp1_entry[index]   = quiet_entry();
    end
    for(int half = 0; half < 2; half++)
      for(int tag = 0; tag < 256; tag++)
        model_memory[half][tag] = quiet_entry();

    idle_cycles(4);
    rstn_in    = 1'b1;
    enabled_in = 1'b1;
    idle_cycles(DRAIN_CYCLES);
    checking = 1'b1;

    // ---------------------------------------------------------------------
    phase = "half-order-low-first";
    drive_cacheline(8'h01, CMD_READ, 1'b0, 6'h01, 0, 8'h01);
    idle_cycles(RESPONSE_GAP_COMMITTED - 1);
    bin_response_timing[0] = 1;
    publish(8'h01, CMD_READ);

    // ---------------------------------------------------------------------
    phase = "half-order-high-first";
    drive_cacheline(8'h7F, CMD_WED, 1'b1, 6'h02, STALL_HALF_GAP_SHORT, 8'h22);
    stall_used[0] = 1;
    idle_cycles(STALL_RESPONSE_DELAY);
    stall_used[2]          = 1;
    bin_response_timing[2] = 1;
    publish(8'h7F, CMD_WED);

    // ---------------------------------------------------------------------
    phase = "half-gap-long";
    drive_cacheline(8'hFF, CMD_READ, 1'b0, 6'h20, STALL_HALF_GAP_LONG, 8'h33);
    stall_used[1] = 1;
    idle_cycles(DRAIN_CYCLES);
    publish(8'hFF, CMD_READ);

    // ---------------------------------------------------------------------
    phase = "lower-half-only";
    drive(
      make_beat(8'h10, 6'h00, make_pattern(8'h10, 1'b0, 8'h44), CMD_READ, 1'b0, 1'b0, 8'h44),
      idle_resp()
    );
    bin_half_order[2] = 1;
    idle_cycles(DRAIN_CYCLES);
    publish(8'h10, CMD_READ);

    phase = "upper-half-only";
    drive(
      make_beat(8'h11, 6'h3F, make_pattern(8'h11, 1'b1, 8'h55), CMD_READ, 1'b0, 1'b0, 8'h55),
      idle_resp()
    );
    bin_half_order[3] = 1;
    idle_cycles(DRAIN_CYCLES);
    publish(8'h11, CMD_READ);

    // ---------------------------------------------------------------------
    phase   = "tag-interleave";
    tags[0] = 8'h00;
    tags[1] = 8'h01;
    tags[2] = 8'h7F;
    tags[3] = 8'hFF;
    for(int index = 0; index < 4; index++)
      drive(
        make_beat(
          tags[index],
          6'h00,
          make_pattern(tags[index], 1'b0, 8'h60 + 8'(index)),
          CMD_READ,
          1'b0,
          1'b0,
          8'h60 + 8'(index)
        ),
        idle_resp()
      );
    for(int index = 3; index >= 0; index--)
      drive(
        make_beat(
          tags[index],
          6'h01,
          make_pattern(tags[index], 1'b1, 8'h60 + 8'(index)),
          CMD_READ,
          1'b0,
          1'b0,
          8'h60 + 8'(index)
        ),
        idle_resp()
      );
    idle_cycles(DRAIN_CYCLES);
    for(int index = 0; index < 4; index++)
      publish(tags[index], CMD_READ);

    // ---------------------------------------------------------------------
    phase = "unrouted-command-type";
    drive(
      make_beat(8'h20, 6'h00, make_pattern(8'h20, 1'b0, 8'h70), CMD_WRITE, 1'b0, 1'b0, 8'h70),
      idle_resp()
    );
    drive(
      make_beat(
        8'h20,
        6'h01,
        make_pattern(8'h20, 1'b1, 8'h70),
        CMD_PREFETCH_READ,
        1'b0,
        1'b0,
        8'h70
      ),
      idle_resp()
    );
    idle_cycles(DRAIN_CYCLES);
    publish(8'h20, CMD_READ);

    // ---------------------------------------------------------------------
    phase = "response-classes";
    drive(idle_beat(), make_resp(1'b1, 8'h01, 1'b0, 1'b0, 1'b1, DONE));
    idle_cycles(DRAIN_CYCLES);
    drive(idle_beat(), make_resp(1'b1, 8'h01, 1'b1, 1'b0, 1'b0, NLOCK));
    idle_cycles(DRAIN_CYCLES);
    drive(idle_beat(), make_resp(1'b1, 8'h01, 1'b1, 1'b1, 1'b0, DONE));
    idle_cycles(DRAIN_CYCLES);
    drive(idle_beat(), make_resp(1'b0, 8'h01, 1'b1, 1'b0, 1'b0, DONE));
    idle_cycles(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "parity-faults";
    drive(
      make_beat(8'h30, 6'h00, make_pattern(8'h30, 1'b0, 8'h80), CMD_READ, 1'b1, 1'b0, 8'h80),
      idle_resp()
    );
    idle_cycles(DRAIN_CYCLES);
    drive(
      make_beat(8'h31, 6'h00, make_pattern(8'h31, 1'b0, 8'h81), CMD_READ, 1'b0, 1'b1, 8'h81),
      idle_resp()
    );
    idle_cycles(DRAIN_CYCLES);
    drive(
      make_beat(8'h32, 6'h00, make_pattern(8'h32, 1'b0, 8'h82), CMD_READ, 1'b1, 1'b1, 8'h82),
      idle_resp()
    );
    idle_cycles(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    // The parity of a beat is the parity accepted with that beat. A clean beat
    // followed by a corrupted parity byte must stay quiet, and a beat that
    // carries a corrupted parity must be reported even when the following
    // cycle presents a correct parity byte. Both cases are only counted when
    // the two parity bytes differ, so the regression cannot degrade into a
    // scenario that both associations would pass.
    phase = "parity-beat-association";
    drive(
      make_beat(8'h33, 6'h00, make_pattern(8'h33, 1'b0, 8'hB0), CMD_READ, 1'b0, 1'b0, 8'hB0),
      idle_resp()
    );
    drive(corrupt_idle_beat(), idle_resp());
    idle_cycles(DRAIN_CYCLES);

    drive(
      make_beat(8'h34, 6'h00, make_pattern(8'h34, 1'b0, 8'hB1), CMD_READ, 1'b0, 1'b1, 8'hB1),
      idle_resp()
    );
    drive(idle_beat(), idle_resp());
    idle_cycles(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    // The enable falls in the cycle right after a beat is accepted. The
    // accepted beat stays valid inside the block for the whole window, so the
    // parity of that beat is compared again in every disabled cycle. The bus
    // keeps presenting a different payload during the window, which an
    // interface that latched the payload without the enable would compare
    // against the frozen parity of the accepted beat. Tags 8'h03 and 8'h05
    // carry an even number of ones, so the tag parity report stays quiet while
    // the tag parity register holds its odd default.
    phase = "enabled-mid-beat-window-clean-beat";
    frozen_data    = make_pattern(8'h03, 1'b0, 8'hC0);
    window_data    = frozen_data;
    window_data[0] = ~window_data[0]; // one lane parity differs by construction
    drive(
      make_beat(8'h03, 6'h00, frozen_data, CMD_READ, 1'b0, 1'b0, 8'hC0),
      idle_resp()
    );
    enabled_in = 1'b0;
    for(int index = 0; index < STALL_ENABLE_LOW; index++)
      drive(
        make_beat(8'h0C, 6'h01, window_data, CMD_READ, 1'b0, 1'b0, 8'hC1),
        idle_resp()
      );
    enabled_in = 1'b1;
    idle_cycles(DRAIN_CYCLES);

    phase = "enabled-mid-beat-window-faulty-beat";
    frozen_data    = make_pattern(8'h05, 1'b0, 8'hC2);
    window_data    = frozen_data;
    window_data[0] = ~window_data[0];
    drive(
      make_beat(8'h05, 6'h00, frozen_data, CMD_READ, 1'b0, 1'b1, 8'hC2),
      idle_resp()
    );
    enabled_in = 1'b0;
    for(int index = 0; index < STALL_ENABLE_LOW; index++)
      drive(
        make_beat(8'h0A, 6'h01, window_data, CMD_READ, 1'b0, 1'b0, 8'hC3),
        idle_resp()
      );
    enabled_in = 1'b1;
    idle_cycles(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "response-before-commit";
    drive(
      make_beat(8'h40, 6'h00, make_pattern(8'h40, 1'b0, 8'h90), CMD_READ, 1'b0, 1'b0, 8'h90),
      idle_resp()
    );
    idle_cycles(RESPONSE_GAP_PRECOMMIT - 1);
    bin_response_timing[1] = 1;
    publish(8'h40, CMD_READ);
    publish(8'h40, CMD_READ);

    // ---------------------------------------------------------------------
    phase      = "disabled-window";
    enabled_in = 1'b0;
    idle_cycles(2);
    for(int index = 0; index < STALL_ENABLE_LOW; index++)
      drive(
        make_beat(8'h50, 6'h00, make_pattern(8'h50, 1'b0, 8'hA0), CMD_READ, 1'b0, 1'b0, 8'hA0),
        idle_resp()
      );
    stall_used[3] = 1;
    idle_cycles(2);
    enabled_in = 1'b1;
    idle_cycles(DRAIN_CYCLES);
    publish(8'h50, CMD_READ);
    bin_control[0] = 1;

    // ---------------------------------------------------------------------
    phase   = "reset-window";
    rstn_in = 1'b0;
    idle_cycles(STALL_RESET_LOW);
    stall_used[4] = 1;
    rstn_in       = 1'b1;
    idle_cycles(DRAIN_CYCLES);
    bin_control[1] = 1;

    phase = "reset-retains-store";
    publish(8'h01, CMD_READ);
    bin_control[2] = 1;

    // ---------------------------------------------------------------------
    phase = "response-code-sweep";
    drive(
      idle_beat(),
      make_resp(1'b1, 8'h01, 1'b1, 1'b0, 1'b0, psl_response_t'(8'hFF))
    );
    idle_cycles(DRAIN_CYCLES);
    drive(idle_beat(), make_resp(1'b1, 8'h01, 1'b1, 1'b0, 1'b0, PAGED));
    idle_cycles(DRAIN_CYCLES);
    drive(idle_beat(), make_resp(1'b1, 8'h01, 1'b1, 1'b0, 1'b0, FAILED));
    idle_cycles(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase          = "toggle-fill";
    ones_beat      = idle_beat();
    ones_beat.valid   = 1'b1;
    ones_beat.tag     = 8'hFF;
    ones_beat.address = 6'h3F;
    ones_beat.data    = {HALF_BITS{1'b1}};
    ones_beat.cmd     = '1;
    drive(ones_beat, idle_resp());
    beat         = idle_beat();
    beat.valid   = 1'b1;
    beat.tag     = 8'h00;
    beat.address = 6'h00;
    beat.data    = {HALF_BITS{1'b0}};
    beat.cmd     = '0;
    drive(beat, idle_resp());
    idle_cycles(DRAIN_CYCLES);

    check_bins();
    checking = 1'b0;
    finished = 1'b1;
  end

endmodule
