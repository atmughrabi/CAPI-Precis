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

    parameter NUM_X_CU_GLOBAL    = 2 ;
    parameter NUM_Y_CU_GLOBAL    = 2 ;
    parameter CU_MATRIX_C_JOB_BUFFER_SIZE = 64;

////////////////////////////////////////////////////////////////////////////
// CU-Control CU Globals
////////////////////////////////////////////////////////////////////////////

//  Sturctue sizes
////////////////////////////////////////////////////////////////////////////

    parameter ARRAY_SIZE                  = 8                                          ; // array size is n bytes
    parameter ARRAY_SIZE_BITS             = ARRAY_SIZE * 8                             ; // array size is n*8 Bits
    parameter CACHELINE_ARRAY_SIZE_NUM    = (CACHELINE_SIZE >> $clog2(ARRAY_SIZE))     ;
    parameter CACHELINE_ARRAY_SIZE_NUM_HF = (CACHELINE_SIZE >> $clog2(ARRAY_SIZE)) >> 1; // number of vertices in one cacheline
    parameter ARRAY_SIZE_NULL_BITS        = {ARRAY_SIZE_BITS{1'b0}}                    ; ;

    parameter DATA_SIZE_READ               = 4                                              ; // edge data size is n bytes Auxiliary1
    parameter DATA_SIZE_READ_BITS          = DATA_SIZE_READ * 8                             ; // edge data size is n*8 Bits
    parameter CACHELINE_DATA_READ_NUM      = (CACHELINE_SIZE >> $clog2(DATA_SIZE_READ))     ;
    parameter CACHELINE_DATA_READ_NUM_HF   = (CACHELINE_SIZE >> $clog2(DATA_SIZE_READ)) >> 1;
    parameter CACHELINE_DATA_READ_NUM_BITS = $clog2(CACHELINE_DATA_READ_NUM)                ; // number of edges in one cacheline
    parameter DATA_SIZE_READ_NULL_BITS     = {DATA_SIZE_READ_BITS{1'b0}}                    ;

    parameter DATA_SIZE_WRITE             = 4                                               ; // edge data size is n bytes Auxiliary2
    parameter DATA_SIZE_WRITE_BITS        = DATA_SIZE_WRITE * 8                             ; // edge data size is n*8 Bits
    parameter CACHELINE_DATA_WRITE_NUM    = (CACHELINE_SIZE >> $clog2(DATA_SIZE_WRITE))     ;
    parameter CACHELINE_DATA_WRITE_NUM_HF = (CACHELINE_SIZE >> $clog2(DATA_SIZE_WRITE)) >> 1; // number of edges in one cacheline
    parameter DATA_SIZE_WRITE_NULL_BITS   = {DATA_SIZE_WRITE_BITS{1'b0}}                    ;

    // aligenment to cacheline 128-BYTES
    parameter [0:63] ADDRESS_ARRAY_ALIGN_MASK = {{57{1'b1}},{7{1'b0}}};
    parameter [0:63] ADDRESS_ARRAY_MOD_MASK   = {{57{1'b0}},{7{1'b1}}};

    parameter [0:63] ADDRESS_DATA_READ_ALIGN_MASK = {{57{1'b1}},{7{1'b0}}};
    parameter [0:63] ADDRESS_DATA_READ_MOD_MASK   = {{57{1'b0}},{7{1'b1}}};

    parameter [0:63] ADDRESS_DATA_WRITE_ALIGN_MASK = {{57{1'b1}},{7{1'b0}}};
    parameter [0:63] ADDRESS_DATA_WRITE_MOD_MASK   = {{57{1'b0}},{7{1'b1}}};

    parameter [0:63] ADDRESS_EDGE_ALIGN_MASK = {{57{1'b1}},{7{1'b0}}};
    parameter [0:63] ADDRESS_EDGE_MOD_MASK   = {{57{1'b0}},{7{1'b1}}};

    parameter CACHELINE_INT_COUNTER_BITS = $clog2(CACHELINE_SIZE);

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