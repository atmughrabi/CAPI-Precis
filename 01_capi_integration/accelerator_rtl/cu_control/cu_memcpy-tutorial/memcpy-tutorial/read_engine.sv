import GLOBALS_AFU_PKG::*;
import GLOBALS_CU_PKG::*;
import CAPI_PKG::*;
import WED_PKG::*;
import AFU_PKG::*;
import CU_PKG::*;

module read_engine #(parameter CU_READ_CONTROL_ID = DATA_READ_CONTROL_ID) (
	input  logic                         clock                         , // Clock
	input  logic                         rstn                          ,
	input  logic                         read_enabled_in               ,
	input  WEDInterface                  wed_request_in                ,
	input  ResponseBufferLine            read_response_in              ,
	input  ReadWriteDataLine             read_data_0_in                ,
	input  ReadWriteDataLine             read_data_1_in                ,
	input  BufferStatus                  read_command_buffer_status    ,
	input  BufferStatus                  read_data_out_buffer_status   ,
	output CommandBufferLine             read_command_out              ,
	output ReadWriteDataLine             read_data_0_out               ,
	output ReadWriteDataLine             read_data_1_out               ,
	output logic [0:(ARRAY_SIZE_BITS-1)] read_job_counter_done
);




endmodule : cu_data_read_engine_control