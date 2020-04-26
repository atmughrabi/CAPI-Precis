
#########################################################
#                GENERAL DIRECTOIRES                    #
#########################################################
# globals binaary /bin/capi-precis name doesn't need to match main/capi-precis.c
  APP               ?= capi-precis
  CU_ALGORITHM 	 	?= memcpy
# test name needs to match the file name test/test_capi-precis.c
  APP_TEST          = test_afu
#   APP_TEST          ?= test_capi-precis

# dirs Root app
APP_DIR             ?= .
CAPI_INTEG_DIR      ?= 01_capi_integration
SCRIPT_DIR          ?= 03_scripts

#dir root/managed_folders
SRC_DIR             ?= src
OBJ_DIR             ?= obj
INC_DIR             ?= include
BIN_DIR             ?= bin

#if you want to compile from cmake you need this directory
#cd build
#cmake ..
BUILD_DIR           ?= build

# relative directories used for managing src/obj files
ALGO_DIR            ?= algorithms
UTIL_DIR            ?= utils
CAPI_UTIL_DIR       ?= capi_utils

#contains the tests use make run-test to compile what in this directory
TEST_DIR            ?= tests

#contains the main for the accel processing framework
MAIN_DIR            ?= main

##################################################
##################################################

##############################################
# CAPI FPGA AFU PERFORMANCE CONFIG           #
##############################################

# STRICT 0b000
# ABORT  0b001
# PAGE   0b010
# PREF   0b011
# SPEC   0b111

# READ_CL_S    0b1
# READ_CL_NA   0b0
# WRITE_MS     0b1
# WRITE_NA     0b0

# // cu_read_engine_control            5-bits STRICT | READ_CL_NA | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits STRICT | READ_CL_NA | WRITE_NA 00000 [5:9] [9] [8] [5:7]

# // 0b 00000 00000 00000 00000 00000 00000 00
# export CU_CONFIG_MODE=0b00000000000000000000000000000000
CU_CONFIG_MODE?=0x00000$(ENABLE_RD_WR)$(RD_WR_PREFETCH_MODE)$(ENABLE_RD_WR_PREFETCH)$(TLB_SHIFT)$(TLB_SHIFT_DIRECTION)

# // cu_read_engine_control            5-bits ABORT | READ_CL_NA | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits ABORT | READ_CL_NA | WRITE_NA 00000 [5:9] [9] [8] [5:7]

# // 0b 10000 10000 00000 00000 00000 00000 00
# export CU_CONFIG_MODE=0b10000100000000000000000000000000
# export CU_CONFIG_MODE=0x84000$(ENABLE_RD_WR)$(RD_WR_PREFETCH_MODE)$(ENABLE_RD_WR_PREFETCH)

# // cu_read_engine_control            5-bits PREF | READ_CL_NA | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits PREF | READ_CL_NA | WRITE_NA 00000 [5:9] [9] [8] [5:7]

# // 0b 11000 11000 00000 00000 00000 00000 00
# export CU_CONFIG_MODE=0b11000110000000000000000000000000
# export CU_CONFIG_MODE=0xC6000$(ENABLE_RD_WR)$(RD_WR_PREFETCH_MODE)$(ENABLE_RD_WR_PREFETCH)

# // cu_read_engine_control            5-bits PAGE | READ_CL_NA | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits PAGE | READ_CL_NA | WRITE_NA 00000 [5:9] [9] [8] [5:7]

# // 0b 11000 11000 00000 00000 00000 00000 00
# export CU_CONFIG_MODE=0b01000010000000000000000000000000
# export CU_CONFIG_MODE=0x42000$(ENABLE_RD_WR)$(RD_WR_PREFETCH_MODE)$(ENABLE_RD_WR_PREFETCH)

# // cu_read_engine_control            5-bits SPEC | READ_CL_NA | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits SPEC | READ_CL_NA | WRITE_NA 00000 [5:9] [9] [8] [5:7]

# // 0b 11000 11000 00000 00000 00000 00000 00
# export CU_CONFIG_MODE=0b11100111000000000000000000000000
# export CU_CONFIG_MODE=0xE7000$(ENABLE_RD_WR)$(RD_WR_PREFETCH_MODE)$(ENABLE_RD_WR_PREFETCH)

##############################################
# With caches                                #
##############################################

