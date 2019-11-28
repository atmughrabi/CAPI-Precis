

#########################################################
#       		 GENERAL DIRECTOIRES   	    			#
#########################################################
# globals binaary /bin/accel-graph name doesn't need to match main/accel-graph.c
  APP               ?= capi-precis

# test name needs to match the file name test/test_accel-graph.c
  APP_TEST          = test_afu
#   APP_TEST          ?= test_capi-precis


# dirs Root app 
APP_DIR           	?= .

#dir root/managed_folders
SRC_DIR           	?= src
OBJ_DIR			  	?= obj
INC_DIR			  	?= include
BIN_DIR			  	?= bin

#if you want to compile from cmake you need this directory
#cd build
#cmake ..
BUILD_DIR		  	?= build

# relative directories used for managing src/obj files
ALGO_DIR		  	?= algorithms
UTIL_DIR		  	?= utils
CAPI_UTIL_DIR		?= capi_utils

#contains the tests use make run-test to compile what in this directory
TEST_DIR		  	?= tests

#contains the main for the graph processing framework
MAIN_DIR		  	?= main

##################################################
##################################################

#########################################################
#       		 RUN  ARGUMENTS    						#
#########################################################

NUM_THREADS  	?= 4

SIZE ?= 256

ARGS ?= -n $(NUM_THREADS) -s $(SIZE)


##############################################
# CAPI FPGA  GRAPH AFU PERFORMANCE CONFIG    #
##############################################

# // cu_read_engine_control          5-bits STRICT | READ_CL_NA | WRITE_NA 00000 [27:31] [4] [3] [0:2]
# // cu_write_engine_control         5-bits STRICT | READ_CL_NA | WRITE_NA 00000 [22:26] [9] [8] [5:7]

 AFU_CONFIG_STRICT_1?=0x00000000  

 
 AFU_CONFIG_GENERIC?=$(AFU_CONFIG_STRICT_1)

##################################################
##################################################

##############################################
#      ACCEL APP   COMPILATION VARIABLES     #
##############################################


