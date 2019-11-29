


#########################################################
#       		 GENERAL DIRECTOIRES   	    			#
#########################################################
# globals binary S
export APP              = capi-precis

# test name
export APP_TEST         = test_capi-precis


# dirs Root app 
export APP_DIR          = .

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

#########################################################
#       		 RUN  ARGUMENTS    						#
#########################################################

export NUM_THREADS  = 8
LHS=32
RHS=257
#test
export SIZE = $(shell echo $(LHS)\*$(RHS) | bc)

#4GB
# export SIZE = 1073741824

#16 GB
# export SIZE = 4294967295

#1GB
# export SIZE = 268435456

export ARGS = -n $(NUM_THREADS) -s $(SIZE)

##############################################
# CAPI FPGA  GRAPH AFU PERFORMANCE CONFIG    #
##############################################

# // cu_read_engine_control            5-bits STRICT | READ_CL_NA | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits STRICT | READ_CL_NA | WRITE_NA 00000 [5:9] [9] [8] [5:7]

# // 0b 00000 00000 00000 00000 00000 00000 00
# export AFU_CONFIG_STRICT_1=0b00000000000000000000000000000000

# // cu_read_engine_control            5-bits ABORT | READ_CL_NA | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits ABORT | READ_CL_NA | WRITE_NA 00000 [5:9] [9] [8] [5:7]

# // 0b 10000 10000 00000 00000 00000 00000 00
# export AFU_CONFIG_STRICT_1=0b10000100000000000000000000000000

# // cu_read_engine_control            5-bits PREF | READ_CL_NA | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits PREF | READ_CL_NA | WRITE_NA 00000 [5:9] [9] [8] [5:7]

# // 0b 11000 11000 00000 00000 00000 00000 00
# export AFU_CONFIG_STRICT_1=0b11000110000000000000000000000000

# // cu_read_engine_control            5-bits PAGE | READ_CL_NA | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits PAGE | READ_CL_NA | WRITE_NA 00000 [5:9] [9] [8] [5:7]

# // 0b 11000 11000 00000 00000 00000 00000 00
# export AFU_CONFIG_STRICT_1=0b01000010000000000000000000000000

# // cu_read_engine_control            5-bits SPEC | READ_CL_NA | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits SPEC | READ_CL_NA | WRITE_NA 00000 [5:9] [9] [8] [5:7]

# // 0b 11000 11000 00000 00000 00000 00000 00
# export AFU_CONFIG_STRICT_1=0b11100111000000000000000000000000

##############################################
# With caches							     #
##############################################

# // cu_read_engine_control            5-bits STRICT | READ_CL_S | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits STRICT | READ_CL_NA | WRITE_MS 00000 [5:9] [9] [8] [5:7]

# // 0b 00010 00001 00000 00000 00000 00000 00
# export AFU_CONFIG_STRICT_1=0b00010000010000000000000000000000

# // cu_read_engine_control            5-bits ABORT | READ_CL_S | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits ABORT | READ_CL_NA | WRITE_MS 00000 [5:9] [9] [8] [5:7]

# // 0b 10010 10001 00000 00000 00000 00000 00
# export AFU_CONFIG_STRICT_1=0b10010100010000000000000000000000

# // cu_read_engine_control            5-bits PREF | READ_CL_S | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits PREF | READ_CL_NA | WRITE_MS 00000 [5:9] [9] [8] [5:7]

# // 0b 11010 11001 00000 00000 00000 00000 00
export AFU_CONFIG_STRICT_1=0b11010110010000000000000000000000

# // cu_read_engine_control            5-bits PAGE | READ_CL_S | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits PAGE | READ_CL_NA | WRITE_MS 00000 [5:9] [9] [8] [5:7]

# // 0b 01010 01001 00000 00000 00000 00000 00
# export AFU_CONFIG_STRICT_1=0b01010010010000000000000000000000

# // cu_read_engine_control            5-bits SPEC | READ_CL_S | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits SPEC | READ_CL_NA | WRITE_MS 00000 [5:9] [9] [8] [5:7]

# // 0b 11110 11101 00000 00000 00000 00000 00
# export AFU_CONFIG_STRICT_1=0b11110111010000000000000000000000

 
export AFU_CONFIG_GENERIC=$(AFU_CONFIG_STRICT_1)
##################################################

APP_DIR           		= .
MAKE_DIR     		 	= 00_bench
MAKE_DIR_SYNTH     		= 01_capi_integration/accelerator_synth

MAKE_NUM_THREADS  		= $(shell grep -c ^processor /proc/cpuinfo)
MAKE_ARGS 				= -w -C $(APP_DIR)/$(MAKE_DIR) -j$(MAKE_NUM_THREADS)
MAKE_ARGS_SYNTH 		= -w -C $(APP_DIR)/$(MAKE_DIR_SYNTH) -j$(MAKE_NUM_THREADS)
##################################################
##################################################

##############################################
#         		ACCEL TOP LEVEL RULES        #
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

.PHONY: clean-all
clean-all: clean clean-sim clean-synth

##################################################
##################################################

##############################################
#      		ACCEL CAPI TOP LEVEL RULES      #
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

##############################################
#      		ACCEL SYNTHESIZE LEVEL RULES     #
##############################################

.PHONY: run-capi-synth
run-capi-synth:
	 $(MAKE) all $(MAKE_ARGS_SYNTH)

.PHONY: map
map:
	 $(MAKE) map $(MAKE_ARGS_SYNTH)

.PHONY: fit
fit:
	 $(MAKE) fit $(MAKE_ARGS_SYNTH)

.PHONY: asm
asm:
	 $(MAKE) asm $(MAKE_ARGS_SYNTH)

.PHONY: sta
sta:
	 $(MAKE) sta $(MAKE_ARGS_SYNTH)

.PHONY: qxp
qxp:
	 $(MAKE) qxp $(MAKE_ARGS_SYNTH)

.PHONY: rbf
rbf:
	 $(MAKE) rbf $(MAKE_ARGS_SYNTH)

.PHONY: smart
smart:
	 $(MAKE) smart $(MAKE_ARGS_SYNTH)

.PHONY: clean-synth
clean-synth:
	 $(MAKE) clean $(MAKE_ARGS_SYNTH)
##################################################
##################################################