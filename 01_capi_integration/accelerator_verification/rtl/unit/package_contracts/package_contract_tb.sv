module package_contract_tb;

  import GLOBALS_AFU_PKG::*;
  import GLOBALS_CU_PKG::*;
  import CAPI_PKG::*;
  import WED_PKG::*;
  import CU_PKG::*;
  import CREDIT_PKG::*;
  import AFU_PKG::*;

  int unsigned checks;
  int unsigned bins_hit;

  task automatic check(input logic condition, input string name);
    checks++;
    if(!condition)
      $fatal(1, "package contract failed: %s", name);
  endtask

  function automatic logic [0:11] command_size_oracle(input int unsigned count);
    int unsigned bytes;
    int unsigned size;

    bytes = count * ARRAY_SIZE;
    if(bytes == 0)
      return 0;
    size = 1;
    while(size < bytes && size < 128)
      size *= 2;
    return size;
  endfunction

  initial begin
    logic [  0:31] input_32;
    logic [  0:31] expected_32;
    logic [  0:63] input_64;
    logic [  0:63] expected_64;
    logic [ 0:127] input_128;
    logic [ 0:127] expected_128;
    logic [ 0:255] input_256;
    logic [ 0:255] expected_256;
    logic [ 0:511] input_512;
    logic [ 0:511] expected_512;
    logic [0:1023] input_1024;
    logic [0:1023] expected_1024;
    logic [0:1023] expected_wed;
    WED_request mapped_wed;
    AFUDescriptor descriptor;