# // cu_read_engine_control            5-bits STRICT | READ_CL_S | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits STRICT | READ_CL_NA | WRITE_MS 00000 [5:9] [9] [8] [5:7]

# export CU_CONFIG_MODE=0x10400$(ENABLE_RD_WR)$(RD_WR_PREFETCH_MODE)$(ENABLE_RD_WR_PREFETCH)
# // 0b 00010 00001 00000 00000 00000 00000 00
# export CU_CONFIG_MODE=0b00010000010000000000000000000000
# export CU_CONFIG_MODE=0x21000$(ENABLE_RD_WR)$(RD_WR_PREFETCH_MODE)$(ENABLE_RD_WR_PREFETCH)

# // cu_read_engine_control            5-bits ABORT | READ_CL_S | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits ABORT | READ_CL_NA | WRITE_MS 00000 [5:9] [9] [8] [5:7]

# // 0b 10010 10001 00000 00000 00000 00000 00
# export CU_CONFIG_MODE=0b10010100010000000000000000000000
# export CU_CONFIG_MODE=0x94400$(ENABLE_RD_WR)$(RD_WR_PREFETCH_MODE)$(ENABLE_RD_WR_PREFETCH)

# // cu_read_engine_control            5-bits PREF | READ_CL_S | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits PREF | READ_CL_NA | WRITE_MS 00000 [5:9] [9] [8] [5:7]

# // 0b 11010 11001 00000 00000 00000 00000 00
# export CU_CONFIG_MODE=0b11010110010000000000000000000000
# export CU_CONFIG_MODE=0xD6400$(ENABLE_RD_WR)$(RD_WR_PREFETCH_MODE)$(ENABLE_RD_WR_PREFETCH)

# // cu_read_engine_control            5-bits PAGE | READ_CL_S | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits PAGE | READ_CL_NA | WRITE_MS 00000 [5:9] [9] [8] [5:7]

# // 0b 01010 01001 00000 00000 00000 00000 00
# export CU_CONFIG_MODE=0b01010010010000000000000000000000
# export CU_CONFIG_MODE=0x52400$(ENABLE_RD_WR)$(RD_WR_PREFETCH_MODE)$(ENABLE_RD_WR_PREFETCH)

# // cu_read_engine_control            5-bits SPEC | READ_CL_S | WRITE_NA 00000 [0:4] [4] [3] [0:2]
# // cu_write_engine_control           5-bits SPEC | READ_CL_NA | WRITE_MS 00000 [5:9] [9] [8] [5:7]

# // 0b 11110 11101 00000 00000 00000 00000 00
# export CU_CONFIG_MODE=0b11110111010000000000000000000000
# export CU_CONFIG_MODE=0xF7400$(ENABLE_RD_WR)$(RD_WR_PREFETCH_MODE)$(ENABLE_RD_WR_PREFETCH)

##############################################
# CAPI FPGA TLB PREFETCH CONFIG              #
##############################################

# [32:35]
# [36:39]

# shift amount
TLB_SHIFT?=b

#0 left | #1 right | example (2048 >> 1)
TLB_SHIFT_DIRECTION?=1

##############################################
# CAPI FPGA AFU PREFETCH CONFIG              #
##############################################

#disable both engines
# ENABLE_RD_WR=0
#enable read engine
# ENABLE_RD_WR=1
# enable write engine dependent (nothing to write)
# ENABLE_RD_WR=2
# enable write engine independent
# ENABLE_RD_WR=4
# enable both engines  dependent
ENABLE_RD_WR?=3
#enable both engines independent
# ENABLE_RD_WR=5

#disable both PREFETCH
# ENABLE_RD_WR_PREFETCH=0
#enable write PREFETCH
# ENABLE_RD_WR_PREFETCH=1
#enable read PREFETCH
# ENABLE_RD_WR_PREFETCH=2
#enable both PREFETCH
ENABLE_RD_WR_PREFETCH?=3

#disable both page address based
# RD_WR_PREFETCH_MODE=0
#cacheline-read page-wrtie address based
# RD_WR_PREFETCH_MODE=1
# cacheline-write page-read address based
# RD_WR_PREFETCH_MODE=2
# both cacheline address based
RD_WR_PREFETCH_MODE?=3

