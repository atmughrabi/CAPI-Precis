// wed family: wed_control.sv
//
// Independent model: a byte level 128 byte work element descriptor decoder plus
// a fetch-once lifecycle model. The decoder oracle reverses the byte order of
// every descriptor field group directly from the delivered cacheline bytes, it
// never calls the production mapping function. The lifecycle model owns its own
// state enumeration, transition table and capture rules.
//
// Sampling contract, cycle c is the interval closed by the posedge that samples
// it:
//   * outputs published during cycle c+1 are produced by the state and the
//     inputs of cycle c.
//   * a data half is captured while the model waits for the fetch response and
//     the delivered command identifies the descriptor engine.
//   * the descriptor is published one cycle after the accepted response.

import GLOBALS_AFU_PKG::*;
import CAPI_PKG::*;
import WED_PKG::*;
import AFU_PKG::*;
import CU_PKG::*;

module wed_control_tb (
  input  logic        clock   ,
  output logic        finished,
  output int unsigned checks  ,
  output int unsigned bin_hits,
  output int unsigned stalls
);

  localparam int unsigned LINE_BITS = CACHELINE_SIZE_BITS;
  localparam int unsigned HALF_BITS = CACHELINE_SIZE_BITS_HF;

  // Number of leading four byte descriptor fields of the active variant. The
  // runner derives the value from the descriptor field groups of the variant
  // work element descriptor package and passes it in, the default matches a
  // descriptor that is built from eight byte fields only.
`ifdef WED_WORD_GROUP_COUNT
  localparam int unsigned WED_WORD_GROUPS = `WED_WORD_GROUP_COUNT;
`else
  localparam int unsigned WED_WORD_GROUPS = 0;
`endif

  // Named bounded stall profiles.
  localparam int unsigned STALL_ALFULL_HOLD   = 10;
  localparam int unsigned STALL_DISABLED_HOLD = 6 ;
  localparam int unsigned STALL_RESPONSE_WAIT = 12;
  localparam int unsigned STALL_HALF_GAP      = 5 ;
  localparam int unsigned STALL_RESET_LOW     = 6 ;
  localparam int unsigned STALL_PROFILES      = 5 ;
  localparam int unsigned DRAIN_CYCLES        = 8 ;
  localparam int unsigned PROGRESS_BOUND      = 64;

  typedef enum int unsigned {
    MODEL_RESET  ,
    MODEL_IDLE   ,
    MODEL_REQUEST,
    MODEL_WAITING,
    MODEL_PUBLISH
  } model_state_t;

  logic              rstn_in              ;
  logic              enabled_in           ;
  logic [0:63]       wed_address          ;
  ReadWriteDataLine  wed_data_0_in        ;
  ReadWriteDataLine  wed_data_1_in        ;
  ResponseBufferLine wed_response_in      ;
  BufferStatus       command_buffer_status;
  CommandBufferLine  command_out          ;
  WEDInterface       wed_request_out      ;

  wed_control dut (
    .clock                (clock                ),
    .enabled_in           (enabled_in           ),
    .rstn_in              (rstn_in              ),
    .wed_address          (wed_address          ),
    .wed_data_0_in        (wed_data_0_in        ),
    .wed_data_1_in        (wed_data_1_in        ),
    .wed_response_in      (wed_response_in      ),
    .command_buffer_status(command_buffer_status),
    .command_out          (command_out          ),
    .wed_request_out      (wed_request_out      )
  );