`ifdef HAS_CU_ENDIAN
    logic [0:DATA_SIZE_WRITE_BITS-1] cu_write_in;
    logic [0:DATA_SIZE_WRITE_BITS-1] cu_write_expected;
    logic [0:DATA_SIZE_READ_BITS-1] cu_read_in;
    logic [0:DATA_SIZE_READ_BITS-1] cu_read_expected;
    logic [0:ARRAY_SIZE_BITS-1] cu_array_in;
    logic [0:ARRAY_SIZE_BITS-1] cu_array_expected;
`endif

    check(PAGE_SIZE == 65536, "PAGE_SIZE");
    check(CACHELINE_SIZE == 128, "CACHELINE_SIZE");
    check(CACHELINE_SIZE_BITS == 1024, "CACHELINE_SIZE_BITS");
    check(CACHELINE_SIZE_BITS_HF == 512, "CACHELINE_SIZE_BITS_HF");
    check(TAG_COUNT == 256, "TAG_COUNT");
    check(CREDITS_TOTAL == 64, "CREDITS_TOTAL");
    check($bits(JobInterfaceInput) == 75, "JobInterfaceInput width");
    check($bits(JobInterfaceOutput) == 68, "JobInterfaceOutput width");
    check($bits(CommandInterfaceInput) == 8, "CommandInterfaceInput width");
    check($bits(CommandInterfaceOutput) == 120, "CommandInterfaceOutput width");
    check($bits(ResponseInterface) == 42, "ResponseInterface width");
    check($bits(MMIOInterfaceInput) == 94, "MMIOInterfaceInput width");
    check($bits(MMIOInterfaceOutput) == 66, "MMIOInterfaceOutput width");
    check($bits(CreditInterfaceInput) == 19, "CreditInterfaceInput width");
    check($bits(CreditInterfaceOutput) == 8, "CreditInterfaceOutput width");
    check($bits(WED_request) == 1024, "WED_request width");
    check($bits(WEDInterfacePayload) == 1088, "WEDInterfacePayload width");
    check($bits(WEDInterface) == 1089, "WEDInterface width");
    check($bits(cu_return_type) == 128, "cu_return_type width");
    check($bits(cu_configure_type) == 256, "cu_configure_type width");
    check($bits(afu_configure_type) == 128, "afu_configure_type width");
    bins_hit += 21;

    check(RESET == 8'h80, "RESET encoding");
    check(START == 8'h90, "START encoding");
    check(DONE == 8'h00, "DONE encoding");
    check(AERROR == 8'h01, "AERROR encoding");
    check(DERROR == 8'h03, "DERROR encoding");
    check(PAGED == 8'h0a, "PAGED encoding");
    check(READ_CL_NA == 13'h0a00, "READ_CL_NA encoding");
    check(WRITE_NA == 13'h0d00, "WRITE_NA encoding");
    bins_hit += 8;

    for(int byte_index = 0; byte_index < 4; byte_index++) begin
      input_32[byte_index*8 +: 8] = byte_index;
      expected_32[byte_index*8 +: 8] = 3-byte_index;
    end
    for(int byte_index = 0; byte_index < 8; byte_index++) begin
      input_64[byte_index*8 +: 8] = byte_index;
      expected_64[byte_index*8 +: 8] = 7-byte_index;
    end
    for(int byte_index = 0; byte_index < 16; byte_index++) begin
      input_128[byte_index*8 +: 8] = byte_index;
      expected_128[byte_index*8 +: 8] = 15-byte_index;
    end
    for(int byte_index = 0; byte_index < 32; byte_index++) begin
      input_256[byte_index*8 +: 8] = byte_index;
      expected_256[byte_index*8 +: 8] = 31-byte_index;
    end
    for(int byte_index = 0; byte_index < 64; byte_index++) begin
      input_512[byte_index*8 +: 8] = byte_index;
      expected_512[byte_index*8 +: 8] = 63-byte_index;
    end
    for(int byte_index = 0; byte_index < 128; byte_index++) begin
      input_1024[byte_index*8 +: 8] = byte_index;
      expected_1024[byte_index*8 +: 8] = 127-byte_index;
    end
    for(int doubleword = 0; doubleword < 16; doubleword++) begin
      for(int byte_index = 0; byte_index < 8; byte_index++) begin
        expected_wed[(doubleword*64)+(byte_index*8) +: 8] =
          input_1024[(doubleword*64)+((7-byte_index)*8) +: 8];
      end
    end

    check(swap_endianness_word(input_32) == expected_32, "word endian");
    check(
      swap_endianness_double_word(input_64) == expected_64,
      "doubleword endian"
    );
    check(
      swap_endianness_quad_word(input_128) == expected_128,
      "quadword endian"
    );
    check(
      swap_endianness_octa_word(input_256) == expected_256,
      "octaword endian"
    );
    check(
      swap_endianness_half_cacheline128(input_512) == expected_512,
      "half-cacheline endian"
    );
    check(
      swap_endianness_full_cacheline128(input_1024) == expected_1024,
      "full-cacheline endian"
    );
    bins_hit += 6;

`ifdef HAS_CU_ENDIAN
    for(int byte_index = 0; byte_index < DATA_SIZE_WRITE; byte_index++) begin
      cu_write_in[byte_index*8 +: 8] = byte_index;
      cu_write_expected[byte_index*8 +: 8] =
        DATA_SIZE_WRITE-1-byte_index;
    end
    for(int byte_index = 0; byte_index < DATA_SIZE_READ; byte_index++) begin
      cu_read_in[byte_index*8 +: 8] = byte_index;
      cu_read_expected[byte_index*8 +: 8] =
        DATA_SIZE_READ-1-byte_index;
    end
    for(int byte_index = 0; byte_index < ARRAY_SIZE; byte_index++) begin
      cu_array_in[byte_index*8 +: 8] = byte_index;
      cu_array_expected[byte_index*8 +: 8] = ARRAY_SIZE-1-byte_index;
    end
    check(
      swap_endianness_data_write(cu_write_in) == cu_write_expected,
      "CU write endian"
    );
    check(
      swap_endianness_data_read(cu_read_in) == cu_read_expected,
      "CU read endian"
    );
    check(
      swap_endianness_array_read(cu_array_in) == cu_array_expected,
      "CU array endian"
    );
    bins_hit += 3;
`endif

    mapped_wed = map_DataArrays_to_WED(input_1024);
    check(mapped_wed == expected_wed, "WED byte mapping");
    bins_hit++;

    check(map_CABT(3'b000) == STRICT, "CABT strict");
    check(map_CABT(3'b100) == ABORT, "CABT abort");
    check(map_CABT(3'b010) == PAGE, "CABT page");
    check(map_CABT(3'b110) == PREF, "CABT pref");
    check(map_CABT(3'b111) == SPEC, "CABT spec");
    check(map_CABT(3'b001) == STRICT, "CABT default");
    bins_hit += 6;

    for(int count = 0; count <= 20; count++) begin
      check(
        cmd_size_calculate(count) == command_size_oracle(count),
        $sformatf("command size count=%0d", count)
      );
      bins_hit++;
    end

    descriptor = '0;
    descriptor.num_ints_per_process = 16'h1111;
    descriptor.num_of_processes = 16'h2222;
    descriptor.num_of_afu_crs = 16'h3333;
    descriptor.req_prog_model = 16'h4444;
    descriptor.reserved_2 = 8'haa;
    descriptor.afu_cr_len = 56'h123456789abcde;
    descriptor.afu_cr_offset = 64'h0123456789abcdef;
    descriptor.reserved_3 = 6'h2a;
    descriptor.psa_per_process_required = 1;
    descriptor.psa_required = 1;
    descriptor.psa_length = 56'h01020304050607;
    descriptor.psa_offset = 64'hfedcba9876543210;
    descriptor.reserved_4 = 8'h55;
    descriptor.afu_eb_len = 56'h08090a0b0c0d0e;
    descriptor.afu_eb_offset = 64'h1122334455667788;
    check(
      read_afu_descriptor(descriptor, 0) == 64'h1111222233334444,
      "descriptor offset 0"
    );
    check(
      read_afu_descriptor(descriptor, 4) == 64'haa123456789abcde,
      "descriptor offset 4"
    );
    check(
      read_afu_descriptor(descriptor, 5) == 64'h0123456789abcdef,
      "descriptor offset 5"
    );
    check(
      read_afu_descriptor(descriptor, 6) ==
        {6'h2a, 1'b1, 1'b1, 56'h01020304050607},
      "descriptor offset 6"
    );
    check(
      read_afu_descriptor(descriptor, 7) == 64'hfedcba9876543210,
      "descriptor offset 7"
    );
    check(
      read_afu_descriptor(descriptor, 8) == 64'h5508090a0b0c0d0e,
      "descriptor offset 8"
    );
    check(
      read_afu_descriptor(descriptor, 9) == 64'h1122334455667788,
      "descriptor offset 9"
    );
    check(
      read_afu_descriptor(descriptor, 32) == 64'h4441454400000000,
      "descriptor device/vendor"
    );
    check(
      read_afu_descriptor(descriptor, 33) == 64'h4645454200000000,
      "descriptor revision/class"
    );
    check(read_afu_descriptor(descriptor, 31) == 0, "descriptor default");
    bins_hit += 10;

    check(cmd_response_error_type(AERROR) == 6'b000001, "AERROR map");
    check(cmd_response_error_type(DERROR) == 6'b000010, "DERROR map");
    check(cmd_response_error_type(FAILED) == 6'b000100, "FAILED map");
    check(cmd_response_error_type(FAULT) == 6'b001000, "FAULT map");
    check(cmd_response_error_type(NRES) == 6'b010000, "NRES map");
    check(cmd_response_error_type(NLOCK) == 6'b100000, "NLOCK map");
    check(cmd_response_error_type(DONE) == 0, "response default");
    bins_hit += 7;

    $display(
      "PASS package_contracts checks=%0d bins=%0d",
      checks,
      bins_hit
    );
    $finish;
  end

endmodule
