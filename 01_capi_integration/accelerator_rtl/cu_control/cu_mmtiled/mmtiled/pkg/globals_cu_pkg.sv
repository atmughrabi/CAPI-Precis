// -----------------------------------------------------------------------------
//
//      "CAPIPrecis Shared Memory Accelerator Project"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi atmughrabi@gmail.com/atmughra@ncsu.edu
// File   : globals_pkg.sv
// Create : 2019-09-26 15:20:15
// Revise : 2019-12-07 03:18:15
// Editor : sublime text3, tab size (4)
// -----------------------------------------------------------------------------

package GLOBALS_CU_PKG;

    import GLOBALS_AFU_PKG::*;

////////////////////////////////////////////////////////////////////////////
// CU-Control CU Globals
////////////////////////////////////////////////////////////////////////////

// How many compute unites you want : each 1  contains N read/write engines
// TOTAL CUS = NUM_DATA_READ_CU_GLOBAL + NUM_DATA_WRITE_CU_GLOBAL
////////////////////////////////////////////////////////////////////////////

    parameter NUM_X_CU_GLOBAL    = 8  ;
    parameter NUM_Y_CU_GLOBAL    = 8  ;
    parameter CU_JOB_BUFFER_SIZE = 256;

////////////////////////////////////////////////////////////////////////////
// CU-Control CU Globals
////////////////////////////////////////////////////////////////////////////

//  Sturctue sizes
////////////////////////////////////////////////////////////////////////////

    parameter ARRAY_SIZE           = 8                  ; // array size is n bytes
    parameter ARRAY_SIZE_BITS      = ARRAY_SIZE * 8     ; // array size is n*8 Bits
    parameter DATA_SIZE_READ       = 4                  ; // data size is n bytes
    parameter DATA_SIZE_READ_BITS  = DATA_SIZE_READ * 8 ; // data size is n*8 Bits
    parameter DATA_SIZE_WRITE      = 4                  ; // data size is n bytes
    parameter DATA_SIZE_WRITE_BITS = DATA_SIZE_WRITE * 8; // data size is n*8 Bits

// aligenment to cacheline 128-BYTES

    parameter [0:63] ADDRESS_ARRAY_ALIGN_MASK = {{57{1'b1}},{7{1'b0}}};
    parameter [0:63] ADDRESS_ARRAY_MOD_MASK   = {{57{1'b0}},{7{1'b1}}};

    parameter [0:63] ADDRESS_DATA_READ_ALIGN_MASK = {{57{1'b1}},{7{1'b0}}};
    parameter [0:63] ADDRESS_DATA_READ_MOD_MASK   = {{57{1'b0}},{7{1'b1}}};

    parameter [0:63] ADDRESS_DATA_WRITE_ALIGN_MASK = {{57{1'b1}},{7{1'b0}}};
    parameter [0:63] ADDRESS_DATA_WRITE_MOD_MASK   = {{57{1'b0}},{7{1'b1}}};

    parameter CACHELINE_INT_COUNTER_BITS = $clog2((DATA_SIZE_READ_BITS < CACHELINE_SIZE_BITS_HF) ? (2 * CACHELINE_SIZE_BITS_HF)/DATA_SIZE_READ_BITS : 2);

    parameter CACHELINE_ARRAY_NUM = (CACHELINE_SIZE >> $clog2(DATA_SIZE_READ)); // number of  in one cacheline
    parameter PAGE_ARRAY_NUM      = (PAGE_SIZE >> $clog2(DATA_SIZE_READ))     ; // number of  in one page

////////////////////////////////////////////////////////////////////////////
//  CU-Control CU IDs any compute unite that generate command must have an ID
////////////////////////////////////////////////////////////////////////////

    parameter PREFETCH_READ_CONTROL_ID  = (RESTART_ID - 1)              ;
    parameter PREFETCH_WRITE_CONTROL_ID = (PREFETCH_READ_CONTROL_ID - 1);


    parameter MATRIX_C_CONTROL_ID   = (PREFETCH_WRITE_CONTROL_ID - 1);
    parameter MATRIX_A_B_CONTROL_ID = (MATRIX_C_CONTROL_ID - 1)      ;

endpackage