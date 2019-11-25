// -----------------------------------------------------------------------------
//
//		"ACCEL-GRAPH Shared Memory Accelerator Project"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi atmughrabi@gmail.com/atmughra@ncsu.edu
// File   : cu_data_write_engine_control.sv
// Create : 2019-11-18 16:55:32
// Revise : 2019-11-25 00:49:44
// Editor : sublime text3, tab size (4)
// -----------------------------------------------------------------------------

import GLOBALS_PKG::*;
import CAPI_PKG::*;
import WED_PKG::*;
import AFU_PKG::*;
import CU_PKG::*;

module cu_data_write_engine_control (
	input  logic                         clock                      , // Clock
	input  logic                         rstn                       ,
	input  logic                         enabled_in                 ,
	input  WEDInterface                  wed_request_in             ,
	input  ResponseBufferLine            write_response_in          ,
	input  ReadWriteDataLine             write_data_0_in            ,
	input  ReadWriteDataLine             write_data_1_in            ,
	input  BufferStatus                  write_command_buffer_status,
	output CommandBufferLine             write_command_out          ,
	output ReadWriteDataLine             write_data_0_out           ,
	output ReadWriteDataLine             write_data_1_out           ,
	output logic [0:(ARRAY_SIZE_BITS-1)] write_job_counter_done
);

	assign write_command_out      = 0;
	assign write_data_0_out       = 0;
	assign write_data_1_out       = 0;
	assign write_job_counter_done = 0;


	

endmodule