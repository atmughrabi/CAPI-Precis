


#########################################################
#       		 GENERAL DIRECTOIRES   	    			#
#########################################################
# globals binary S
export APP               = capi-precis

# test name
export APP_TEST         = test_capi-precis


# dirs Root app 
export APP_DIR           = .

#dir root/managed_folders
export SRC_DIR           = src
export OBJ_DIR			 = obj
export INC_DIR			 = include
export BIN_DIR			 = bin

#if you want to compile from cmake you need this directory
#cd build
#cmake ..
export BUILD_DIR		= build

# relative directories used for managing src/obj files
export ALGO_DIR		  	= algorithms
export UTIL_DIR		  	= utils
export CAPI_UTIL_DIR	= capi_utils

#contains the tests use make run-test to compile what in this directory
export TEST_DIR		  	= tests

#contains the main for the graph processing framework
export MAIN_DIR		  	= main

##############################################
# CAPI FPGA  GRAPH AFU PERFORMANCE CONFIG    #
##############################################
# // cu_vertex_job_control        5-bits STRICT | READ_CL_NA | WRITE_NA 00000 [27:31] [4] [3] [0:2]
# // cu_edge_job_control          5-bits STRICT | READ_CL_NA | WRITE_NA 00000 [22:26] [9] [8] [5:7]
# // cu_edge_data_control         5-bits STRICT | READ_CL_NA | WRITE_NA 00000 [22:26] [14] [13] [10:12]
# // cu_edge_data_write_control   5-bits STRICT | READ_CL_NA | WRITE_NA 00000 [22:26] [19] [18] [15:17]
# // 0b 00000 00000 00000 00000 00000 00000 00
export AFU_CONFIG_STRICT_1=0x00000000  
# // cu_vertex_job_control        5-bits STRICT | READ_CL_NA | WRITE_NA 00000 [27:31] [4] [3] [0:2]
# // cu_edge_job_control          5-bits STRICT | READ_CL_NA | WRITE_NA 00000 [22:26] [9] [8] [5:7]
# // cu_edge_data_control         5-bits STRICT | READ_CL_S  | WRITE_NA 00010 [22:26] [14] [13] [10:12]
# // cu_edge_data_write_control   5-bits STRICT | READ_CL_NA | WRITE_MS 00001 [22:26] [19] [18] [15:17]
# // 0b 00000 00000 00010 00001 00000 00000 00
export AFU_CONFIG_STRICT_2=0x00041000  

# // cu_vertex_job_control        5-bits ABORT | READ_CL_NA | WRITE_NA 10000 [27:31] [4] [3] [0:2]
# // cu_edge_job_control          5-bits ABORT | READ_CL_NA | WRITE_NA 10000 [22:26] [9] [8] [5:7]
# // cu_edge_data_control         5-bits ABORT | READ_CL_S  | WRITE_NA 10010 [22:26] [14] [13] [10:12]
# // cu_edge_data_write_control   5-bits ABORT | READ_CL_NA | WRITE_MS 10001 [22:26] [19] [18] [15:17]
#  // 0b 10000 10000 10010 10001 00000 00000 00
export AFU_CONFIG_ABORT_1=0x84251000 

# // cu_vertex_job_control        5-bits PREF | READ_CL_NA | WRITE_NA 11000 [27:31] [4] [3] [0:2]
# // cu_edge_job_control          5-bits PREF | READ_CL_NA | WRITE_NA 11000 [22:26] [9] [8] [5:7]
# // cu_edge_data_control         5-bits PREF | READ_CL_NA | WRITE_NA 11000 [22:26] [14] [13] [10:12]
# // cu_edge_data_write_control   5-bits PREF | READ_CL_NA | WRITE_NA 11000 [22:26] [19] [18] [15:17]
# // 0b 11000 11000 11000 11000 00000 00000 00
export AFU_CONFIG_PREF_1=0xC6318000  

