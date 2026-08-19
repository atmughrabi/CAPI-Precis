// mmio family: mmio.sv
//
// Independent model: a register and descriptor map that is written from the
// documented address map, not from the DUT decoder. The model owns the sticky
// read data register, the pulse semantics of the configuration and
// acknowledge registers, the AFU descriptor table and an independent odd
// parity reference.
//
// Sampling contract, cycle c is the interval closed by the posedge that samples
// it and a request is presented at cycle T:
//   * the selected read data is formed at cycle T+4 from the status inputs
//     sampled at cycle T+2.
//   * configuration and acknowledge registers pulse at cycle T+4 and reach the
//     module outputs at cycle T+5.
//   * the MMIO acknowledge, data, data parity and parity error report reach the
//     module outputs at cycle T+6.

import GLOBALS_AFU_PKG::*;
import CAPI_PKG::*;
import AFU_PKG::*;
import CU_PKG::*;

module mmio_tb (
  input  logic        clock   ,
  output logic        finished,
  output int unsigned checks  ,
  output int unsigned bin_hits,
  output int unsigned stalls
);

  localparam int unsigned HIST_DEPTH     = 8 ;
  localparam int unsigned READ_REGISTERS = 26;
  localparam int unsigned WRITE_REGISTERS = 8;
  localparam int unsigned DESCRIPTOR_WORDS = 10;

  // Named bounded stall profiles.
  localparam int unsigned STALL_REQUEST_GAP_SHORT = 1;
  localparam int unsigned STALL_REQUEST_GAP_LONG  = 12;
  localparam int unsigned STALL_ACK_DELAY         = 9;
  localparam int unsigned STALL_RESET_LOW         = 6;
  localparam int unsigned STALL_SOURCE_CHURN      = 8;
  localparam int unsigned STALL_PROFILES          = 5;
  localparam int unsigned DRAIN_CYCLES            = 10;

  localparam int unsigned ACK_LATENCY       = 6;
  localparam int unsigned CONFIGURE_LATENCY = 5;
  localparam int unsigned SELECT_LATENCY    = 4;
  localparam int unsigned SOURCE_LATENCY    = 2;

  logic                      rstn_in               ;
  logic [0:63]               report_errors         ;
  cu_return_type             cu_return             ;
  cu_return_type             cu_return_done        ;
  logic [0:63]               cu_status             ;
  logic [0:63]               afu_status            ;
  ResponseStatistcsInterface response_statistics   ;
  afu_configure_type         afu_configure_out     ;
  cu_configure_type          cu_configure_out      ;
  MMIOInterfaceInput         mmio_in               ;
  MMIOInterfaceOutput        mmio_out_out          ;
  logic [0:1]                mmio_errors_out       ;
  logic                      report_errors_ack_out ;
  logic                      cu_return_done_ack_out;
  logic                      reset_mmio_out        ;

  mmio dut (
    .clock                 (clock                 ),
    .rstn_in               (rstn_in               ),
    .report_errors         (report_errors         ),
    .cu_return             (cu_return             ),
    .cu_return_done        (cu_return_done        ),
    .cu_status             (cu_status             ),
    .afu_status            (afu_status            ),
    .response_statistics   (response_statistics   ),
    .afu_configure_out     (afu_configure_out     ),
    .cu_configure_out      (cu_configure_out      ),
    .mmio_in               (mmio_in               ),
    .mmio_out_out          (mmio_out_out          ),
    .mmio_errors_out       (mmio_errors_out       ),
    .report_errors_ack_out (report_errors_ack_out ),
    .cu_return_done_ack_out(cu_return_done_ack_out),
    .reset_mmio_out        (reset_mmio_out        )
  );

////////////////////////////////////////////////////////////////////////////
// independent parity and descriptor references
////////////////////////////////////////////////////////////////////////////

  function automatic logic odd_parity_of(input logic [0:63] value);
    odd_parity_of = (($countones(value) % 2) == 0);
  endfunction

  function automatic logic [0:63] descriptor_word(input logic [0:22] index);
    case (index)
      23'd0  : return 64'h0000_0001_0001_8010;
      23'd4  : return 64'h0000_0000_0000_0001;
      23'd5  : return 64'h0000_0000_0000_0100;
      23'd6  : return 64'h0100_0000_0000_0000;
      23'd7  : return 64'h0000_0000_0000_0000;
      23'd8  : return 64'h0000_0000_0000_0000;
      23'd9  : return 64'h0000_0000_0000_0000;
      23'd32 : return 64'h4441_4544_0000_0000;
      23'd33 : return 64'h4645_4542_0000_0000;
      default : return 64'h0000_0000_0000_0000;
    endcase
  endfunction