#each implementation is contained in a separate folder. when you compile for openmp for example the files in openmp folder gets included
SRC_FILES_ALGO_OPENMP		=	$(wildcard $(APP_DIR)/$(SRC_DIR)/$(ALGO_DIR)/openmp/*.c)

SRC_FILES_UTIL		=	$(wildcard $(APP_DIR)/$(SRC_DIR)/$(UTIL_DIR)/*.c) 
SRC_FILES_MAIN		=	$(wildcard $(APP_DIR)/$(SRC_DIR)/$(MAIN_DIR)/*.c)
SRC_FILES_TEST		=	$(wildcard $(APP_DIR)/$(SRC_DIR)/$(TEST_DIR)/*.c)

#create object file rules for the final binary target
OBJ_FILES_ALGO_OPENMP 		= $(patsubst $(APP_DIR)/$(SRC_DIR)/$(ALGO_DIR)/openmp/%.c,$(APP_DIR)/$(OBJ_DIR)/$(ALGO_DIR)/openmp/%.o,$(SRC_FILES_ALGO_OPENMP)) 

OBJ_FILES_UTIL 		= $(patsubst $(APP_DIR)/$(SRC_DIR)/$(UTIL_DIR)/%.c,$(APP_DIR)/$(OBJ_DIR)/$(UTIL_DIR)/%.o,$(SRC_FILES_UTIL)) 
OBJ_FILES_MAIN  	= $(patsubst $(APP_DIR)/$(SRC_DIR)/$(MAIN_DIR)/%.c,$(APP_DIR)/$(OBJ_DIR)/$(MAIN_DIR)/%.o,$(SRC_FILES_MAIN)) 
OBJ_FILES_TEST  	= $(patsubst $(APP_DIR)/$(SRC_DIR)/$(TEST_DIR)/%.c,$(APP_DIR)/$(OBJ_DIR)/$(TEST_DIR)/%.o,$(SRC_FILES_TEST)) 

CC				  = gcc 

OPENMP_INC = 	-I$(APP_DIR)/$(INC_DIR)/$(ALGO_DIR)/openmp 	\
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

PSLSE_DIR         = ../01_capi_integration/pslse
LIBCXL_DIR        = ../01_capi_integration/libcxl
CAPI_UTILS_DIR    = ../01_capi_integration/capi-utils
CAPI_ACCEL		  = ../01_capi_integration/accelerator
CAPI_COMMON		  = ../01_capi_integration/capi_common

CAPI_SIM		  = $(CAPI_COMMON)/sim
CAPI_SERVER		  = $(CAPI_COMMON)/server


PSLSE_COMMON_DIR  = $(PSLSE_DIR)/common
# PSLSE_LIBCXL_DIR  = $(PSLSE_DIR)/libcxl


SRC_FILES_ALGO_CAPI			=  $(wildcard $(APP_DIR)/$(SRC_DIR)/$(ALGO_DIR)/capi/*.c) 
OBJ_FILES_ALGO_CAPI 		=  $(patsubst $(APP_DIR)/$(SRC_DIR)/$(ALGO_DIR)/capi/%.c,$(APP_DIR)/$(OBJ_DIR)/$(ALGO_DIR)/capi/%.o,$(SRC_FILES_ALGO_CAPI))

SRC_FILES_CAPI_UTIL		=	$(wildcard $(APP_DIR)/$(SRC_DIR)/$(CAPI_UTIL_DIR)/*.c)
OBJ_FILES_CAPI_UTIL 	=   $(patsubst $(APP_DIR)/$(SRC_DIR)/$(CAPI_UTIL_DIR)/%.c,$(APP_DIR)/$(OBJ_DIR)/$(CAPI_UTIL_DIR)/%.o,$(SRC_FILES_CAPI_UTIL)) 


CAPI_LINKFLAGS = -lrt -lpthread



CAPI_AFU_CONFIG = -DAFU_CONFIG=$(AFU_CONFIG_GENERIC)
# CAPI_INC   = -I$(PSLSE_COMMON_DIR) -I$(PSLSE_LIBCXL_DIR) -I$(APP_DIR)/$(INC_DIR)/$(CAPI_UTIL_DIR)
# CAPI_FLAGS = -DSIM -DVERBOSE 

##################################################
##################################################


#########################################################
#       		 ACCEL APP GENERATION    				#
#########################################################

.PHONY: graph-openmp
graph-openmp : directories directories-openmp $(APP_DIR)/$(BIN_DIR)/$(APP)-openmp
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
#       		 CAPI GENERATION    	    			#
#########################################################

.PHONY: clean-pslse
clean-pslse:
	@cd $(PSLSE_DIR)/afu_driver/src && make clean
	@cd $(PSLSE_DIR)/pslse && make clean
	@cd $(PSLSE_DIR)/libcxl && make clean

.PHONY: graph-capi
graph-capi : directories directories-capi $(APP_DIR)/$(BIN_DIR)/$(APP)-capi
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
	@rm -f $(CAPI_SIM)/vsim.wlf
	@rm -rf $(CAPI_SIM)/work
	@rm -f $(CAPI_SIM)/debug.log
	@rm -f $(CAPI_SIM)/gmon.out	 
	@cd $(PSLSE_DIR)/afu_driver/src && make clean
	@cd $(PSLSE_DIR)/libcxl && make clean
	@cd $(PSLSE_DIR)/pslse && make  clean

##################################################
##################################################

##############################################
#         ACCEL GRAPH TOP LEVEL RULES        #
##############################################

.PHONY: help
help: graph-openmp
	./$(APP_DIR)/$(BIN_DIR)/$(APP)-openmp  --help

.PHONY: run
run: run-openmp

.PHONY: run-openmp
run-openmp: graph-openmp
	./$(APP_DIR)/$(BIN_DIR)/$(APP)-openmp  $(ARGS)

.PHONY: debug-openmp
debug-openmp: graph-openmp	
	gdb -ex=r --args ./$(APP_DIR)/$(BIN_DIR)/$(APP)-openmp  $(ARGS)

.PHONY: debug-memory-openmp
debug-memory-openmp: graph-openmp	
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
cachegrind-perf-openmp: graph-openmp
	valgrind --tool=cachegrind ./$(APP_DIR)/$(BIN_DIR)/$(APP)-openmp  $(ARGS)
.PHONY: cache-perf
cache-perf-openmp: graph-openmp
	sudo perf record -d ./$(APP_DIR)/$(BIN_DIR)/$(APP)-openmp  $(ARGS)

##################################################
##################################################

##############################################
#      ACCEL GRAPH CAPI TOP LEVEL RULES      #
##############################################


.PHONY: run-capi-sim
run-capi-sim: CAPI_FLAGS = -DSIM $(CAPI_AFU_CONFIG)
run-capi-sim: PSLSE_LIBCXL_DIR  = $(PSLSE_DIR)/libcxl
run-capi-sim: CAPI_INC   = -I$(PSLSE_COMMON_DIR) -I$(PSLSE_LIBCXL_DIR) -I$(APP_DIR)/$(INC_DIR)/$(CAPI_UTIL_DIR)
run-capi-sim: graph-capi
	./$(APP_DIR)/$(BIN_DIR)/$(APP)-capi  $(ARGS)

.PHONY: run-capi-sim-verbose
run-capi-sim-verbose: CAPI_FLAGS = -DSIM -DVERBOSE $(CAPI_AFU_CONFIG)
run-capi-sim-verbose: PSLSE_LIBCXL_DIR  = $(PSLSE_DIR)/libcxl
run-capi-sim-verbose: CAPI_INC   = -I$(PSLSE_COMMON_DIR) -I$(PSLSE_LIBCXL_DIR) -I$(APP_DIR)/$(INC_DIR)/$(CAPI_UTIL_DIR)
run-capi-sim-verbose: graph-capi
	./$(APP_DIR)/$(BIN_DIR)/$(APP)-capi  $(ARGS)

.PHONY: run-capi-fpga
run-capi-fpga: CAPI_FLAGS = $(CAPI_AFU_CONFIG)
run-capi-fpga: PSLSE_LIBCXL_DIR  = $(LIBCXL_DIR)
run-capi-fpga: CAPI_INC = -I$(LIBCXL_DIR) -I$(APP_DIR)/$(INC_DIR)/$(CAPI_UTIL_DIR)
run-capi-fpga: graph-capi
	./$(APP_DIR)/$(BIN_DIR)/$(APP)-capi  $(ARGS)

.PHONY: run-capi-fpga-verbose
run-capi-fpga-verbose: CAPI_FLAGS = -DVERBOSE $(CAPI_AFU_CONFIG)
run-capi-fpga-verbose: PSLSE_LIBCXL_DIR  = $(LIBCXL_DIR)
run-capi-fpga-verbose: CAPI_INC = -I$(LIBCXL_DIR) -I$(APP_DIR)/$(INC_DIR)/$(CAPI_UTIL_DIR)
run-capi-fpga-verbose: graph-capi
	./$(APP_DIR)/$(BIN_DIR)/$(APP)-capi  $(ARGS)


.PHONY: run-test-capi
run-test-capi: CAPI_FLAGS = -DSIM $(CAPI_AFU_CONFIG) -DVERBOSE 
run-test-capi: PSLSE_LIBCXL_DIR  = $(PSLSE_DIR)/libcxl
run-test-capi: CAPI_INC   = -I$(PSLSE_COMMON_DIR) -I$(PSLSE_LIBCXL_DIR) -I$(APP_DIR)/$(INC_DIR)/$(CAPI_UTIL_DIR)
run-test-capi: test-capi
	./$(APP_DIR)/$(BIN_DIR)/$(APP_TEST)-capi 

.PHONY: run-vsim
run-vsim: build-libdpi
	cd $(CAPI_SIM) && vsim -do vsim.tcl

.PHONY: run-pslse
run-pslse: build-pslse
	cd $(CAPI_SIM) && ./../../pslse/pslse/pslse
	  
##################################################
##################################################