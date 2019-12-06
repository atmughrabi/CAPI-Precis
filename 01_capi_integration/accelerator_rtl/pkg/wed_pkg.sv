// -----------------------------------------------------------------------------
//
//      "ACCEL-GRAPH Shared Memory Accelerator Project"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi atmughrabi@gmail.com/atmughra@ncsu.edu
// File   : wed_pkg.sv
// Create : 2019-09-26 15:20:20
// Revise : 2019-09-26 15:20:20
// Editor : sublime text3, tab size (4)
// -----------------------------------------------------------------------------

package WED_PKG;

    import GLOBALS_AFU_PKG::*;
    import CAPI_PKG::*;

    typedef enum int unsigned {
        WED_RESET,
        WED_IDLE,
        WED_REQ,
        WED_WAITING_FOR_REQUEST,
        WED_READ_DATA,
        WED_DONE_REQ
    } wed_state;

    typedef struct packed{
        logic [0:31] size_send    ; // 4-Bytes
        logic [0:31] size_recive  ; // 4-Bytes
        logic [0:31] size3        ; // 4-Bytes
        logic [0:63] array_send   ; // 8-Bytes
        logic [0:63] array_receive; // 8-Bytes
        logic [0:63] pointer1     ; // 8-Bytes
        logic [0:63] pointer2     ; // 8-Bytes
        logic [0:63] pointer3     ; // 8-Bytes
        logic [0:63] pointer4     ; // 8-Bytes
        logic [0:63] pointer5     ; // 8-Bytes
        logic [0:63] pointer6     ; // 8-Bytes
        logic [0:63] pointer7     ; // 8-Bytes
        logic [0:63] pointer8     ; // 8-Bytes
        logic [0:63] pointer9     ; // 8-Bytes
        logic [0:63] pointer10    ; // 8-Bytes
        logic [0:63] pointer11    ; // 8-Bytes
        logic [0:63] pointer12    ; // 8-Bytes

        logic [0:31] afu_config   ; // 4-Bytes
    } WED_request;// 108-bytes used from 128-Bytes WED

    typedef struct packed{
        logic        valid  ;
        logic [0:63] address;
        WED_request  wed    ;
    } WEDInterface;


    function WED_request map_DataArrays_to_WED(logic [0:(CACHELINE_SIZE_BITS-1)] in);

        WED_request wed;

        wed.size_send               = swap_endianness_word(in[0:31]);               // 4-Bytes
        wed.size_recive             = swap_endianness_word(in[32:63]);              // 4-Bytes
        wed.size3                   = swap_endianness_word(in[64:95]);              // 4-Bytes

        wed.array_send              = swap_endianness_double_word(in[96:159]);      // 8-Bytes
        wed.array_receive           = swap_endianness_double_word(in[160:223]);     // 8-Bytes
        wed.pointer1                = swap_endianness_double_word(in[224:287]);     // 8-Bytes
        wed.pointer2                = swap_endianness_double_word(in[288:351]);     // 8-Bytes
        wed.pointer3                = swap_endianness_double_word(in[352:415]);     // 8-Bytes
        wed.pointer4                = swap_endianness_double_word(in[416:479]);     // 8-Bytes
        wed.pointer5                = swap_endianness_double_word(in[480:543]);     // 8-Bytes
        wed.pointer6                = swap_endianness_double_word(in[544:607]);     // 8-Bytes
        wed.pointer7                = swap_endianness_double_word(in[608:671]);     // 8-Bytes
        wed.pointer8                = swap_endianness_double_word(in[672:735]);     // 8-Bytes
        wed.pointer9                = swap_endianness_double_word(in[736:799]);     // 8-Bytes
        wed.pointer10               = swap_endianness_double_word(in[800:863]);     // 8-Bytes
        wed.pointer11               = swap_endianness_double_word(in[864:927]);     // 8-Bytes
        wed.pointer12               = swap_endianness_double_word(in[928:991]);     // 8-Bytes
        wed.afu_config              = swap_endianness_word(in[992:1023]);           // 4-Bytes

        return wed;

    endfunction : map_DataArrays_to_WED

    function trans_order_behavior_t map_CABT (logic [0:2] cabt_in);

        trans_order_behavior_t cabt;

        case(cabt_in)
            3'b000 : begin
                cabt = STRICT;
            end
            3'b100 : begin
                cabt = ABORT;
            end
            3'b010 : begin
                cabt = PAGE;
            end
            3'b110 : begin
                cabt = PREF;
            end
            3'b111 : begin
                cabt = SPEC;
            end
            default : begin
                cabt = STRICT;
            end
        endcase

        return cabt;

    endfunction : map_CABT

endpackage