////////////////////////////////////////////////////////////////////////////
// independent descriptor decoder
////////////////////////////////////////////////////////////////////////////

  function automatic logic [0:(LINE_BITS-1)] wed_decode(
      input logic [0:(LINE_BITS-1)] line
  );
    logic [0:(LINE_BITS-1)] result;
    int                     offset;
    int                     word_bits;
    int                     group_bytes;

    result    = '0;
    offset    = 0;
    word_bits = 32 * int'(WED_WORD_GROUPS);
    while(offset < int'(LINE_BITS)) begin
      group_bytes = (offset < word_bits) ? 4 : 8;
      for(int byte_index = 0; byte_index < group_bytes; byte_index++)
        result[offset + 8*byte_index +: 8] =
          line[offset + 8*(group_bytes-1-byte_index) +: 8];
      offset += 8 * group_bytes;
    end
    return result;
  endfunction

////////////////////////////////////////////////////////////////////////////
// model state
////////////////////////////////////////////////////////////////////////////

  model_state_t model_state       ;
  model_state_t model_state_last  ;
  logic [0:(LINE_BITS-1)] model_line;

  logic                    expect_command_valid ;
  CommandBufferLinePayload expect_command       ;
  logic                    expect_command_known ;
  logic                    expect_request_valid ;
  logic [0:63]             expect_request_addr  ;
  logic                    expect_address_known ;
  logic [0:(LINE_BITS-1)]  expect_wed           ;
  logic                    expect_wed_known     ;
  logic                    outputs_known        ;

  logic rstn_previous;
  logic rstn_reg     ;
  logic rstn_reg_last;
  logic enabled_last ;

  int unsigned cycle   ;
  logic        checking;
  string       phase   ;

  bit bin_state       [0:4];
  bit bin_transition  [0:6];
  bit bin_reset_entry [0:2];
  bit bin_pattern     [0:3];
  bit bin_delivery    [0:3];
  bit bin_block       [0:2];
  bit bin_filter      [0:3];
  bit bin_fetch_once  [0:1];
  bit bin_address     [0:2];
  bit bin_foreign     [0:1];
  bit stall_used      [0:4];

////////////////////////////////////////////////////////////////////////////
// diagnostics
////////////////////////////////////////////////////////////////////////////

  task automatic fail(input string reason);
    $error(
      "wed mismatch reason=%s phase=%s cycle=%0d state=%s",
      reason,
      phase,
      cycle,
      model_state.name()
    );
    $fatal(1);
  endtask

////////////////////////////////////////////////////////////////////////////
// model and checker
////////////////////////////////////////////////////////////////////////////

  function automatic CommandBufferLinePayload expected_command_payload(
      input logic [0:63] address
  );
    CommandBufferLinePayload payload;
    payload                      = '0;
    payload.size                 = 12'h080;
    payload.command              = READ_CL_NA;
    payload.address              = address;
    payload.cmd.cu_id_x          = WED_ID;
    payload.cmd.cu_id_y          = WED_ID;
    payload.cmd.cmd_type         = CMD_WED;
    payload.cmd.array_struct     = STRUCT_INVALID;
    payload.cmd.real_size        = 8'd32;
    payload.cmd.real_size_bytes  = 8'd128;
    payload.cmd.cacheline_offset = 8'd0;
    payload.cmd.address_offset   = 64'd0;
    payload.cmd.aux_data         = 64'd0;
    payload.cmd.size             = 12'h080;
    payload.cmd.tag              = 8'd0;
    payload.cmd.abt              = STRICT;
    payload.abt                  = STRICT;
    return payload;
  endfunction

  task automatic check_command_payload();
    checks++;
    if(command_out.payload.size !== expect_command.size)
      fail("descriptor command size");
    if(command_out.payload.command !== expect_command.command)
      fail("descriptor command code");
    if(command_out.payload.address !== expect_command.address)
      fail("descriptor command address");
    if(command_out.payload.abt !== expect_command.abt)
      fail("descriptor command bus transfer behaviour");
    if(command_out.payload.cmd.cu_id_x !== expect_command.cmd.cu_id_x ||
       command_out.payload.cmd.cu_id_y !== expect_command.cmd.cu_id_y)
      fail("descriptor command engine identifier");
    if(command_out.payload.cmd.cmd_type !== expect_command.cmd.cmd_type)
      fail("descriptor command type");
    if(command_out.payload.cmd.array_struct !== expect_command.cmd.array_struct)
      fail("descriptor command array structure");
    if(command_out.payload.cmd.real_size !== expect_command.cmd.real_size ||
       command_out.payload.cmd.real_size_bytes !== expect_command.cmd.real_size_bytes)
      fail("descriptor command size metadata");
    if(command_out.payload.cmd.cacheline_offset !== expect_command.cmd.cacheline_offset ||
       command_out.payload.cmd.address_offset !== expect_command.cmd.address_offset)
      fail("descriptor command offsets");
    if(command_out.payload.cmd.size !== expect_command.cmd.size ||
       command_out.payload.cmd.aux_data !== expect_command.cmd.aux_data)
      fail("descriptor command tag metadata");
    if(command_out.payload.cmd.tag !== expect_command.cmd.tag)
      fail("descriptor command tag");
    if(command_out.payload.cmd.abt !== expect_command.cmd.abt)
      fail("descriptor command transfer behaviour");
    // every field of the payload is driven, so the whole image must match and
    // no field may hold an unknown value
    if(command_out.payload !== expect_command)
      fail("descriptor command payload image");
  endtask

  always @(posedge clock) begin
    model_state_t next_state    ;
    logic         response_taken;
    logic         enabled_now   ;
    logic [0:(LINE_BITS-1)] actual_wed;

    rstn_reg_last = rstn_reg;
    rstn_reg      = rstn_in ? rstn_previous : 1'b0;
    enabled_now   = (rstn_reg && rstn_reg_last) ? enabled_last : 1'b0;
    cycle++;

    if(!rstn_reg) begin
      if(model_state != MODEL_RESET)
        bin_reset_entry[
          model_state == MODEL_IDLE ? 0 :
          model_state == MODEL_WAITING ? 1 : 2
        ] = 1;
      model_state = MODEL_RESET;
    end

    // -------------------------------------------------------------------
    // compare the outputs published in this cycle
    // -------------------------------------------------------------------
    if(checking && outputs_known) begin
      checks++;
      if(command_out.valid !== expect_command_valid)
        fail("descriptor command request");
      checks++;
      if(wed_request_out.valid !== expect_request_valid)
        fail("descriptor publication");
      if(expect_command_known)
        check_command_payload();
      if(expect_address_known) begin
        checks++;
        if(wed_request_out.payload.address !== expect_request_addr)
          fail("descriptor source address");
      end
      if(expect_wed_known) begin
        checks++;
        actual_wed = wed_request_out.payload.wed;
        if(actual_wed !== expect_wed)
          fail("descriptor byte decode");
      end
    end

    // -------------------------------------------------------------------
    // outputs that this cycle produces for the next cycle
    // -------------------------------------------------------------------
    case (model_state)
      MODEL_RESET : begin
        expect_command_valid = 1'b0;
        expect_request_valid = 1'b0;
        model_line           = '0;
        expect_command       = '0;
        expect_command_known = 1'b1;
        expect_request_addr  = 64'h0;
        expect_address_known = 1'b1;
        expect_wed           = '0;
        expect_wed_known     = 1'b1;
        outputs_known        = 1'b1;
      end
      MODEL_IDLE : begin
        expect_command_valid = 1'b0;
      end
      MODEL_REQUEST : begin
        expect_command_valid = 1'b1;
        expect_command       = expected_command_payload(wed_address);
        expect_command_known = 1'b1;
        expect_request_addr  = wed_address;
        expect_address_known = 1'b1;
      end
      MODEL_WAITING : begin
        expect_command_valid = 1'b0;
        if(wed_data_0_in.payload.cmd.cu_id_x == WED_ID)
          model_line[0:(HALF_BITS-1)] = wed_data_0_in.payload.data;
        if(wed_data_1_in.payload.cmd.cu_id_x == WED_ID)
          model_line[HALF_BITS:(LINE_BITS-1)] = wed_data_1_in.payload.data;
      end
      MODEL_PUBLISH : begin
        expect_request_valid = 1'b1;
        expect_wed           = wed_decode(model_line);
        expect_wed_known     = 1'b1;
      end
    endcase

    // -------------------------------------------------------------------
    // transition
    // -------------------------------------------------------------------
    response_taken = wed_response_in.valid &&
      (wed_response_in.payload.cmd.cu_id_x == WED_ID) &&
      (wed_response_in.payload.response == DONE);

    next_state = model_state;
    case (model_state)
      MODEL_RESET : begin
        next_state = MODEL_IDLE;
      end
      MODEL_IDLE : begin
        if(enabled_now && !wed_request_out.valid && !command_buffer_status.alfull)
          next_state = MODEL_REQUEST;
      end
      MODEL_REQUEST : begin
        next_state = MODEL_WAITING;
      end
      MODEL_WAITING : begin
        if(response_taken)
          next_state = MODEL_PUBLISH;
      end
      MODEL_PUBLISH : begin
        next_state = MODEL_IDLE;
      end
    endcase

    if(checking) begin
      bin_state[int'(model_state)] = 1;
      case (model_state)
        MODEL_RESET : bin_transition[0] = 1;
        MODEL_IDLE : begin
          if(next_state == MODEL_IDLE)
            bin_transition[1] = 1;
          else
            bin_transition[2] = 1;
        end
        MODEL_REQUEST : bin_transition[3] = 1;
        MODEL_WAITING : begin
          if(next_state == MODEL_WAITING)
            bin_transition[4] = 1;
          else
            bin_transition[5] = 1;
        end
        MODEL_PUBLISH : bin_transition[6] = 1;
      endcase
      if(model_state == MODEL_WAITING && wed_response_in.valid && !response_taken)
        bin_filter[
          (wed_response_in.payload.cmd.cu_id_x != WED_ID) ? 0 : 1
        ] = 1;
      if(model_state == MODEL_WAITING && !wed_response_in.valid &&
         (wed_data_0_in.valid || wed_data_1_in.valid))
        bin_filter[2] = 1;
      if(model_state == MODEL_WAITING && response_taken)
        bin_filter[3] = 1;
      if(model_state == MODEL_IDLE && next_state == MODEL_IDLE) begin
        if(wed_request_out.valid)
          bin_fetch_once[0] = 1;
        else if(!enabled_now)
          bin_block[1] = 1;
        else if(command_buffer_status.alfull)
          bin_block[0] = 1;
        if(!enabled_now && command_buffer_status.alfull)
          bin_block[2] = 1;
      end
    end

    model_state_last = model_state;
    model_state      = rstn_reg ? next_state : MODEL_RESET;

    rstn_previous = rstn_in;
    enabled_last  = enabled_in;
  end

////////////////////////////////////////////////////////////////////////////
// stimulus
////////////////////////////////////////////////////////////////////////////

  task automatic step(input int unsigned count);
    for(int unsigned index = 0; index < count; index++)
      @(negedge clock);
  endtask

  task automatic wait_for_state(input model_state_t target);
    int unsigned guard;
    guard = 0;
    while(model_state != target) begin
      step(1);
      guard++;
      if(guard > PROGRESS_BOUND) begin
        $error(
          "wed progress bound exceeded phase=%s waiting=%s state=%s",
          phase,
          target.name(),
          model_state.name()
        );
        $fatal(1);
      end
    end
  endtask

  function automatic logic [0:(HALF_BITS-1)] byte_index_pattern(
      input logic [0:7] base
  );
    logic [0:(HALF_BITS-1)] value;
    for(int unsigned index = 0; index < 64; index++)
      value[8*index +: 8] = base + 8'(index);
    return value;
  endfunction

  task automatic clear_data_lines();
    wed_data_0_in = '0;
    wed_data_1_in = '0;
  endtask

  task automatic deliver_half(
      input logic                   half   ,
      input logic [0:(HALF_BITS-1)] data   ,
      input logic [0:7]             cu_id
  );
    if(!half) begin
      wed_data_0_in.valid               = 1'b1;
      wed_data_0_in.payload.cmd         = '0;
      wed_data_0_in.payload.cmd.cu_id_x = cu_id;
      wed_data_0_in.payload.cmd.cmd_type = CMD_WED;
      wed_data_0_in.payload.data        = data;
    end else begin
      wed_data_1_in.valid               = 1'b1;
      wed_data_1_in.payload.cmd         = '0;
      wed_data_1_in.payload.cmd.cu_id_x = cu_id;
      wed_data_1_in.payload.cmd.cmd_type = CMD_WED;
      wed_data_1_in.payload.data        = data;
    end
  endtask

  task automatic send_response(input logic [0:7] cu_id, input psl_response_t code);
    wed_response_in                      = '0;
    wed_response_in.valid                = 1'b1;
    wed_response_in.payload.cmd.cu_id_x  = cu_id;
    wed_response_in.payload.cmd.cmd_type = CMD_WED;
    wed_response_in.payload.cmd.tag      = 8'h00;
    wed_response_in.payload.response     = code;
    step(1);
    wed_response_in = '0;
  endtask

  task automatic reset_pulse(input int unsigned low_cycles);
    rstn_in = 1'b0;
    step(low_cycles);
    rstn_in = 1'b1;
    step(DRAIN_CYCLES);
  endtask

  task automatic check_bins();
    bin_hits = 0;
    for(int index = 0; index < 5; index++) begin
      if(!bin_state[index])
        $fatal(1, "wed missing state bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 7; index++) begin
      if(!bin_transition[index])
        $fatal(1, "wed missing transition bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_reset_entry[index])
        $fatal(1, "wed missing reset entry bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 4; index++) begin
      if(!bin_pattern[index])
        $fatal(1, "wed missing descriptor pattern bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 4; index++) begin
      if(!bin_delivery[index])
        $fatal(1, "wed missing half delivery bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_block[index])
        $fatal(1, "wed missing request block bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 4; index++) begin
      if(!bin_filter[index])
        $fatal(1, "wed missing response filter bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 2; index++) begin
      if(!bin_fetch_once[index])
        $fatal(1, "wed missing fetch once bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_address[index])
        $fatal(1, "wed missing address bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 2; index++) begin
      if(!bin_foreign[index])
        $fatal(1, "wed missing foreign identifier bin %0d", index);
      bin_hits++;
    end
    stalls = 0;
    for(int index = 0; index < STALL_PROFILES; index++) begin
      if(!stall_used[index])
        $fatal(1, "wed missing stall profile %0d", index);
      stalls++;
    end
  endtask

  initial begin
    logic [0:(HALF_BITS-1)] low_half ;
    logic [0:(HALF_BITS-1)] high_half;

    finished              = 1'b0;
    bin_hits              = 0;
    stalls                = 0;
    cycle                 = 0;
    checking              = 1'b0;
    phase                 = "reset";
    rstn_in               = 1'b0;
    enabled_in            = 1'b0;
    wed_address           = 64'h0;
    wed_data_0_in         = '0;
    wed_data_1_in         = '0;
    wed_response_in       = '0;
    command_buffer_status = '0;
    model_state           = MODEL_RESET;
    model_state_last      = MODEL_RESET;
    model_line            = '0;
    expect_command_valid  = 1'b0;
    expect_command_known  = 1'b0;
    expect_request_valid  = 1'b0;
    expect_address_known  = 1'b0;
    expect_wed_known      = 1'b0;
    outputs_known         = 1'b0;
    rstn_previous         = 1'b0;
    rstn_reg              = 1'b0;
    rstn_reg_last         = 1'b0;
    enabled_last          = 1'b0;

    if($bits(WED_request) != LINE_BITS)
      $fatal(1, "wed descriptor width contract changed: %0d", $bits(WED_request));

    step(4);
    rstn_in = 1'b1;
    step(DRAIN_CYCLES);
    checking = 1'b1;

    // ---------------------------------------------------------------------
    phase                        = "blocked-by-almost-full";
    command_buffer_status.alfull = 1'b1;
    enabled_in                   = 1'b1;
    step(STALL_ALFULL_HOLD);
    stall_used[0] = 1;

    phase                        = "blocked-by-disable";
    enabled_in                   = 1'b0;
    step(STALL_DISABLED_HOLD);
    stall_used[1] = 1;
    command_buffer_status.alfull = 1'b0;
    step(2);
    enabled_in = 1'b1;

    // ---------------------------------------------------------------------
    phase       = "byte-index-descriptor";
    wed_address = 64'h0000_0000_0000_0000;
    bin_address[0] = 1;
    wait_for_state(MODEL_WAITING);
    low_half  = byte_index_pattern(8'h00);
    high_half = byte_index_pattern(8'h40);
    deliver_half(1'b0, low_half, WED_ID);
    step(1);
    clear_data_lines();
    step(STALL_HALF_GAP);
    stall_used[3] = 1;
    deliver_half(1'b1, high_half, WED_ID);
    step(1);
    clear_data_lines();
    bin_delivery[0] = 1;
    bin_pattern[0]  = 1;
    step(STALL_RESPONSE_WAIT);
    stall_used[2] = 1;
    send_response(WED_ID, DONE);
    step(DRAIN_CYCLES);

    phase = "fetch-once-hold";
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "repeat-job-high-half-first";
    wed_address    = 64'hFFFF_FFFF_FFFF_FFF8;
    bin_address[1] = 1;
    reset_pulse(STALL_RESET_LOW);
    stall_used[4]  = 1;
    bin_fetch_once[1] = 1;
    wait_for_state(MODEL_WAITING);
    low_half  = {HALF_BITS{1'b1}};
    high_half = {HALF_BITS{1'b0}};
    deliver_half(1'b1, high_half, WED_ID);
    step(1);
    clear_data_lines();
    step(2);
    deliver_half(1'b0, low_half, WED_ID);
    step(1);
    clear_data_lines();
    bin_delivery[1] = 1;
    bin_pattern[1]  = 1;
    send_response(WED_ID, DONE);
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "simultaneous-halves-and-filtered-responses";
    wed_address    = 64'h0123_4567_89AB_CDE0;
    bin_address[2] = 1;
    reset_pulse(STALL_RESET_LOW);
    wait_for_state(MODEL_WAITING);
    low_half  = byte_index_pattern(8'h81);
    high_half = byte_index_pattern(8'hC1);
    deliver_half(1'b0, low_half, WED_ID);
    deliver_half(1'b1, high_half, WED_ID);
    step(1);
    clear_data_lines();
    bin_delivery[2] = 1;
    bin_pattern[3]  = 1;
    send_response(RESTART_ID, DONE);
    step(2);
    send_response(WED_ID, FLUSHED);
    step(2);
    deliver_half(1'b0, {HALF_BITS{1'b1}}, RESTART_ID);
    deliver_half(1'b1, {HALF_BITS{1'b1}}, INVALID_ID);
    step(1);
    clear_data_lines();
    bin_foreign[0] = 1;
    bin_foreign[1] = 1;
    step(2);
    send_response(WED_ID, DONE);
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase       = "reset-while-waiting-for-response";
    wed_address = 64'h0000_0000_DEAD_BEE0;
    reset_pulse(STALL_RESET_LOW);
    wait_for_state(MODEL_WAITING);
    deliver_half(1'b0, byte_index_pattern(8'h11), WED_ID);
    step(1);
    clear_data_lines();
    rstn_in = 1'b0;
    step(STALL_RESET_LOW);
    rstn_in = 1'b1;
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase       = "reset-while-publishing";
    wed_address = 64'h0000_0000_0BAD_F00D;
    reset_pulse(STALL_RESET_LOW);
    wait_for_state(MODEL_WAITING);
    deliver_half(1'b0, byte_index_pattern(8'h31), WED_ID);
    deliver_half(1'b1, byte_index_pattern(8'h71), WED_ID);
    step(1);
    clear_data_lines();
    send_response(WED_ID, DONE);
    rstn_in = 1'b0;
    step(STALL_RESET_LOW);
    rstn_in = 1'b1;
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase                        = "interface-boundary-sweep";
    wed_address                  = 64'h5555_5555_5555_5555;
    command_buffer_status.full   = 1'b1;
    command_buffer_status.valid  = 1'b1;
    command_buffer_status.empty  = 1'b1;
    step(4);
    wed_address                  = 64'hAAAA_AAAA_AAAA_AAAA;
    command_buffer_status.full   = 1'b0;
    command_buffer_status.valid  = 1'b0;
    command_buffer_status.empty  = 1'b0;
    step(4);

    // ---------------------------------------------------------------------
    phase       = "partial-delivery";
    wed_address = 64'h0000_0000_0000_1000;
    reset_pulse(STALL_RESET_LOW);
    wait_for_state(MODEL_WAITING);
    deliver_half(1'b0, byte_index_pattern(8'h20), WED_ID);
    step(1);
    clear_data_lines();
    bin_delivery[3] = 1;
    bin_pattern[2]  = 1;
    send_response(WED_ID, DONE);
    step(DRAIN_CYCLES);

    check_bins();
    checking = 1'b0;
    finished = 1'b1;
  end

endmodule
