// write-data family: write_data_control.sv
//
// Independent model: a byte addressable half line store plus an address/mask
// and latency contract model. The model owns a tag indexed memory for each
// cacheline half, reproduces the buffer read latency contract published by the
// DUT and recomputes the eight doubleword parity lanes by counting ones.
//
// Sampling contract, cycle c is the interval closed by the posedge that samples
// it:
//   * a compute unit write beat at cycle T is visible to a buffer read request
//     from cycle T+2.
//   * a buffer read request at cycle R returns data and parity at cycle R+3,
//     which is the read_latency the DUT publishes to the PSL.
//   * a buffer read address outside the two cacheline halves holds the
//     previously selected data.
//   * a buffer read request at cycle R reports its tag parity at cycle R+4.

import GLOBALS_AFU_PKG::*;
import CAPI_PKG::*;
import AFU_PKG::*;
import CU_PKG::*;

module write_data_control_tb (
  input  logic        clock   ,
  output logic        finished,
  output int unsigned checks  ,
  output int unsigned bin_hits,
  output int unsigned stalls
);

  localparam int unsigned HALF_BITS  = CACHELINE_SIZE_BITS_HF;
  localparam int unsigned HIST_DEPTH = 6                     ;
  localparam int unsigned LOOKUP_DEPTH = 4                   ;

  // Named bounded stall profiles.
  localparam int unsigned STALL_REQUEST_GAP_SHORT = 1;
  localparam int unsigned STALL_REQUEST_GAP_LONG  = 8;
  localparam int unsigned STALL_WRITE_DELAY       = 12;
  localparam int unsigned STALL_ENABLE_LOW        = 4;
  localparam int unsigned STALL_RESET_LOW         = 6;
  localparam int unsigned STALL_PROFILES          = 5;
  localparam int unsigned DRAIN_CYCLES            = 8;

  localparam int unsigned REQUEST_GAP_COMMITTED = 2;
  localparam int unsigned REQUEST_GAP_PRECOMMIT = 1;
  localparam logic [0:3]  READ_LATENCY_CONTRACT = 4'h3;

  logic                     rstn_in         ;
  logic                     enabled_in      ;
  WriteDataControlInterface buffer_in       ;
  logic [0:7]               command_tag_in  ;
  ReadWriteDataLine         write_data_0_in ;
  ReadWriteDataLine         write_data_1_in ;
  logic                     data_write_error;
  BufferInterfaceOutput     buffer_out      ;

  write_data_control dut (
    .clock           (clock           ),
    .rstn_in         (rstn_in         ),
    .enabled_in      (enabled_in      ),
    .buffer_in       (buffer_in       ),
    .command_tag_in  (command_tag_in  ),
    .write_data_0_in (write_data_0_in ),
    .write_data_1_in (write_data_1_in ),
    .data_write_error(data_write_error),
    .buffer_out      (buffer_out      )
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
    logic                   valid;
    logic [0:(HALF_BITS-1)] data ;
  } wbeat_t;

  typedef struct packed {
    logic       valid       ;
    logic [0:7] tag         ;
    logic [0:5] address     ;
    logic       parity_fault;
  } rreq_t;

  typedef struct packed {
    logic                   enabled_in  ;
    logic                   rstn_in     ;
    logic                   rstn_reg    ;
    logic                   en_reg      ;
    logic                   w0_valid    ;
    logic                   w1_valid    ;
    logic [0:(HALF_BITS-1)] w0_data     ;
    logic [0:(HALF_BITS-1)] w1_data     ;
    logic [0:7]             command_tag ;
    logic                   req_valid   ;
    logic [0:7]             req_tag     ;
    logic                   req_parity  ;
    logic [0:5]             req_address ;
  } snapshot_t;

  snapshot_t hist [0:HIST_DEPTH-1];

  logic [0:(HALF_BITS-1)] model_memory [0:1][0:255];
  logic [0:(HALF_BITS-1)] model_write_data          ;

  logic                   lookup_valid [0:LOOKUP_DEPTH-1];
  logic [0:(HALF_BITS-1)] lookup_data  [0:LOOKUP_DEPTH-1];

  int unsigned cycle   ;
  logic        checking;
  string       phase   ;

  bit bin_lane_parity   [0:7][0:1];
  bit bin_lane_isolated [0:7]     ;
  bit bin_address       [0:3]     ;
  bit bin_timing        [0:2]     ;
  bit bin_tag           [0:3]     ;
  bit bin_half_valid    [0:2]     ;
  bit bin_parity        [0:1]     ;
  bit bin_gap           [0:2]     ;
  bit bin_control       [0:2]     ;
  bit stall_used        [0:4]     ;