////////////////////////////////////////////////////////////////////////////
// address map
////////////////////////////////////////////////////////////////////////////

  logic [0:23] read_address_map  [0:READ_REGISTERS-1] ;
  logic [0:23] write_address_map [0:WRITE_REGISTERS-1];
  logic [0:22] descriptor_index_map [0:DESCRIPTOR_WORDS-1];

  typedef struct packed {
    logic                      rstn_in            ;
    logic                      valid              ;
    logic                      cfg                ;
    logic                      read               ;
    logic                      doubleword         ;
    logic [0:23]               address            ;
    logic                      address_parity     ;
    logic [0:63]               data               ;
    logic                      data_parity        ;
    logic [0:63]               report_errors      ;
    logic [0:63]               cu_return_var1     ;
    logic [0:63]               cu_return_var2     ;
    logic [0:63]               cu_return_done_var1;
    logic [0:63]               cu_return_done_var2;
    logic [0:63]               afu_status         ;
    logic [0:63]               cu_status          ;
    ResponseStatistcsInterface stats              ;
  } snapshot_t;

  snapshot_t hist [0:HIST_DEPTH-1];

  logic [0:63]       model_data_out     ;
  logic [0:63]       model_data_out_prev;
  cu_configure_type  model_cu_configure ;
  afu_configure_type model_afu_configure;
  logic [0:63]       model_cu_ack      ;
  logic [0:63]       model_cu_ack_prev ;
  logic [0:63]       model_err_ack     ;
  logic [0:63]       model_err_ack_prev;

  logic rstn_previous;
  logic rstn_reg     ;
  logic rstn_reg_last;

  int unsigned cycle   ;
  logic        checking;
  string       phase   ;

  bit bin_read_register  [0:READ_REGISTERS-1] ;
  bit bin_write_register [0:WRITE_REGISTERS-1];
  bit bin_descriptor     [0:DESCRIPTOR_WORDS-1];
  bit bin_word_mode      [0:2];
  bit bin_unmapped       [0:1];
  bit bin_ack            [0:3];
  bit bin_parity         [0:3];
  bit bin_gap            [0:2];
  bit bin_control        [0:2];
  bit stall_used         [0:4];

////////////////////////////////////////////////////////////////////////////
// diagnostics
////////////////////////////////////////////////////////////////////////////

  task automatic fail(input string reason);
    $error(
      "mmio mismatch reason=%s phase=%s cycle=%0d",
      reason,
      phase,
      cycle
    );
    $fatal(1);
  endtask

  function automatic int read_register_index(input logic [0:23] address);
    for(int index = 0; index < READ_REGISTERS; index++)
      if(read_address_map[index] == address)
        return index;
    return -1;
  endfunction

  function automatic int write_register_index(input logic [0:23] address);
    for(int index = 0; index < WRITE_REGISTERS; index++)
      if(write_address_map[index] == address)
        return index;
    return -1;
  endfunction

  function automatic int descriptor_word_index(input logic [0:22] index);
    for(int entry = 0; entry < DESCRIPTOR_WORDS; entry++)
      if(descriptor_index_map[entry] == index)
        return entry;
    return -1;
  endfunction

  function automatic logic [0:63] mapped_read_value(
      input int        index   ,
      input snapshot_t source
  );
    case (index)
      0  : return source.cu_return_var1;
      1  : return source.cu_return_var2;
      2  : return source.cu_return_done_var1;
      3  : return source.cu_return_done_var2;
      4  : return source.report_errors;
      5  : return source.afu_status;
      6  : return source.cu_status;
      7  : return source.stats.DONE_RESTART_count;
      8  : return source.stats.DONE_count;
      9  : return source.stats.FLUSHED_count;
      10 : return source.stats.PAGED_count;
      11 : return source.stats.AERROR_count;
      12 : return source.stats.DERROR_count;
      13 : return source.stats.FAILED_count;
      14 : return source.stats.FAULT_count;
      15 : return source.stats.NRES_count;
      16 : return source.stats.NLOCK_count;
      17 : return source.stats.CYCLE_count;
      18 : return source.stats.DONE_READ_count;
      19 : return source.stats.DONE_WRITE_count;
      20 : return source.stats.DONE_PREFETCH_READ_count;
      21 : return source.stats.DONE_PREFETCH_WRITE_count;
      22 : return source.stats.READ_BYTE_count;
      23 : return source.stats.WRITE_BYTE_count;
      24 : return source.stats.PREFETCH_READ_BYTE_count;
      25 : return source.stats.PREFETCH_WRITE_BYTE_count;
      default : return 64'h0;
    endcase
  endfunction

