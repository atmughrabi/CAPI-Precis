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
    // import GLOBALS_CU_PKG::*;

    // This is important for the AFU control layer change to reflect the structures you want to process
    typedef enum int unsigned{
        STRUCT_INVALID,
        READ_DATA,
        WRITE_DATA,
        PREFETCH_DATA
    } array_struct_type;

    

endpackage