////////////////////////////////////////////////////////////////////////////
// diagnostics
////////////////////////////////////////////////////////////////////////////

  task automatic fail(input string reason);
    $error(
      "write_data mismatch reason=%s phase=%s cycle=%0d",
      reason,
      phase,
      cycle
    );
    $fatal(1);
  endtask

////////////////////////////////////////////////////////////////////////////
// stimulus helpers
////////////////////////////////////////////////////////////////////////////

  function automatic logic [0:63] lane_value(
      input logic [0:7]  tag     ,
      input logic [0:7]  salt    ,
      input logic        half    ,
      input int unsigned lane    ,
      input logic        want_odd
  );
    logic [0:63] value;
    value = {tag, salt, 7'h00, half, 8'(lane), 32'hA5A5_0000 ^ (32'(lane) << 8)};
    if((($countones(value) % 2) == 1) != want_odd)
      value[63] = ~value[63];
    return value;
  endfunction

  function automatic logic [0:(HALF_BITS-1)] make_line(
      input logic [0:7] tag     ,
      input logic [0:7] salt    ,
      input logic       half    ,
      input logic [0:7] odd_mask
  );
    logic [0:(HALF_BITS-1)] line;
    for(int unsigned lane = 0; lane < 8; lane++)
      line[64*lane +: 64] = lane_value(tag, salt, half, lane, odd_mask[lane]);
    return line;
  endfunction

  function automatic CommandTagLine make_cmd(input logic [0:7] tag, input logic [0:7] salt);
    CommandTagLine cmd;
    cmd                  = '0;
    cmd.cu_id_x          = salt;
    cmd.cu_id_y          = ~salt;
    cmd.array_struct     = array_struct_type'(2);
    cmd.cmd_type         = CMD_WRITE;
    cmd.real_size        = 8'h20;
    cmd.real_size_bytes  = 8'h80;
    cmd.cacheline_offset = salt;
    cmd.address_offset   = {56'h0, tag};
    cmd.size             = 12'h080;
    cmd.tag              = tag;
    cmd.abt              = STRICT;
    return cmd;
  endfunction

  function automatic wbeat_t idle_write();
    wbeat_t beat;
    beat = '0;
    return beat;
  endfunction

  function automatic wbeat_t make_write(input logic [0:(HALF_BITS-1)] data);
    wbeat_t beat;
    beat.valid = 1'b1;
    beat.data  = data;
    return beat;
  endfunction

  function automatic rreq_t idle_request();
    rreq_t request;
    request = '0;
    return request;
  endfunction

  function automatic rreq_t make_request(
      input logic [0:7] tag         ,
      input logic [0:5] address     ,
      input logic       parity_fault
  );
    rreq_t request;
    request.valid        = 1'b1;
    request.tag          = tag;
    request.address      = address;
    request.parity_fault = parity_fault;
    return request;
  endfunction

  task automatic drive(
      input wbeat_t     write_0   ,
      input wbeat_t     write_1   ,
      input logic [0:7] command_tag,
      input rreq_t      request
  );
    @(negedge clock);

    write_data_0_in.valid        = write_0.valid;
    write_data_0_in.payload.cmd  = make_cmd(command_tag, 8'h10);
    write_data_0_in.payload.data = write_0.data;

    write_data_1_in.valid        = write_1.valid;
    write_data_1_in.payload.cmd  = make_cmd(command_tag, 8'h11);
    write_data_1_in.payload.data = write_1.data;

    command_tag_in = command_tag;

    buffer_in.read_valid      = request.valid;
    buffer_in.read_tag        = request.tag;
    buffer_in.read_tag_parity =
      odd_parity_of({56'h0, request.tag}) ^ request.parity_fault;
    buffer_in.read_address    = request.address;
  endtask

  task automatic idle_cycles(input int unsigned count);
    for(int unsigned index = 0; index < count; index++)
      drive(idle_write(), idle_write(), 8'h00, idle_request());
  endtask

////////////////////////////////////////////////////////////////////////////
// model and checker
////////////////////////////////////////////////////////////////////////////

  always @(posedge clock) begin
    snapshot_t              snapshot     ;
    logic [0:(HALF_BITS-1)] expect_data  ;
    logic [0:7]             expect_parity;
    logic                   expect_error ;
    logic                   in_reset     ;
    int unsigned            odd_lanes    ;
    int unsigned            odd_lane     ;

    for(int index = HIST_DEPTH-1; index > 0; index--)
      hist[index] = hist[index-1];

    snapshot             = '0;
    snapshot.enabled_in  = enabled_in;
    snapshot.rstn_in     = rstn_in;
    snapshot.rstn_reg    = rstn_in ? hist[1].rstn_in : 1'b0;
    snapshot.en_reg      = (rstn_in && hist[1].rstn_in) ? hist[1].enabled_in : 1'b0;
    snapshot.w0_valid    = write_data_0_in.valid;
    snapshot.w1_valid    = write_data_1_in.valid;
    snapshot.w0_data     = write_data_0_in.payload.data;
    snapshot.w1_data     = write_data_1_in.payload.data;
    snapshot.command_tag = command_tag_in;
    snapshot.req_valid   = buffer_in.read_valid;
    snapshot.req_tag     = buffer_in.read_tag;
    snapshot.req_parity  = buffer_in.read_tag_parity;
    snapshot.req_address = buffer_in.read_address;
    hist[0]              = snapshot;
    cycle++;

    // a compute unit beat at cycle c-2 is visible to a lookup issued now
    if(hist[2].en_reg) begin
      if(hist[2].w0_valid)
        model_memory[0][hist[2].command_tag] = hist[2].w0_data;
      if(hist[2].w1_valid)
        model_memory[1][hist[2].command_tag] = hist[2].w1_data;
    end

    // a register with an asynchronous reset also publishes its reset value in
    // the cycle after the release, because the clock edge that closes the
    // release cycle still samples the reset level
    in_reset = (!hist[0].rstn_reg) || (!hist[1].rstn_reg);
    if(in_reset) begin
      expect_data   = {HALF_BITS{1'b1}};
      expect_parity = 8'h01;
    end else begin
      expect_data   = model_write_data;
      expect_parity = dw_odd_parity(model_write_data);
    end

    if(checking) begin
      checks++;
      if(buffer_out.read_latency !== READ_LATENCY_CONTRACT)
        fail("published read latency contract");
      bin_control[2] = 1;

      checks++;
      if(buffer_out.read_data !== expect_data)
        fail("buffer read data");

      checks++;
      if(buffer_out.read_parity !== expect_parity)
        fail("buffer read parity lanes");

      odd_lanes = 0;
      odd_lane  = 0;
      for(int unsigned lane = 0; lane < 8; lane++) begin
        bin_lane_parity[lane][expect_parity[lane]] = 1;
        if(!expect_parity[lane]) begin
          odd_lanes++;
          odd_lane = lane;
        end
      end
      if(odd_lanes == 1)
        bin_lane_isolated[odd_lane] = 1;

      expect_error = 1'b0;
      if(hist[4].req_valid && hist[4].en_reg)
        expect_error = odd_parity_of({56'h0, hist[4].req_tag}) ^ hist[4].req_parity;
      checks++;
      if(data_write_error !== expect_error)
        fail($sformatf(
          "tag parity report expected=%0b actual=%0b",
          expect_error,
          data_write_error
        ));
      if(hist[4].req_valid && hist[4].en_reg)
        bin_parity[expect_error] = 1;
    end

    if(in_reset) begin
      model_write_data = {HALF_BITS{1'b1}};
      for(int index = 0; index < LOOKUP_DEPTH; index++)
        lookup_valid[index] = 1'b0;
    end else if(lookup_valid[0]) begin
      model_write_data = lookup_data[0];
    end

    if(hist[0].req_valid && hist[0].en_reg) begin
      if(hist[0].req_address == 6'h00 || hist[0].req_address == 6'h01) begin
        lookup_valid[2] = 1'b1;
        lookup_data[2]  = model_memory[hist[0].req_address[5]][hist[0].req_tag];
      end
      if(checking) begin
        bin_address[
          hist[0].req_address == 6'h00 ? 0 :
          hist[0].req_address == 6'h01 ? 1 :
          hist[0].req_address == 6'h02 ? 2 : 3
        ] = 1;
        bin_tag[
          hist[0].req_tag == 8'h00 ? 0 :
          hist[0].req_tag == 8'h01 ? 1 :
          hist[0].req_tag == 8'h7F ? 2 : 3
        ] = 1;
      end
    end

    for(int index = 0; index < LOOKUP_DEPTH-1; index++) begin
      lookup_valid[index] = lookup_valid[index+1];
      lookup_data[index]  = lookup_data[index+1];
    end
    lookup_valid[LOOKUP_DEPTH-1] = 1'b0;
    lookup_data[LOOKUP_DEPTH-1]  = '0;
  end

////////////////////////////////////////////////////////////////////////////
// scenarios
////////////////////////////////////////////////////////////////////////////

  task automatic store_cacheline(
      input logic [0:7] tag         ,
      input logic [0:7] salt        ,
      input logic [0:7] odd_mask_low,
      input logic [0:7] odd_mask_high,
      input logic       write_low   ,
      input logic       write_high
  );
    drive(
      write_low ? make_write(make_line(tag, salt, 1'b0, odd_mask_low)) : idle_write(),
      write_high ? make_write(make_line(tag, salt, 1'b1, odd_mask_high)) : idle_write(),
      tag,
      idle_request()
    );
    bin_half_valid[(write_low && write_high) ? 0 : (write_low ? 1 : 2)] = 1;
  endtask

  task automatic request_half(input logic [0:7] tag, input logic [0:5] address);
    drive(idle_write(), idle_write(), 8'h00, make_request(tag, address, 1'b0));
    idle_cycles(DRAIN_CYCLES);
  endtask

  task automatic check_bins();
    bin_hits = 0;
    for(int lane = 0; lane < 8; lane++)
      for(int class_index = 0; class_index < 2; class_index++) begin
        if(!bin_lane_parity[lane][class_index])
          $fatal(1, "write_data missing lane %0d parity class %0d", lane, class_index);
        bin_hits++;
      end
    for(int lane = 0; lane < 8; lane++) begin
      if(!bin_lane_isolated[lane])
        $fatal(1, "write_data missing isolated lane bin %0d", lane);
      bin_hits++;
    end
    for(int index = 0; index < 4; index++) begin
      if(!bin_address[index])
        $fatal(1, "write_data missing address bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_timing[index])
        $fatal(1, "write_data missing timing bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 4; index++) begin
      if(!bin_tag[index])
        $fatal(1, "write_data missing tag bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_half_valid[index])
        $fatal(1, "write_data missing half valid bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 2; index++) begin
      if(!bin_parity[index])
        $fatal(1, "write_data missing parity bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_gap[index])
        $fatal(1, "write_data missing request gap bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_control[index])
        $fatal(1, "write_data missing control bin %0d", index);
      bin_hits++;
    end
    stalls = 0;
    for(int index = 0; index < STALL_PROFILES; index++) begin
      if(!stall_used[index])
        $fatal(1, "write_data missing stall profile %0d", index);
      stalls++;
    end
  endtask

  initial begin
    logic [0:7] tags [0:3];

    finished         = 1'b0;
    bin_hits         = 0;
    stalls           = 0;
    cycle            = 0;
    checking         = 1'b0;
    phase            = "reset";
    rstn_in          = 1'b0;
    enabled_in       = 1'b0;
    buffer_in        = '0;
    command_tag_in   = '0;
    write_data_0_in  = '0;
    write_data_1_in  = '0;
    model_write_data = {HALF_BITS{1'b1}};
    foreach(hist[index]) hist[index] = '0;
    for(int index = 0; index < LOOKUP_DEPTH; index++) begin
      lookup_valid[index] = 1'b0;
      lookup_data[index]  = '0;
    end
    for(int half = 0; half < 2; half++)
      for(int tag = 0; tag < 256; tag++)
        model_memory[half][tag] = '0;

    idle_cycles(4);
    rstn_in    = 1'b1;
    enabled_in = 1'b1;
    idle_cycles(DRAIN_CYCLES);
    checking = 1'b1;

    // ---------------------------------------------------------------------
    phase = "store-and-return-both-halves";
    store_cacheline(8'h01, 8'h01, 8'hFF, 8'h00, 1'b1, 1'b1);
    idle_cycles(REQUEST_GAP_COMMITTED - 1);
    bin_timing[0] = 1;
    request_half(8'h01, 6'h00);
    request_half(8'h01, 6'h01);

    // ---------------------------------------------------------------------
    phase = "request-before-commit";
    store_cacheline(8'h7F, 8'h22, 8'h0F, 8'hF0, 1'b1, 1'b1);
    idle_cycles(REQUEST_GAP_PRECOMMIT - 1);
    bin_timing[1] = 1;
    request_half(8'h7F, 6'h00);
    request_half(8'h7F, 6'h00);

    // ---------------------------------------------------------------------
    phase = "unmapped-buffer-address";
    store_cacheline(8'h00, 8'h33, 8'hAA, 8'h55, 1'b1, 1'b1);
    idle_cycles(DRAIN_CYCLES);
    request_half(8'h00, 6'h02);
    request_half(8'h00, 6'h3F);

    // ---------------------------------------------------------------------
    phase = "isolated-lane-sweep";
    for(int unsigned lane = 0; lane < 8; lane++) begin
      store_cacheline(
        8'hFF,
        8'h40 + 8'(lane),
        8'(1 << (7 - lane)),
        8'hFF,
        1'b1,
        1'b1
      );
      idle_cycles(DRAIN_CYCLES);
      request_half(8'hFF, 6'h00);
    end

    // ---------------------------------------------------------------------
    phase   = "tag-association";
    tags[0] = 8'h00;
    tags[1] = 8'h01;
    tags[2] = 8'h7F;
    tags[3] = 8'hFF;
    for(int index = 0; index < 4; index++)
      store_cacheline(
        tags[index],
        8'h50 + 8'(index),
        8'h81,
        8'h18,
        1'b1,
        1'b1
      );
    idle_cycles(DRAIN_CYCLES);
    for(int index = 3; index >= 0; index--) begin
      request_half(tags[index], 6'h00);
      request_half(tags[index], 6'h01);
    end

    // ---------------------------------------------------------------------
    phase = "half-valid-asymmetry";
    store_cacheline(8'h60, 8'h60, 8'hC3, 8'h00, 1'b1, 1'b0);
    idle_cycles(DRAIN_CYCLES);
    request_half(8'h60, 6'h00);
    request_half(8'h60, 6'h01);
    store_cacheline(8'h61, 8'h61, 8'h00, 8'h3C, 1'b0, 1'b1);
    idle_cycles(DRAIN_CYCLES);
    request_half(8'h61, 6'h01);
    request_half(8'h61, 6'h00);

    // ---------------------------------------------------------------------
    phase = "back-to-back-requests";
    store_cacheline(8'h70, 8'h70, 8'h11, 8'hEE, 1'b1, 1'b1);
    store_cacheline(8'h71, 8'h71, 8'h22, 8'hDD, 1'b1, 1'b1);
    idle_cycles(DRAIN_CYCLES);
    drive(idle_write(), idle_write(), 8'h00, make_request(8'h70, 6'h00, 1'b0));
    drive(idle_write(), idle_write(), 8'h00, make_request(8'h70, 6'h01, 1'b0));
    drive(idle_write(), idle_write(), 8'h00, make_request(8'h71, 6'h00, 1'b0));
    drive(idle_write(), idle_write(), 8'h00, make_request(8'h71, 6'h01, 1'b0));
    bin_gap[0] = 1;
    idle_cycles(DRAIN_CYCLES);

    drive(idle_write(), idle_write(), 8'h00, make_request(8'h70, 6'h00, 1'b0));
    idle_cycles(STALL_REQUEST_GAP_SHORT);
    drive(idle_write(), idle_write(), 8'h00, make_request(8'h71, 6'h01, 1'b0));
    bin_gap[1]    = 1;
    stall_used[0] = 1;
    idle_cycles(DRAIN_CYCLES);

    drive(idle_write(), idle_write(), 8'h00, make_request(8'h70, 6'h01, 1'b0));
    idle_cycles(STALL_REQUEST_GAP_LONG);
    drive(idle_write(), idle_write(), 8'h00, make_request(8'h71, 6'h00, 1'b0));
    bin_gap[2]    = 1;
    stall_used[1] = 1;
    idle_cycles(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "concurrent-store-and-request";
    drive(
      make_write(make_line(8'h80, 8'h80, 1'b0, 8'h5A)),
      make_write(make_line(8'h80, 8'h80, 1'b1, 8'hA5)),
      8'h80,
      make_request(8'h70, 6'h00, 1'b0)
    );
    idle_cycles(STALL_WRITE_DELAY);
    stall_used[2] = 1;
    bin_timing[2] = 1;
    request_half(8'h80, 6'h00);
    request_half(8'h80, 6'h01);

    // ---------------------------------------------------------------------
    phase = "tag-parity-fault";
    drive(idle_write(), idle_write(), 8'h00, make_request(8'h7F, 6'h00, 1'b1));
    idle_cycles(DRAIN_CYCLES);
    drive(idle_write(), idle_write(), 8'h00, make_request(8'h7F, 6'h00, 1'b0));
    idle_cycles(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase      = "disabled-window";
    enabled_in = 1'b0;
    idle_cycles(2);
    for(int index = 0; index < STALL_ENABLE_LOW; index++)
      drive(
        make_write(make_line(8'h90, 8'h90, 1'b0, 8'hFF)),
        make_write(make_line(8'h90, 8'h90, 1'b1, 8'hFF)),
        8'h90,
        make_request(8'h01, 6'h00, 1'b0)
      );
    stall_used[3] = 1;
    idle_cycles(2);
    enabled_in = 1'b1;
    idle_cycles(DRAIN_CYCLES);
    request_half(8'h90, 6'h00);
    bin_control[0] = 1;

    // ---------------------------------------------------------------------
    phase   = "reset-window";
    rstn_in = 1'b0;
    idle_cycles(STALL_RESET_LOW);
    stall_used[4] = 1;
    rstn_in       = 1'b1;
    idle_cycles(DRAIN_CYCLES);
    bin_control[1] = 1;
    request_half(8'h01, 6'h00);

    check_bins();
    checking = 1'b0;
    finished = 1'b1;
  end

endmodule
