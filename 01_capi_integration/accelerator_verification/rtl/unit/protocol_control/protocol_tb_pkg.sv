package PROTOCOL_TB_PKG;

  import GLOBALS_AFU_PKG::*;
  import CAPI_PKG::*;
  import AFU_PKG::*;
  import CU_PKG::*;

  function automatic logic model_odd_parity8(input logic [0:7] data);
    logic result;
    result = 1'b1;
    for(int bit_index = 0; bit_index < 8; bit_index++)
      result ^= data[bit_index];
    return result;
  endfunction

  function automatic logic model_odd_parity13(input logic [0:12] data);
    logic result;
    result = 1'b1;
    for(int bit_index = 0; bit_index < 13; bit_index++)
      result ^= data[bit_index];
    return result;
  endfunction

  function automatic logic model_odd_parity64(input logic [0:63] data);
    logic result;
    result = 1'b1;
    for(int bit_index = 0; bit_index < 64; bit_index++)
      result ^= data[bit_index];
    return result;
  endfunction

  function automatic afu_command_t legal_command(input int unsigned index);
    case(index)
      0:  return READ_CL_S;
      1:  return READ_CL_M;
      2:  return READ_CL_LCK;
      3:  return READ_CL_RES;
      4:  return TOUCH_I;
      5:  return TOUCH_S;
      6:  return TOUCH_M;
      7:  return WRITE_MI;
      8:  return WRITE_MS;
      9:  return WRITE_UNLOCK;
      10: return WRITE_C;
      11: return PUSH_I;
      12: return PUSH_S;
      13: return EVICT_I;
      14: return LOCK;
      15: return UNLOCK;
      16: return READ_CL_NA;
      17: return READ_PNA;
      18: return WRITE_NA;
      19: return WRITE_INJ;
      20: return FLUSH;
      21: return INTREQ;
      22: return RESTART;
      default: return INVALID;
    endcase
  endfunction

  function automatic logic [0:11] legal_size(input int unsigned index);
    case(index)
      0: return 12'd1;
      1: return 12'd2;
      2: return 12'd4;
      3: return 12'd8;
      4: return 12'd16;
      5: return 12'd32;
      6: return 12'd64;
      7: return 12'd128;
      default: return 12'd0;
    endcase
  endfunction

  function automatic trans_order_behavior_t legal_abt(input int unsigned index);
    case(index)
      0: return STRICT;
      1: return ABORT;
      2: return PAGE;
      3: return PREF;
      4: return SPEC;
      default: return STRICT;
    endcase
  endfunction

  function automatic logic [0:63] legal_address(input int unsigned index);
    case(index)
      0: return 64'h0000_0000_0000_0000;
      1: return 64'h0000_0000_0000_0001;
      2: return 64'h0000_0000_0000_0080;
      3: return 64'h0000_0000_0000_ff80;
      4: return 64'hffff_ffff_ffff_ff80;
      5: return 64'hffff_ffff_ffff_ffff;
      default: return 64'h0;
    endcase
  endfunction

  function automatic CommandTagLine make_metadata(
      input command_type cmd_type,
      input logic [0:7] tag,
      input trans_order_behavior_t abt,
      input logic [0:7] size_bytes
  );
    CommandTagLine metadata;
    metadata = '0;
    metadata.cu_id_x = cu_id_t'(8'h31);
    metadata.cu_id_y = cu_id_t'(8'h47);
    metadata.array_struct = READ_DATA;
    metadata.cmd_type = cmd_type;
    metadata.real_size = size_bytes;
    metadata.real_size_bytes = size_bytes;
    metadata.cacheline_offset = tag;
    metadata.address_offset = 64'h1020_3040_5060_7080 ^ tag;
    metadata.aux_data = 64'h8877_6655_4433_2211 ^ tag;
    metadata.size = size_bytes;
    metadata.tag = tag;
    metadata.abt = abt;
    return metadata;
  endfunction

  function automatic logic [0:5] model_response_error(
      input psl_response_t response_code
  );
    case(response_code)
      AERROR: return 6'b000001;
      DERROR: return 6'b000010;
      FAILED: return 6'b000100;
      FAULT:  return 6'b001000;
      NRES:   return 6'b010000;
      NLOCK:  return 6'b100000;
      default: return 6'b000000;
    endcase
  endfunction

endpackage
