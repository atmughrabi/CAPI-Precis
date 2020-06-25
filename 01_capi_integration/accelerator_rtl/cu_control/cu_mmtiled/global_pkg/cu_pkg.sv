// -----------------------------------------------------------------------------
//
//      "CAPIPrecis Shared Memory Accelerator Project"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi atmughrabi@gmail.com/atmughra@ncsu.edu
// File   : cu_pkg.sv
// Create : 2019-09-26 15:20:09
// Revise : 2019-12-06 22:28:51
// Editor : sublime text3, tab size (4)
// -----------------------------------------------------------------------------

package CU_PKG;

// Relating to array int types and sizes
    import GLOBALS_AFU_PKG::*;
    import GLOBALS_CU_PKG::*;

    typedef enum int unsigned {
        SEND_MATRIX_C_RESET,
        SEND_MATRIX_C_INIT,
        SEND_MATRIX_C_IDLE,
        START_MATRIX_C_REQ,
        CALC_MATRIX_C_REQ_SIZE,
        SEND_MATRIX_C_START,
        SEND_MATRIX_C_DATA_READ,
        WAIT_MATRIX_C_DATA,
        SHIFT_MATRIX_C_DATA_START,
        SHIFT_MATRIX_C_DATA_0,
        SHIFT_MATRIX_C_DATA_DONE_0,
        SHIFT_MATRIX_C_DATA_1,
        SHIFT_MATRIX_C_DATA_DONE_1
    } matrix_C_struct_state;


    typedef enum int unsigned{
        STRUCT_INVALID,
        MATRIX_C_DATA_READ,
        MATRIX_C_DATA_WRITE,
        MATRIX_A_DATA_READ,
        MATRIX_B_DATA_READ
    } array_struct_type;

    typedef struct packed {
        logic [     0:(ARRAY_SIZE_BITS-1)] ii          ;
        logic [     0:(ARRAY_SIZE_BITS-1)] jj          ;
        logic [0:(DATA_SIZE_READ_BITS-1)] data        ;
    } MatrixCInterfacePayload;

    typedef struct packed {
        logic                   valid  ;
        MatrixCInterfacePayload payload;
    } MatrixCInterface;

    typedef struct packed {
        cu_id_t                           cu_id_x;
        cu_id_t                           cu_id_y;
        logic [0:(DATA_SIZE_READ_BITS-1)] data   ;
    } MatrixDataReadPayload;

    typedef struct packed {
        logic                 valid  ;
        MatrixDataReadPayload payload;
    } MatrixDataRead;

    typedef struct packed {
        cu_id_t                            cu_id_x     ;
        cu_id_t                            cu_id_y     ;
        logic [     0:(ARRAY_SIZE_BITS-1)] ii_jj_offset;
        logic [0:(DATA_SIZE_WRITE_BITS-1)] data        ;
    } MatrixDataWritePayload;

    typedef struct packed {
        logic                  valid  ;
        MatrixDataWritePayload payload;
    } MatrixDataWrite;



    function logic [0:DATA_SIZE_WRITE_BITS-1] swap_endianness_data_write(logic [0:DATA_SIZE_WRITE_BITS-1] in);

        logic [0:DATA_SIZE_WRITE_BITS-1] out;

        integer i;
        for ( i = 0; i < DATA_SIZE_WRITE; i++) begin
            out[i*8 +: 8] = in[((DATA_SIZE_WRITE_BITS-1)-(i*8)) -:8];
        end

        return out;
    endfunction : swap_endianness_data_write

    function logic [0:DATA_SIZE_READ_BITS-1] swap_endianness_data_read(logic [0:DATA_SIZE_READ_BITS-1] in);

        logic [0:DATA_SIZE_READ_BITS-1] out;

        integer i;
        for ( i = 0; i < DATA_SIZE_READ; i++) begin
            out[i*8 +: 8] = in[((DATA_SIZE_READ_BITS-1)-(i*8)) -:8];
        end

        return out;
    endfunction : swap_endianness_data_read




    function logic [0:ARRAY_SIZE_BITS-1] swap_endianness_array_read(logic [0:ARRAY_SIZE_BITS-1] in);

        logic [0:ARRAY_SIZE_BITS-1] out;

        integer i;
        for ( i = 0; i < ARRAY_SIZE; i++) begin
            out[i*8 +: 8] = in[((ARRAY_SIZE_BITS-1)-(i*8)) -:8];
        end

        return out;
    endfunction : swap_endianness_array_read


// Read/write commands require the size to be a power of 2 (1, 2, 4, 8, 16, 32,64, 128).
    function logic [0:11] cmd_size_calculate(logic [0:(ARRAY_SIZE_BITS-1)]  num_counter);

        logic [0:(ARRAY_SIZE_BITS-1)] num_size;
        logic [0:11] request_size;

        num_size = (num_counter << $clog2(ARRAY_SIZE));

        if (num_size > 64)
            request_size = 128;
        else if (num_size > 32)
            request_size = 64;
        else if (num_size > 16)
            request_size = 32;
        else if (num_size > 8)
            request_size = 16;
        else if (num_size > 4)
            request_size = 8;
        else if (num_size > 2)
            request_size = 4;
        else if (num_size > 1)
            request_size = 2;
        else if (num_size > 0)
            request_size = 1;
        else
            request_size = 0;

        return request_size;

    endfunction : cmd_size_calculate

endpackage