////////////////////////////////////////////////////////////////////////////
// model and checker
////////////////////////////////////////////////////////////////////////////

  always @(posedge clock) begin
    snapshot_t         snapshot        ;
    logic              in_reset        ;
    logic              expect_ack      ;
    logic [0:63]       expect_data     ;
    logic              expect_parity   ;
    logic [0:1]        expect_errors   ;
    logic              expect_cu_ack   ;
    logic              expect_err_ack  ;
    cu_configure_type  expect_cu_cfg   ;
    afu_configure_type expect_afu_cfg  ;
    logic [0:63]       effective_data  ;
    logic              effective_parity;
    logic [0:63]       descriptor      ;
    int                index           ;

    for(int position = HIST_DEPTH-1; position > 0; position--)
      hist[position] = hist[position-1];

    snapshot                     = '0;
    snapshot.rstn_in             = rstn_in;
    snapshot.valid               = mmio_in.valid;
    snapshot.cfg                 = mmio_in.cfg;
    snapshot.read                = mmio_in.read;
    snapshot.doubleword          = mmio_in.doubleword;
    snapshot.address             = mmio_in.address;
    snapshot.address_parity      = mmio_in.address_parity;
    snapshot.data                = mmio_in.data;
    snapshot.data_parity         = mmio_in.data_parity;
    snapshot.report_errors       = report_errors;
    snapshot.cu_return_var1      = cu_return.var1;
    snapshot.cu_return_var2      = cu_return.var2;
    snapshot.cu_return_done_var1 = cu_return_done.var1;
    snapshot.cu_return_done_var2 = cu_return_done.var2;
    snapshot.afu_status          = afu_status;
    snapshot.cu_status           = cu_status;
    snapshot.stats               = response_statistics;
    hist[0]                      = snapshot;

    rstn_reg_last = rstn_reg;
    rstn_reg      = rstn_in ? rstn_previous : 1'b0;
    rstn_previous = rstn_in;
    in_reset      = (!rstn_reg) || (!rstn_reg_last);
    cycle++;

    // -------------------------------------------------------------------
    // expected module outputs for this cycle
    // -------------------------------------------------------------------
    expect_ack     = 1'b0;
    expect_data    = 64'h0;
    expect_parity  = 1'b0;
    expect_errors  = 2'b00;
    expect_cu_ack  = 1'b0;
    expect_err_ack = 1'b0;
    expect_cu_cfg  = '0;
    expect_afu_cfg = '0;

    if(!in_reset) begin
      expect_ack    = hist[ACK_LATENCY].valid;
      expect_data   = model_data_out_prev;
      expect_parity = odd_parity_of(model_data_out_prev);

      effective_data   = 64'h0;
      effective_parity = 1'b1;
      if(hist[ACK_LATENCY].valid && !hist[ACK_LATENCY].read) begin
        effective_data   = hist[ACK_LATENCY].data;
        effective_parity = hist[ACK_LATENCY].data_parity;
      end
      if(hist[ACK_LATENCY].valid)
        expect_errors = {
          odd_parity_of(effective_data) ^ effective_parity,
          odd_parity_of({40'h0, hist[ACK_LATENCY].address}) ^
            hist[ACK_LATENCY].address_parity
        };

      expect_cu_ack  = |model_cu_ack_prev;
      expect_err_ack = |model_err_ack_prev;
      expect_cu_cfg  = model_cu_configure;
      expect_afu_cfg = model_afu_configure;
    end

    if(checking) begin
      checks++;
      if(reset_mmio_out !== 1'b1)
        fail("mmio reset request is always released");
      bin_control[2] = 1;

      checks++;
      if(mmio_out_out.ack !== expect_ack)
        fail("mmio acknowledge");

      checks++;
      if(mmio_out_out.data !== expect_data)
        fail("mmio read data");

      checks++;
      if(mmio_out_out.data_parity !== expect_parity)
        fail("mmio read data parity");

      checks++;
      if(mmio_errors_out !== expect_errors)
        fail($sformatf(
          "mmio parity report expected=%2b actual=%2b",
          expect_errors,
          mmio_errors_out
        ));

      checks++;
      if(cu_return_done_ack_out !== expect_cu_ack)
        fail("compute unit return acknowledge");

      checks++;
      if(report_errors_ack_out !== expect_err_ack)
        fail("error register acknowledge");

      checks++;
      if(cu_configure_out !== expect_cu_cfg)
        fail("compute unit configuration publication");

      checks++;
      if(afu_configure_out !== expect_afu_cfg)
        fail("afu configuration publication");

      if(hist[ACK_LATENCY].valid)
        bin_parity[{expect_errors[0], expect_errors[1]}] = 1;
      if(in_reset)
        bin_control[0] = 1;
      if(expect_ack && (expect_cu_ack || expect_err_ack))
        bin_control[1] = 1;
    end

    // -------------------------------------------------------------------
    // advance the independent register model
    // -------------------------------------------------------------------
    model_data_out_prev = model_data_out;
    model_cu_ack_prev   = model_cu_ack;
    model_err_ack_prev  = model_err_ack;

    if(in_reset) begin
      model_data_out           = 64'h0;
      model_data_out_prev      = 64'h0;
      model_cu_configure       = '0;
      model_afu_configure      = '0;
      model_cu_ack             = 64'h0;
      model_cu_ack_prev        = 64'h0;
      model_err_ack            = 64'h0;
      model_err_ack_prev       = 64'h0;
    end else begin
      if(hist[SELECT_LATENCY].valid && hist[SELECT_LATENCY].cfg &&
         hist[SELECT_LATENCY].read) begin
        descriptor = descriptor_word(hist[SELECT_LATENCY].address[0:22]);
        if(hist[SELECT_LATENCY].doubleword)
          model_data_out = descriptor;
        else if(hist[SELECT_LATENCY].address[23])
          model_data_out = {descriptor[32:63], descriptor[32:63]};
        else
          model_data_out = {descriptor[0:31], descriptor[0:31]};
        if(checking) begin
          index = descriptor_word_index(hist[SELECT_LATENCY].address[0:22]);
          if(index >= 0)
            bin_descriptor[index] = 1;
          bin_word_mode[
            hist[SELECT_LATENCY].doubleword ? 0 :
            (hist[SELECT_LATENCY].address[23] ? 2 : 1)
          ] = 1;
        end
      end else if(hist[SELECT_LATENCY].valid && !hist[SELECT_LATENCY].cfg &&
                  hist[SELECT_LATENCY].read) begin
        index = read_register_index(hist[SELECT_LATENCY].address);
        if(index >= 0)
          model_data_out = mapped_read_value(index, hist[SOURCE_LATENCY]);
        if(checking) begin
          if(index >= 0)
            bin_read_register[index] = 1;
          else
            bin_unmapped[0] = 1;
        end
      end

      // a mapped write updates only the addressed field, every other write
      // cycle clears the whole configuration and acknowledge pulse group
      if(hist[SELECT_LATENCY].valid && !hist[SELECT_LATENCY].cfg &&
         !hist[SELECT_LATENCY].read) begin
        index = write_register_index(hist[SELECT_LATENCY].address);
        case (index)
          0 : model_cu_configure.var1 = hist[SELECT_LATENCY].data;
          1 : model_cu_configure.var2 = hist[SELECT_LATENCY].data;
          2 : model_cu_configure.var3 = hist[SELECT_LATENCY].data;
          3 : model_cu_configure.var4 = hist[SELECT_LATENCY].data;
          4 : model_afu_configure.var1 = hist[SELECT_LATENCY].data;
          5 : model_afu_configure.var2 = hist[SELECT_LATENCY].data;
          6 : model_cu_ack = hist[SELECT_LATENCY].data;
          7 : model_err_ack = hist[SELECT_LATENCY].data;
          default : begin
            model_cu_configure  = '0;
            model_afu_configure = '0;
            model_cu_ack        = 64'h0;
            model_err_ack       = 64'h0;
          end
        endcase
        if(checking) begin
          if(index >= 0) begin
            bin_write_register[index] = 1;
            if(index == 6)
              bin_ack[(|hist[SELECT_LATENCY].data) ? 0 : 1] = 1;
            if(index == 7)
              bin_ack[(|hist[SELECT_LATENCY].data) ? 2 : 3] = 1;
          end else begin
            bin_unmapped[1] = 1;
          end
        end
      end else begin
        model_cu_configure  = '0;
        model_afu_configure = '0;
        model_cu_ack        = 64'h0;
        model_err_ack       = 64'h0;
      end
    end
  end

////////////////////////////////////////////////////////////////////////////
// stimulus
////////////////////////////////////////////////////////////////////////////

  task automatic step(input int unsigned count);
    for(int unsigned index = 0; index < count; index++)
      @(negedge clock);
  endtask

  task automatic request(
      input logic        cfg         ,
      input logic        read        ,
      input logic        doubleword  ,
      input logic [0:23] address     ,
      input logic [0:63] data        ,
      input logic        address_fault,
      input logic        data_fault
  );
    mmio_in.valid          = 1'b1;
    mmio_in.cfg            = cfg;
    mmio_in.read           = read;
    mmio_in.doubleword     = doubleword;
    mmio_in.address        = address;
    mmio_in.address_parity = odd_parity_of({40'h0, address}) ^ address_fault;
    mmio_in.data           = data;
    mmio_in.data_parity    = odd_parity_of(data) ^ data_fault;
    step(1);
    mmio_in = '0;
  endtask

  task automatic read_register(input logic [0:23] address);
    request(1'b0, 1'b1, 1'b1, address, 64'h0, 1'b0, 1'b0);
    step(DRAIN_CYCLES);
  endtask

  task automatic write_register(input logic [0:23] address, input logic [0:63] data);
    request(1'b0, 1'b0, 1'b1, address, data, 1'b0, 1'b0);
    step(DRAIN_CYCLES);
  endtask

  task automatic read_descriptor(
      input logic [0:22] index     ,
      input logic        doubleword,
      input logic        odd_word
  );
    request(1'b1, 1'b1, doubleword, {index, odd_word}, 64'h0, 1'b0, 1'b0);
    step(DRAIN_CYCLES);
  endtask

  task automatic drive_sources(input logic [0:63] seed);
    report_errors       = seed ^ 64'h0000_0000_0000_00FF;
    cu_return.var1      = seed ^ 64'h1111_1111_1111_1111;
    cu_return.var2      = seed ^ 64'h2222_2222_2222_2222;
    cu_return_done.var1 = seed ^ 64'h3333_3333_3333_3333;
    cu_return_done.var2 = seed ^ 64'h4444_4444_4444_4444;
    afu_status          = seed ^ 64'h5555_5555_5555_5555;
    cu_status           = seed ^ 64'h6666_6666_6666_6666;

    response_statistics.DONE_count                = seed ^ 64'h0000_0000_0000_0001;
    response_statistics.DONE_RESTART_count        = seed ^ 64'h0000_0000_0000_0002;
    response_statistics.DONE_PREFETCH_READ_count  = seed ^ 64'h0000_0000_0000_0003;
    response_statistics.DONE_PREFETCH_WRITE_count = seed ^ 64'h0000_0000_0000_0004;
    response_statistics.PAGED_count               = seed ^ 64'h0000_0000_0000_0005;
    response_statistics.FLUSHED_count             = seed ^ 64'h0000_0000_0000_0006;
    response_statistics.AERROR_count              = seed ^ 64'h0000_0000_0000_0007;
    response_statistics.DERROR_count              = seed ^ 64'h0000_0000_0000_0008;
    response_statistics.FAILED_count              = seed ^ 64'h0000_0000_0000_0009;
    response_statistics.FAULT_count               = seed ^ 64'h0000_0000_0000_000A;
    response_statistics.NRES_count                = seed ^ 64'h0000_0000_0000_000B;
    response_statistics.NLOCK_count               = seed ^ 64'h0000_0000_0000_000C;
    response_statistics.CYCLE_count               = seed ^ 64'h0000_0000_0000_000D;
    response_statistics.DONE_READ_count           = seed ^ 64'h0000_0000_0000_000E;
    response_statistics.DONE_WRITE_count          = seed ^ 64'h0000_0000_0000_000F;
    response_statistics.READ_BYTE_count           = seed ^ 64'h0000_0000_0000_0010;
    response_statistics.WRITE_BYTE_count          = seed ^ 64'h0000_0000_0000_0011;
    response_statistics.PREFETCH_READ_BYTE_count  = seed ^ 64'h0000_0000_0000_0012;
    response_statistics.PREFETCH_WRITE_BYTE_count = seed ^ 64'h0000_0000_0000_0013;
  endtask

  task automatic check_bins();
    bin_hits = 0;
    for(int index = 0; index < READ_REGISTERS; index++) begin
      if(!bin_read_register[index])
        $fatal(1, "mmio missing read register bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < WRITE_REGISTERS; index++) begin
      if(!bin_write_register[index])
        $fatal(1, "mmio missing write register bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < DESCRIPTOR_WORDS; index++) begin
      if(!bin_descriptor[index])
        $fatal(1, "mmio missing descriptor bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_word_mode[index])
        $fatal(1, "mmio missing word mode bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 2; index++) begin
      if(!bin_unmapped[index])
        $fatal(1, "mmio missing unmapped access bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 4; index++) begin
      if(!bin_ack[index])
        $fatal(1, "mmio missing acknowledge bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 4; index++) begin
      if(!bin_parity[index])
        $fatal(1, "mmio missing parity bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_gap[index])
        $fatal(1, "mmio missing request gap bin %0d", index);
      bin_hits++;
    end
    for(int index = 0; index < 3; index++) begin
      if(!bin_control[index])
        $fatal(1, "mmio missing control bin %0d", index);
      bin_hits++;
    end
    stalls = 0;
    for(int index = 0; index < STALL_PROFILES; index++) begin
      if(!stall_used[index])
        $fatal(1, "mmio missing stall profile %0d", index);
      stalls++;
    end
  endtask

  initial begin
    read_address_map[0]  = CU_RETURN;
    read_address_map[1]  = CU_RETURN_2;
    read_address_map[2]  = CU_RETURN_DONE;
    read_address_map[3]  = CU_RETURN_DONE_2;
    read_address_map[4]  = ERROR_REG;
    read_address_map[5]  = AFU_STATUS;
    read_address_map[6]  = CU_STATUS;
    read_address_map[7]  = DONE_RESTART_COUNT_REG;
    read_address_map[8]  = DONE_COUNT_REG;
    read_address_map[9]  = FLUSHED_COUNT_REG;
    read_address_map[10] = PAGED_COUNT_REG;
    read_address_map[11] = AERROR_COUNT_REG;
    read_address_map[12] = DERROR_COUNT_REG;
    read_address_map[13] = FAILED_COUNT_REG;
    read_address_map[14] = FAULT_COUNT_REG;
    read_address_map[15] = NRES_COUNT_REG;
    read_address_map[16] = NLOCK_COUNT_REG;
    read_address_map[17] = CYCLE_COUNT_REG;
    read_address_map[18] = DONE_READ_COUNT_REG;
    read_address_map[19] = DONE_WRITE_COUNT_REG;
    read_address_map[20] = DONE_PREFETCH_READ_COUNT_REG;
    read_address_map[21] = DONE_PREFETCH_WRITE_COUNT_REG;
    read_address_map[22] = READ_BYTE_COUNT_REG;
    read_address_map[23] = WRITE_BYTE_COUNT_REG;
    read_address_map[24] = PREFETCH_READ_BYTE_COUNT_REG;
    read_address_map[25] = PREFETCH_WRITE_BYTE_COUNT_REG;

    write_address_map[0] = CU_CONFIGURE;
    write_address_map[1] = CU_CONFIGURE_2;
    write_address_map[2] = CU_CONFIGURE_3;
    write_address_map[3] = CU_CONFIGURE_4;
    write_address_map[4] = AFU_CONFIGURE;
    write_address_map[5] = AFU_CONFIGURE_2;
    write_address_map[6] = CU_RETURN_DONE_ACK;
    write_address_map[7] = ERROR_REG_ACK;

    descriptor_index_map[0] = 23'd0;
    descriptor_index_map[1] = 23'd4;
    descriptor_index_map[2] = 23'd5;
    descriptor_index_map[3] = 23'd6;
    descriptor_index_map[4] = 23'd7;
    descriptor_index_map[5] = 23'd8;
    descriptor_index_map[6] = 23'd9;
    descriptor_index_map[7] = 23'd32;
    descriptor_index_map[8] = 23'd33;
    descriptor_index_map[9] = 23'd11;

    finished                 = 1'b0;
    bin_hits                 = 0;
    stalls                   = 0;
    cycle                    = 0;
    checking                 = 1'b0;
    phase                    = "reset";
    rstn_in                  = 1'b0;
    mmio_in                  = '0;
    report_errors            = '0;
    cu_return                = '0;
    cu_return_done           = '0;
    cu_status                = '0;
    afu_status               = '0;
    response_statistics      = '0;
    model_data_out           = 64'h0;
    model_data_out_prev      = 64'h0;
    model_cu_configure       = '0;
    model_afu_configure      = '0;
    model_cu_ack             = 64'h0;
    model_cu_ack_prev        = 64'h0;
    model_err_ack            = 64'h0;
    model_err_ack_prev       = 64'h0;
    rstn_previous            = 1'b0;
    rstn_reg                 = 1'b0;
    rstn_reg_last            = 1'b0;
    foreach(hist[position]) hist[position] = '0;

    drive_sources(64'h0F1E_2D3C_4B5A_6978);

    step(4);
    rstn_in = 1'b1;
    step(DRAIN_CYCLES);
    checking = 1'b1;

    // ---------------------------------------------------------------------
    phase = "status-register-sweep";
    for(int index = 0; index < READ_REGISTERS; index++)
      read_register(read_address_map[index]);

    // ---------------------------------------------------------------------
    phase = "descriptor-sweep";
    for(int index = 0; index < DESCRIPTOR_WORDS; index++)
      read_descriptor(descriptor_index_map[index], 1'b1, 1'b0);
    read_descriptor(23'd0, 1'b0, 1'b0);
    read_descriptor(23'd0, 1'b0, 1'b1);

    // ---------------------------------------------------------------------
    phase = "configuration-write-sweep";
    for(int index = 0; index < 6; index++)
      write_register(write_address_map[index], 64'hFFFF_FFFF_FFFF_FFFF);
    for(int index = 0; index < 6; index++)
      write_register(write_address_map[index], 64'h0000_0000_0000_0000);
    write_register(write_address_map[0], 64'h0123_4567_89AB_CDEF);

    // ---------------------------------------------------------------------
    phase = "acknowledge-registers";
    write_register(CU_RETURN_DONE_ACK, 64'h0000_0000_0000_0001);
    step(STALL_ACK_DELAY);
    stall_used[2] = 1;
    write_register(CU_RETURN_DONE_ACK, 64'h0000_0000_0000_0000);
    write_register(CU_RETURN_DONE_ACK, 64'hFFFF_FFFF_FFFF_FFFF);
    write_register(CU_RETURN_DONE_ACK, 64'h0000_0000_0000_0000);
    write_register(ERROR_REG_ACK, 64'hFFFF_FFFF_FFFF_FFFF);
    write_register(ERROR_REG_ACK, 64'h0000_0000_0000_0000);

    // ---------------------------------------------------------------------
    phase = "configuration-space-write";
    request(1'b1, 1'b0, 1'b1, {23'd0, 1'b0}, 64'hFFFF_FFFF_FFFF_FFFF, 1'b0, 1'b0);
    step(DRAIN_CYCLES);
    request(1'b1, 1'b0, 1'b0, {23'd5, 1'b1}, 64'h0000_0000_0000_0000, 1'b0, 1'b0);
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "unmapped-access";
    read_register(24'h00_1234);
    write_register(24'h00_1234, 64'hDEAD_BEEF_FEED_FACE);
    read_register(24'h00_1234);

    // ---------------------------------------------------------------------
    phase = "parity-faults";
    request(1'b0, 1'b1, 1'b1, AFU_STATUS, 64'h0, 1'b1, 1'b0);
    step(DRAIN_CYCLES);
    request(1'b0, 1'b0, 1'b1, CU_CONFIGURE, 64'h55AA_55AA_55AA_55AA, 1'b0, 1'b1);
    step(DRAIN_CYCLES);
    request(1'b0, 1'b0, 1'b1, CU_CONFIGURE, 64'h55AA_55AA_55AA_55AA, 1'b1, 1'b1);
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "request-gaps";
    request(1'b0, 1'b1, 1'b1, CU_STATUS, 64'h0, 1'b0, 1'b0);
    request(1'b0, 1'b1, 1'b1, AFU_STATUS, 64'h0, 1'b0, 1'b0);
    request(1'b0, 1'b0, 1'b1, CU_CONFIGURE_2, 64'hA5A5_A5A5_A5A5_A5A5, 1'b0, 1'b0);
    request(1'b0, 1'b1, 1'b1, ERROR_REG, 64'h0, 1'b0, 1'b0);
    bin_gap[0] = 1;
    step(DRAIN_CYCLES);

    request(1'b0, 1'b1, 1'b1, CU_RETURN, 64'h0, 1'b0, 1'b0);
    step(STALL_REQUEST_GAP_SHORT);
    stall_used[0] = 1;
    request(1'b0, 1'b1, 1'b1, CU_RETURN_2, 64'h0, 1'b0, 1'b0);
    bin_gap[1] = 1;
    step(DRAIN_CYCLES);

    request(1'b0, 1'b1, 1'b1, CU_RETURN_DONE, 64'h0, 1'b0, 1'b0);
    step(STALL_REQUEST_GAP_LONG);
    stall_used[1] = 1;
    request(1'b0, 1'b1, 1'b1, CU_RETURN_DONE_2, 64'h0, 1'b0, 1'b0);
    bin_gap[2] = 1;
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase = "source-churn-during-transaction";
    request(1'b0, 1'b1, 1'b1, CU_STATUS, 64'h0, 1'b0, 1'b0);
    for(int index = 0; index < STALL_SOURCE_CHURN; index++) begin
      drive_sources(64'hAAAA_0000_0000_0000 + 64'(index));
      step(1);
    end
    stall_used[3] = 1;
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase               = "extreme-source-values";
    report_errors       = {64{1'b1}};
    cu_return           = '1;
    cu_return_done      = '1;
    afu_status          = {64{1'b1}};
    cu_status           = {64{1'b1}};
    response_statistics = '1;
    read_register(ERROR_REG);
    read_register(CU_RETURN);
    read_register(CU_RETURN_DONE_2);
    read_register(DONE_COUNT_REG);
    report_errors       = {64{1'b0}};
    cu_return           = '0;
    cu_return_done      = '0;
    afu_status          = {64{1'b0}};
    cu_status           = {64{1'b0}};
    response_statistics = '0;
    read_register(ERROR_REG);
    read_register(CU_RETURN);
    read_register(CU_RETURN_DONE_2);
    read_register(DONE_COUNT_REG);
    drive_sources(64'h0F1E_2D3C_4B5A_6978);
    step(DRAIN_CYCLES);

    // ---------------------------------------------------------------------
    phase   = "reset-window";
    rstn_in = 1'b0;
    step(STALL_RESET_LOW);
    stall_used[4] = 1;
    rstn_in       = 1'b1;
    step(DRAIN_CYCLES);
    read_register(AFU_STATUS);

    check_bins();
    checking = 1'b0;
    finished = 1'b1;
  end

endmodule