##############################################
# CAPI FPGA AFU ARBITER CONFIG               #
##############################################
# shift credits >>
# read_credits            [0:3]
# write_credits           [4:7]
# prefetch_read_credits   [8:11]
# prefetch_write_credits  [12:15]
# FIXED_ARB               [62]
# ROUND_ROBIN_ARB         [63]

ROUND_ROBIN_ARB?=0x1111000000000001
FIXED_ARB?=0x1111000000000002

##############################################
# CAPI FPGA AFU/CU      CONFIG               #
##############################################

AFU_CONFIG_MODE?=$(ROUND_ROBIN_ARB)
# AFU_CONFIG_MODE=$(FIXED_ARB)

CU_CONFIG_GENERIC?=$(CU_CONFIG_MODE)
AFU_CONFIG_GENERIC?=$(AFU_CONFIG_MODE))


##################################################
ARGS ?= -n $(NUM_THREADS) -s $(SIZE) -a $(AFU_CONFIG_GENERIC) -c $(CU_CONFIG_GENERIC) -m $(ENABLE_RD_WR)
##################################################
##################################################

##############################################
#      ACCEL APP   COMPILATION VARIABLES     #
##############################################


#each implementation is contained in a separate folder. when you compile for openmp for example the files in openmp folder gets included
SRC_FILES_ALGO_OPENMP       =   $(wildcard $(APP_DIR)/$(SRC_DIR)/$(ALGO_DIR)/openmp/*.c)

SRC_FILES_UTIL      =   $(wildcard $(APP_DIR)/$(SRC_DIR)/$(UTIL_DIR)/*.c)
SRC_FILES_MAIN      =   $(wildcard $(APP_DIR)/$(SRC_DIR)/$(MAIN_DIR)/*.c)
SRC_FILES_TEST      =   $(wildcard $(APP_DIR)/$(SRC_DIR)/$(TEST_DIR)/*.c)

#create object file rules for the final binary target
OBJ_FILES_ALGO_OPENMP       = $(patsubst $(APP_DIR)/$(SRC_DIR)/$(ALGO_DIR)/openmp/%.c,$(APP_DIR)/$(OBJ_DIR)/$(ALGO_DIR)/openmp/%.o,$(SRC_FILES_ALGO_OPENMP))

OBJ_FILES_UTIL      = $(patsubst $(APP_DIR)/$(SRC_DIR)/$(UTIL_DIR)/%.c,$(APP_DIR)/$(OBJ_DIR)/$(UTIL_DIR)/%.o,$(SRC_FILES_UTIL))
OBJ_FILES_MAIN      = $(patsubst $(APP_DIR)/$(SRC_DIR)/$(MAIN_DIR)/%.c,$(APP_DIR)/$(OBJ_DIR)/$(MAIN_DIR)/%.o,$(SRC_FILES_MAIN))
OBJ_FILES_TEST      = $(patsubst $(APP_DIR)/$(SRC_DIR)/$(TEST_DIR)/%.c,$(APP_DIR)/$(OBJ_DIR)/$(TEST_DIR)/%.o,$(SRC_FILES_TEST))

CC                = gcc

OPENMP_INC =    -I$(APP_DIR)/$(INC_DIR)/$(ALGO_DIR)/openmp  \
				-I$(APP_DIR)/$(INC_DIR)/$(UTIL_DIR)

# flags
CFLAGS   =  -O3 -Wall -m64 -fopenmp -g
LFLAGS = -lm


# TEST PASS OR FAIL
PASS = \033[92mPASS\033[0m
FAIL = \033[91mFAIL\033[0m

##################################################
##################################################

##############################################
#      CAPI        COMPILATION VARIABLES     #
##############################################

ARCHITECTURE = $(shell uname -p) # store the output of the command in a variable if on intel run simulation if power8 run fpga

PSLSE_DIR         = ../$(CAPI_INTEG_DIR)/pslse
LIBCXL_DIR        = ../$(CAPI_INTEG_DIR)/libcxl
CAPI_UTILS_DIR    = ../$(CAPI_INTEG_DIR)/capi-utils
CAPI_ACCEL		  = ../$(CAPI_INTEG_DIR)/accelerator_rtl
CAPI_COMMON		  = ../$(CAPI_INTEG_DIR)/accelerator_sim

CAPI_SIM          = $(CAPI_COMMON)/sim
CAPI_SERVER       = $(CAPI_COMMON)/server


PSLSE_COMMON_DIR  = $(PSLSE_DIR)/common
# PSLSE_LIBCXL_DIR  = $(PSLSE_DIR)/libcxl


SRC_FILES_ALGO_CAPI         =  $(wildcard $(APP_DIR)/$(SRC_DIR)/$(ALGO_DIR)/capi/*.c)
OBJ_FILES_ALGO_CAPI         =  $(patsubst $(APP_DIR)/$(SRC_DIR)/$(ALGO_DIR)/capi/%.c,$(APP_DIR)/$(OBJ_DIR)/$(ALGO_DIR)/capi/%.o,$(SRC_FILES_ALGO_CAPI))

SRC_FILES_CAPI_UTIL     =   $(wildcard $(APP_DIR)/$(SRC_DIR)/$(CAPI_UTIL_DIR)/*.c)
OBJ_FILES_CAPI_UTIL     =   $(patsubst $(APP_DIR)/$(SRC_DIR)/$(CAPI_UTIL_DIR)/%.c,$(APP_DIR)/$(OBJ_DIR)/$(CAPI_UTIL_DIR)/%.o,$(SRC_FILES_CAPI_UTIL))


CAPI_LINKFLAGS = -lrt -lpthread

# CAPI_INC   = -I$(PSLSE_COMMON_DIR) -I$(PSLSE_LIBCXL_DIR) -I$(APP_DIR)/$(INC_DIR)/$(CAPI_UTIL_DIR)
# CAPI_FLAGS = -DSIM -DVERBOSE

##################################################
##################################################


#########################################################
#                ACCEL APP GENERATION                   #
#########################################################

.PHONY: app-openmp
app-openmp : directories directories-openmp $(APP_DIR)/$(BIN_DIR)/$(APP)-openmp
	@echo "\n ******************************************************************************  "
	@echo " * DONE!! NOTHING ELSE TO COMPILE ---> CAPI-Precis: ./$(word 3,$^)"
	@echo " ******************************************************************************  \n"

.PHONY: test-openmp
test-openmp : directories directories-openmp $(APP_DIR)/$(BIN_DIR)/$(APP_TEST)-openmp
	@echo "\n ******************************************************************************  "
	@echo " * DONE!! NOTHING ELSE TO COMPILE ---> TEST: ./$(word 3,$^)"
	@echo " ****************************************************************************** \n"

.PHONY: directories
directories :
	@mkdir -p $(APP_DIR)/$(BIN_DIR)
	@mkdir -p $(APP_DIR)/$(OBJ_DIR)
	@mkdir -p $(APP_DIR)/$(OBJ_DIR)/$(UTIL_DIR)
	@mkdir -p $(APP_DIR)/$(OBJ_DIR)/$(MAIN_DIR)
	@mkdir -p $(APP_DIR)/$(OBJ_DIR)/$(TEST_DIR)

.PHONY: directories-openmp
directories-openmp :
	@mkdir -p $(APP_DIR)/$(OBJ_DIR)/$(ALGO_DIR)/openmp

$(APP_DIR)/$(BIN_DIR)/$(APP)-openmp : $(APP_DIR)/$(OBJ_DIR)/$(MAIN_DIR)/$(APP).o $(OBJ_FILES_UTIL) $(OBJ_FILES_ALGO_OPENMP)
	@$(CC) $(CFLAGS) -o $@ $^  $(LFLAGS)

$(APP_DIR)/$(BIN_DIR)/$(APP_TEST)-openmp : $(APP_DIR)/$(OBJ_DIR)/$(TEST_DIR)/$(APP_TEST).o $(OBJ_FILES_UTIL) $(OBJ_FILES_ALGO_OPENMP)
	@$(CC) $(CFLAGS) -o $@ $^  $(LFLAGS)

$(APP_DIR)/$(OBJ_DIR)/$(MAIN_DIR)/$(APP).o : $(APP_DIR)/$(SRC_DIR)/$(MAIN_DIR)/capi-precis.c
	$(CC) $(CFLAGS) $(OPENMP_INC) -c -o $@ $<

$(APP_DIR)/$(OBJ_DIR)/$(TEST_DIR)/$(APP_TEST).o : $(APP_DIR)/$(SRC_DIR)/$(TEST_DIR)/$(APP_TEST).c
	$(CC) $(CFLAGS) $(OPENMP_INC) -c -o $@ $<

$(APP_DIR)/$(OBJ_DIR)/$(UTIL_DIR)/%.o : $(APP_DIR)/$(SRC_DIR)/$(UTIL_DIR)/%.c
	$(CC) $(CFLAGS) $(OPENMP_INC) -c -o $@ $<

$(APP_DIR)/$(OBJ_DIR)/$(ALGO_DIR)/openmp/%.o : $(APP_DIR)/$(SRC_DIR)/$(ALGO_DIR)/openmp/%.c
	$(CC) $(CFLAGS) $(OPENMP_INC) -c -o $@ $<


.PHONY: clean
clean:
	@rm -fr $(APP_DIR)/$(OBJ_DIR)
	@rm -fr $(APP_DIR)/$(BIN_DIR)


##################################################
##################################################

#########################################################
#                CAPI GENERATION                        #
#########################################################

.PHONY: clean-pslse
clean-pslse:
	@cd $(PSLSE_DIR)/afu_driver/src && make clean
	@cd $(PSLSE_DIR)/pslse && make clean
	@cd $(PSLSE_DIR)/libcxl && make clean

.PHONY: app-capi
app-capi : directories directories-capi $(APP_DIR)/$(BIN_DIR)/$(APP)-capi
	@echo "\n ******************************************************************************  "
	@echo " * DONE!! NOTHING ELSE TO COMPILE ---> CAPI-Precis: ./$(word 3,$^)"
	@echo " ******************************************************************************  \n"

.PHONY: test-capi
test-capi : directories directories-capi $(APP_DIR)/$(BIN_DIR)/$(APP_TEST)-capi
	@echo "\n ******************************************************************************  "
	@echo " * DONE!! NOTHING ELSE TO COMPILE ---> TEST: ./$(word 3,$^)"
	@echo " ******************************************************************************  \n"

.PHONY: directories-capi
directories-capi :
	@mkdir -p $(APP_DIR)/$(OBJ_DIR)/$(ALGO_DIR)/capi
	@mkdir -p $(APP_DIR)/$(OBJ_DIR)/$(CAPI_UTIL_DIR)

$(PSLSE_DIR)/afu_driver/src/libdpi.so:
	@cd $(PSLSE_DIR)/afu_driver/src && make clean && BIT32=y make

$(PSLSE_LIBCXL_DIR)/libcxl.a:
	@cd $(PSLSE_LIBCXL_DIR) && make

$(PSLSE_DIR)/pslse/pslse:
	@cd $(PSLSE_DIR)/pslse && make DEBUG=1

.PHONY: build-libdpi
build-libdpi: $(PSLSE_DIR)/afu_driver/src/libdpi.so

.PHONY: build-libcxl
build-libcxl: $(PSLSE_LIBCXL_DIR)/libcxl.a

.PHONY: build-pslse
build-pslse: $(PSLSE_DIR)/pslse/pslse

$(APP_DIR)/$(BIN_DIR)/$(APP)-capi : $(APP_DIR)/$(OBJ_DIR)/$(MAIN_DIR)/$(APP).o $(OBJ_FILES_UTIL) $(OBJ_FILES_ALGO_CAPI) $(OBJ_FILES_CAPI_UTIL)
	@$(CC) $(CFLAGS) -o $@ $^ $(LFLAGS) $(PSLSE_LIBCXL_DIR)/libcxl.a $(CAPI_LINKFLAGS)

$(APP_DIR)/$(BIN_DIR)/$(APP_TEST)-capi : $(APP_DIR)/$(OBJ_DIR)/$(TEST_DIR)/$(APP_TEST)-capi.o $(OBJ_FILES_UTIL) $(OBJ_FILES_ALGO_CAPI) $(OBJ_FILES_CAPI_UTIL)
	@$(CC) $(CFLAGS) -o $@ $^ $(PSLSE_LIBCXL_DIR)/libcxl.a $(LFLAGS) $(CAPI_LINKFLAGS)

$(APP_DIR)/$(OBJ_DIR)/$(CAPI_UTIL_DIR)/%.o : $(APP_DIR)/$(SRC_DIR)/$(CAPI_UTIL_DIR)/%.c build-libcxl
	$(CC) $(CFLAGS) $(OPENMP_INC) $(CAPI_INC) -c -o $@ $< $(CAPI_FLAGS)

$(APP_DIR)/$(OBJ_DIR)/$(ALGO_DIR)/capi/%.o : $(APP_DIR)/$(SRC_DIR)/$(ALGO_DIR)/capi/%.c
	$(CC) $(CFLAGS) $(OPENMP_INC) $(CAPI_INC) -c -o $@ $< $(CAPI_FLAGS)

$(APP_DIR)/$(OBJ_DIR)/$(TEST_DIR)/$(APP_TEST)-capi.o : $(APP_DIR)/$(SRC_DIR)/$(TEST_DIR)/$(APP_TEST).c
	$(CC) $(CFLAGS) $(OPENMP_INC) $(CAPI_INC) -c -o $@ $< $(CAPI_FLAGS)

.PHONY: clean-sim
clean-sim:
	@rm -f $(CAPI_SIM)/modelsim.ini
	@rm -f $(CAPI_SIM)/transcript
	@rm -f $(CAPI_SIM)/vsim_stacktrace.vstf
	@rm -f $(CAPI_SIM)/vish_stacktrace.vstf
	@rm -f $(CAPI_SIM)/vsim.wlf
	@rm -f $(CAPI_SIM)/*.vcd
	@rm -rf $(CAPI_SIM)/work
	@rm -rf $(CAPI_SIM)/libraries
	@rm -f $(CAPI_SERVER)/debug.log
	@rm -f $(CAPI_SIM)/gmon.out
	@cd $(PSLSE_DIR)/afu_driver/src && make clean
	@cd $(PSLSE_DIR)/libcxl && make clean
	@cd $(PSLSE_DIR)/pslse && make  clean

##################################################
##################################################

##############################################
#             APP TOP LEVEL RULES            #
##############################################

.PHONY: help
help: app-openmp
	./$(APP_DIR)/$(BIN_DIR)/$(APP)-openmp  --help

.PHONY: run
run: run-openmp

.PHONY: run-openmp
run-openmp: app-openmp
	./$(APP_DIR)/$(BIN_DIR)/$(APP)-openmp  $(ARGS)

.PHONY: debug-openmp
debug-openmp: app-openmp
	gdb -ex=r --args ./$(APP_DIR)/$(BIN_DIR)/$(APP)-openmp  $(ARGS)

.PHONY: debug-memory-openmp
debug-memory-openmp: app-openmp
	valgrind --leak-check=full --show-leak-kinds=all ./$(APP_DIR)/$(BIN_DIR)/$(APP)-openmp  $(ARGS)

.PHONY: test-verbose
test-verbose:
	$(MAKE) run-test -C $(APP_DIR) | grep -E 'PASS|FAIL'

# test files
.PHONY: test
test:
	@if $(MAKE) run-test -C $(APP_DIR) | grep FAIL > /dev/null; \
		then exit 1; \
	fi

.PHONY: run-test
run-test: run-test-openmp

.PHONY: run-test-openmp
run-test-openmp: test-openmp
	./$(APP_DIR)/$(BIN_DIR)/$(APP_TEST)-openmp

.PHONY: debug-test-openmp
debug-test-openmp: test-openmp
	gdb ./$(APP_DIR)/$(BIN_DIR)/$(APP_TEST)-openmp

.PHONY: debug-memory-test-openmp
debug-memory-test-openmp: test-openmp
	valgrind --leak-check=full --show-leak-kinds=all ./$(APP_DIR)/$(BIN_DIR)/$(APP_TEST)-openmp
# cache performance
.PHONY: cachegrind-perf-openmp
cachegrind-perf-openmp: app-openmp
	valgrind --tool=cachegrind ./$(APP_DIR)/$(BIN_DIR)/$(APP)-openmp  $(ARGS)
.PHONY: cache-perf
cache-perf-openmp: app-openmp
	sudo perf record -d ./$(APP_DIR)/$(BIN_DIR)/$(APP)-openmp  $(ARGS)

##################################################
##################################################

##############################################
#         APP CAPI TOP LEVEL RULES           #
##############################################


.PHONY: run-capi-sim
run-capi-sim: CAPI_FLAGS = -DSIM
run-capi-sim: PSLSE_LIBCXL_DIR  = $(PSLSE_DIR)/libcxl
run-capi-sim: CAPI_INC   = -I$(PSLSE_COMMON_DIR) -I$(PSLSE_LIBCXL_DIR) -I$(APP_DIR)/$(INC_DIR)/$(CAPI_UTIL_DIR)
run-capi-sim: app-capi
	./$(APP_DIR)/$(BIN_DIR)/$(APP)-capi  $(ARGS)

.PHONY: run-capi-sim-verbose
run-capi-sim-verbose: CAPI_FLAGS = -DSIM -DVERBOSE
run-capi-sim-verbose: PSLSE_LIBCXL_DIR  = $(PSLSE_DIR)/libcxl
run-capi-sim-verbose: CAPI_INC   = -I$(PSLSE_COMMON_DIR) -I$(PSLSE_LIBCXL_DIR) -I$(APP_DIR)/$(INC_DIR)/$(CAPI_UTIL_DIR)
run-capi-sim-verbose: app-capi
	./$(APP_DIR)/$(BIN_DIR)/$(APP)-capi  $(ARGS)

.PHONY: run-capi-sim-verbose2
run-capi-sim-verbose2: CAPI_FLAGS = -DSIM -DVERBOSE -DVERBOSE_2
run-capi-sim-verbose2: PSLSE_LIBCXL_DIR  = $(PSLSE_DIR)/libcxl
run-capi-sim-verbose2: CAPI_INC   = -I$(PSLSE_COMMON_DIR) -I$(PSLSE_LIBCXL_DIR) -I$(APP_DIR)/$(INC_DIR)/$(CAPI_UTIL_DIR)
run-capi-sim-verbose2: app-capi
	./$(APP_DIR)/$(BIN_DIR)/$(APP)-capi  $(ARGS)

.PHONY: run-capi-fpga
run-capi-fpga: CAPI_FLAGS =
run-capi-fpga: PSLSE_LIBCXL_DIR  = $(LIBCXL_DIR)
run-capi-fpga: CAPI_INC = -I$(LIBCXL_DIR) -I$(APP_DIR)/$(INC_DIR)/$(CAPI_UTIL_DIR)
run-capi-fpga: app-capi
	./$(APP_DIR)/$(BIN_DIR)/$(APP)-capi  $(ARGS)

.PHONY: run-capi-fpga-verbose
run-capi-fpga-verbose: CAPI_FLAGS = -DVERBOSE
run-capi-fpga-verbose: PSLSE_LIBCXL_DIR  = $(LIBCXL_DIR)
run-capi-fpga-verbose: CAPI_INC = -I$(LIBCXL_DIR) -I$(APP_DIR)/$(INC_DIR)/$(CAPI_UTIL_DIR)
run-capi-fpga-verbose: app-capi
	./$(APP_DIR)/$(BIN_DIR)/$(APP)-capi  $(ARGS)

.PHONY: run-capi-fpga-verbose2
run-capi-fpga-verbose2: CAPI_FLAGS = -DVERBOSE -DVERBOSE_2
run-capi-fpga-verbose2: PSLSE_LIBCXL_DIR  = $(LIBCXL_DIR)
run-capi-fpga-verbose2: CAPI_INC = -I$(LIBCXL_DIR) -I$(APP_DIR)/$(INC_DIR)/$(CAPI_UTIL_DIR)
run-capi-fpga-verbose2: app-capi
	./$(APP_DIR)/$(BIN_DIR)/$(APP)-capi  $(ARGS)


.PHONY: run-test-capi
run-test-capi: CAPI_FLAGS = -DSIM -DVERBOSE
run-test-capi: PSLSE_LIBCXL_DIR  = $(PSLSE_DIR)/libcxl
run-test-capi: CAPI_INC   = -I$(PSLSE_COMMON_DIR) -I$(PSLSE_LIBCXL_DIR) -I$(APP_DIR)/$(INC_DIR)/$(CAPI_UTIL_DIR)
run-test-capi: test-capi
	./$(APP_DIR)/$(BIN_DIR)/$(APP_TEST)-capi

.PHONY: run-vsim
run-vsim: build-libdpi
	cd $(CAPI_SIM) && vsim -do sim_$(CU_ALGORITHM).tcl

.PHONY: run-pslse
run-pslse: build-pslse
	cd $(CAPI_SIM) && ./../../pslse/pslse/pslse

##################################################
##################################################