# // cu_vertex_job_control        5-bits PREF | READ_CL_NA | WRITE_NA 11000 [27:31] [4] [3] [0:2]
# // cu_edge_job_control          5-bits PREF | READ_CL_NA | WRITE_NA 11000 [22:26] [9] [8] [5:7]
# // cu_edge_data_control         5-bits PREF | READ_CL_S  | WRITE_NA 11010 [22:26] [14] [13] [10:12]
# // cu_edge_data_write_control   5-bits PREF | READ_CL_NA | WRITE_MS 11001 [22:26] [19] [18] [15:17]
# // 0b 11000 11000 11010 11001 00000 00000 00
export AFU_CONFIG_PREF_2=0xC6359000 
 
export AFU_CONFIG_GENERIC=$(AFU_CONFIG_PREF_2)
##################################################

APP_DIR           	= .
MAKE_DIR      = 00_bench
MAKE_NUM_THREADS  	= $(shell grep -c ^processor /proc/cpuinfo)
MAKE_ARGS = -w -C $(APP_DIR)/$(MAKE_DIR) -j$(MAKE_NUM_THREADS)

##################################################
##################################################

##############################################
#         ACCEL GRAPH TOP LEVEL RULES        #
##############################################

.PHONY: help
help:
	$(MAKE) help $(MAKE_ARGS)

.PHONY: run
run:
	$(MAKE) run $(MAKE_ARGS)

.PHONY: run-openmp
run-openmp:
	$(MAKE) run-openmp $(MAKE_ARGS)

.PHONY: debug-openmp
debug-openmp: 
	$(MAKE) debug-openmp $(MAKE_ARGS)

.PHONY: debug-memory-openmp
debug-memory-openmp: 
	$(MAKE) debug-memory-openmp $(MAKE_ARGS)

.PHONY: test-verbose
test-verbose:
	$(MAKE) test-verbose $(MAKE_ARGS)
	
# test files
.PHONY: test
test:
	$(MAKE) test $(MAKE_ARGS)
	
.PHONY: run-test
run-test: 
	$(MAKE) run-test $(MAKE_ARGS)

.PHONY: run-test-openmp
run-test-openmp:
	$(MAKE) run-test-openmp $(MAKE_ARGS)

.PHONY: debug-test-openmp
debug-test-openmp: 
	$(MAKE) debug-test-openmp $(MAKE_ARGS)

.PHONY: debug-memory-test-openmp
debug-memory-test-openmp:	
	$(MAKE) debug-memory-test-openmp $(MAKE_ARGS)
# cache performance
.PHONY: cachegrind-perf-openmp
cachegrind-perf-openmp:
	$(MAKE) cachegrind-perf-openmp $(MAKE_ARGS)

.PHONY: cache-perf
cache-perf-openmp: 
	$(MAKE) cache-perf-openmp $(MAKE_ARGS)

.PHONY: clean
clean: 
	$(MAKE) clean $(MAKE_ARGS)

.PHONY: clean-obj
clean-obj: 
	$(MAKE) clean-obj $(MAKE_ARGS)

##################################################
##################################################

##############################################
#      ACCEL GRAPH CAPI TOP LEVEL RULES      #
##############################################

.PHONY: run-capi-sim
run-capi-sim:
	$(MAKE) run-capi-sim $(MAKE_ARGS)

.PHONY: run-capi-fpga
run-capi-fpga:
	$(MAKE) run-capi-fpga $(MAKE_ARGS)

.PHONY: run-capi-sim-verbose
run-capi-sim-verbose:
	$(MAKE) run-capi-sim-verbose $(MAKE_ARGS)

.PHONY: run-capi-fpga-verbose
run-capi-fpga-verbose:
	$(MAKE) run-capi-fpga-verbose $(MAKE_ARGS)

.PHONY: run-test-capi
run-test-capi:
	$(MAKE) run-test-capi $(MAKE_ARGS)

.PHONY: run-vsim
run-vsim:
	$(MAKE) run-vsim $(MAKE_ARGS)

.PHONY: run-pslse
run-pslse:
	$(MAKE) run-pslse $(MAKE_ARGS)

.PHONY: build-pslse
build-pslse:
	  $(MAKE) build-pslse $(MAKE_ARGS)

.PHONY: clean-sim
clean-sim:
	 $(MAKE) clean-sim $(MAKE_ARGS)
##################################################
##################################################