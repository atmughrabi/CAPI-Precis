[![Build Status](https://travis-ci.com/atmughrabi/CAPIPrecis.svg?token=L3reAtGHdEVVPvzcVqQ6&branch=master)](https://travis-ci.com/atmughrabi/CAPIPrecis)
<p align="center"><img src="./02_slides/fig/logo3.png" width="650" ></p>

#  CAPIPrecis Coherent Accelerator Processor Interface (CAPI) Abstract Layer

## Overview 

<p align="center"><img src="./02_slides/fig/theme.png" width="650" ></p>

CAPIPrecis is an abstraction layer (AFU-Control) that simplifies communication and buffering with IBM CAPI Power Service Layer (PSL). Each control unit handling different aspects of communication with the PSL, it simplifies the interface for sending and receiving memory transactions, and preserves the fine-grain random or sequential memory access pattern. Furthermore our layer differentiate its self from other CAPI frameworks, by keeping the PSL cache support.

### Key Features and Benefits

* Design your Compute Units (CUs) without the need to interface with the PSL directly (CU-centric).
* Supports PSL cache access.
* Supports fine grain random, or streaming access, for it keeps the command-buffer exposed and flexible for any CAPI-PSL supported commands.
* You will only be concerned with sending PSL supported commands, for example you can send reads/writes without the need to check parity, error reporting, and latency requirements. Just push commands to their corresponding buffers, and wait for the response.
* Each sent command can be coupled with meta-data (for example CU_ID, request_size, etc.), and then receive data or responses coupled with those elements for an easier multi-CU design.
* Open-source and minimalistic design.

# Installation 

## Dependencies

### OpenMP
1. OpenMP is already a feature of the compiler, so this step is not necessary.
```console
CAPI@Precis:~$ sudo apt-get install libomp-dev
```

### CAPI
1. Simulation and Synthesis
  * This framework was developed on Ubuntu 18.04 LTS.
  * ModelSim is used for simulation and installed along side Quartus II 18.1.
  * Synthesis requires ALTERA Quartus, starting from release 15.0 of Quartus II should be fine.
  * Nallatech P385-A7 card with the Altera Stratix-V-GX-A7 FPGA is supported.
  * Environment Variable setup, `HOME` and `ALTERAPATH` depend on where you clone the repository and install ModelSim.

```bash
#quartus 18.1 env-variables
export ALTERAPATH="${HOME}/intelFPGA/18.1"
export QUARTUS_INSTALL_DIR="${ALTERAPATH}/quartus"
export LM_LICENSE_FILE="${ALTERAPATH}/licenses/psl_A000_license.dat:${ALTERAPATH}/licenses/common_license.dat"
export QSYS_ROOTDIR="${ALTERAPATH}/quartus/sopc_builder/bin"
export PATH=$PATH:${ALTERAPATH}/quartus/bin
export PATH=$PATH:${ALTERAPATH}/nios2eds/bin

#modelsim env-variables
export PATH=$PATH:${ALTERAPATH}/modelsim_ase/bin

#CAPIPrecis project folder
export CAPI_PROJECT=00_CAPIPrecis

#CAPI framework env variables
export PSLSE_INSTALL_DIR="${HOME}/Documents/github_repos/${CAPI_PROJECT}/01_capi_integration/pslse"
export VPI_USER_H_DIR="${ALTERAPATH}/modelsim_ase/include"
export PSLVER=8
export BIT32=n
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$PSLSE_INSTALL_DIR/libcxl:$PSLSE_INSTALL_DIR/afu_driver/src"

#PSLSE env variables
export PSLSE_SERVER_DIR="${HOME}/Documents/github_repos/${CAPI_PROJECT}/01_capi_integration/accelerator_sim/server"
export PSLSE_SERVER_DAT="${PSLSE_SERVER_DIR}/pslse_server.dat"
export SHIM_HOST_DAT="${PSLSE_SERVER_DIR}/shim_host.dat"
export PSLSE_PARMS="${PSLSE_SERVER_DIR}/pslse.parms"
export DEBUG_LOG_PATH="${PSLSE_SERVER_DIR}/debug.log"

```

2. AFU Communication with PSL
  * please check [(CAPI User's Manual)](http://www.nallatech.com/wp-content/uploads/IBM_CAPI_Users_Guide_1-2.pdf).

## Setting up the source code 

1. Clone CAPIPrecis.
```console
CAPI@Precis:~$ git clone https://github.com/atmughrabi/CAPIPrecis.git
```
2. From the home directory go to the CAPIPrecis directory:
```console
CAPI@Precis:~$ cd CAPIPrecis/
```
3. Setup the CAPI submodules.
```console
CAPI@Precis:~CAPIPrecis$ git submodule update --init --recursive
```

# Running CAPIPrecis (Memory Copy engines)

[<img src="./02_slides/fig/openmp_logo.png" height="45" align="right" >](https://www.openmp.org/)

## Initial compilation for framework with OpenMP 

1. (Optional) From the root directory go to benchmark directory:
```console
CAPI@Precis:~CAPIPrecis$ cd 00_bench/
```
2. The default compilation is `openmp` mode:
```console
CAPI@Precis:~CAPIPrecis/00_bench$ make 
```
3. From the root directory you can modify the Makefile with the directories you need for you custom project:
```console
CAPI@Precis:~CAPIPrecis/00_bench$ make run
```
* OR
```console
CAPI@Precis:~CAPIPrecis/00_bench$ make run-openmp
```
4. Example output:
```
*-----------------------------------------------------*
| Number of Threads :  8                              | 
 -----------------------------------------------------
*-----------------------------------------------------*
| Allocating Data Arrays (SIZE)  131072               | 
 -----------------------------------------------------
*-----------------------------------------------------*
| Populating Data Arrays (Seed)  27491095             | 
 -----------------------------------------------------
*-----------------------------------------------------*
| Copy data (SIZE)               131072               | 
 -----------------------------------------------------
| Time (Seconds)         | 0.00000900000000000000     | 
| BandWidth MB/s         | 55555.55555555555474711582 | 
| BandWidth GB/s         | 54.25347222222222143273    | 
*-----------------------------------------------------*
| Data Missmatched (#)           | 0                  | 
 -----------------------------------------------------
| PASS                                                |
*-----------------------------------------------------*
| Freeing Data Arrays (SIZE)     131072               | 
 -----------------------------------------------------
```

[<img src="./02_slides/fig/capi_logo.png" height="45" align="right" >](https://openpowerfoundation.org/capi-drives-business-performance/)

## Initial compilation for framework with Coherent Accelerator Processor Interface (CAPI)  

* NOTE: You need CAPI environment setup on your machine (tested on Power8 8247-22L).
* [CAPI Education Videos](https://developer.ibm.com/linuxonpower/capi/education/)
* We are not supporting CAPI-SNAP since our processing suite supports accelerator-cache. SNAP does not support this feature yet. So if you are interested in streaming applications or do not benefit from caches SNAP is also good candidate.
* To check the SNAP framework: https://github.com/open-power/snap.

### Simulation

* NOTE: You need three open terminals, for running vsim, pslse, and the application.

1. (Optional) From the root directory go to benchmark directory:
```console
CAPI@Precis:~CAPIPrecis$ cd 00_bench/
```
2. On terminal 1. Run [ModelSim vsim] for `simulation` this step is not needed when running on real hardware, this just simulates the AFU that resides on your (CAPI supported) FPGA  :
```console
CAPI@Precis:~CAPIPrecis/00_bench$ make run-vsim
```
3. The previous step will execute vsim.tcl script to compile the design, to start the running the simulation just execute the following command at the transcript terminal of ModelSim : `r #recompile design`,`c #run simulation`
```console
ModelSim> r 
ModelSim> c 
```
4. On Terminal 2. Run [PSL Simulation Engine](https://github.com/ibm-capi/pslse) (PSLSE) for `simulation` this step is not needed when running on real hardware, this just emulates the PSL that resides on your (CAPI supported) IBM-PowerPC machine  :
```console
CAPI@Precis:~CAPIPrecis/00_bench$ make run-pslse
```

##### Option 1: Silent run with no stats output

5. On Terminal 3. Run the algorithm that communicates with the PSLSE (simulation):
```console
CAPI@Precis:~CAPIPrecis/00_bench$ make run-capi-sim
```

##### Option 2: Verbose run with stats output

5.  On Terminal 3. Run the algorithm that communicates with the PSLSE (simulation) printing out stats based on the responses received to the AFU-Control layer:
```console
CAPI@Precis:~CAPIPrecis/00_bench$ make run-capi-sim-verbose
```
6. Example output: please check [(CAPI User's Manual)](http://www.nallatech.com/wp-content/uploads/IBM_CAPI_Users_Guide_1-2.pdf), for each response explanation. The stats are labeled `RESPONSE_COMMANADTYPE_count`.
```
*-----------------------------------------------------*
|                 WEDStruct structure                 | 
 -----------------------------------------------------
| wed                    | 0x557ba26c1600             | 
| wed->size_send         | 131072                     | 
| wed->size_recive       | 131072                     | 
| wed->array_send        | 0x7fc19b290080             | 
| wed->array_receive     | 0x7fc19b20f080             | 
 -----------------------------------------------------
*-----------------------------------------------------*
|               AFU configuration START               | 
 -----------------------------------------------------
| status                 | 0                          | 
*-----------------------------------------------------*
|               AFU configuration DONE                | 
 -----------------------------------------------------
| status                 | 1111000000000001           | 
*-----------------------------------------------------*
*-----------------------------------------------------*
|               CU configuration START                | 
 -----------------------------------------------------
| status                 | 0                          | 
*-----------------------------------------------------*
|               CU configuration DONE                 | 
 -----------------------------------------------------
| status                 | 333b1000008                | 
*-----------------------------------------------------*
*-----------------------------------------------------*
|                 AFU Stats                           | 
 -----------------------------------------------------
| CYCLE_count            | 55060                      | 
| Time (Seconds)         | 0.00022023999999999999     | 
 -----------------------------------------------------
*-----------------------------------------------------*
|                 Total BW                            | 
 -----------------------------------------------------
| Data MB                | 1.00000000000000000000     | 
| Data GB                | 0.00097656250000000000     | 
 -----------------------------------------------------
| BandWidth MB/s         | 4540.50127134035574272275  | 
| BandWidth GB/s         | 4.43408327279331615500     | 
*-----------------------------------------------------*
|                 Total Read BW                       | 
 -----------------------------------------------------
| Data MB                | 0.50000000000000000000     | 
| Data GB                | 0.00048828125000000000     | 
 -----------------------------------------------------
| BandWidth MB/s         | 2270.25063567017787136137  | 
| BandWidth GB/s         | 2.21704163639665807750     | 
*-----------------------------------------------------*
|                 Total Write BW                      | 
 -----------------------------------------------------
| Data MB                | 0.50000000000000000000     | 
| Data GB                | 0.00048828125000000000     | 
 -----------------------------------------------------
| BandWidth MB/s         | 2270.25063567017787136137  | 
| BandWidth GB/s         | 2.21704163639665807750     | 
*-----------------------------------------------------*
|                 Effective total BW                  | 
 -----------------------------------------------------
| Data MB                | 1.00000000000000000000     | 
| Data GB                | 0.00097656250000000000     | 
 -----------------------------------------------------
| BandWidth MB/s         | 4540.50127134035574272275  | 
| BandWidth GB/s         | 4.43408327279331615500     | 
*-----------------------------------------------------*
|                 Effective Read BW                   | 
 -----------------------------------------------------
| Data MB                | 0.50000000000000000000     | 
| Data GB                | 0.00048828125000000000     | 
 -----------------------------------------------------
| BandWidth MB/s         | 2270.25063567017787136137  | 
| BandWidth GB/s         | 2.21704163639665807750     | 
*-----------------------------------------------------*
|                 Effective Write BW                  | 
 -----------------------------------------------------
| Data MB                | 0.50000000000000000000     | 
| Data GB                | 0.00048828125000000000     | 
 -----------------------------------------------------
| BandWidth MB/s         | 2270.25063567017787136137  | 
| BandWidth GB/s         | 2.21704163639665807750     | 
*-----------------------------------------------------*
|              Byte Transfer Stats                    | 
 -----------------------------------------------------
| READ_BYTE_count        | 524288                     | 
| WRITE_BYTE_count       | 524288                     | 
 -----------------------------------------------------
| PREFETCH_READ_BYTE_count   | 0                      | 
| PREFETCH_WRITE_BYTE_count  | 0                      | 
*-----------------------------------------------------*
|                 Responses Stats                     | 
 -----------------------------------------------------
| DONE_count             | 8415                       | 
 -----------------------------------------------------
| DONE_READ_count        | 4096                       | 
| DONE_WRITE_count       | 4096                       | 
 -----------------------------------------------------
| DONE_RESTART_count     | 206                        | 
 -----------------------------------------------------
| DONE_PREFETCH_READ_count   | 8                      | 
| DONE_PREFETCH_WRITE_count  | 8                      | 
 -----------------------------------------------------
| PAGED_count            | 206                        | 
| FLUSHED_count          | 0                          | 
| AERROR_count           | 0                          | 
| DERROR_count           | 0                          | 
| FAILED_count           | 0                          | 
| NRES_count             | 0                          | 
| NLOCK_count            | 0                          | 
*-----------------------------------------------------*

```

### FPGA

#### Synthesize

These steps require ALTERA Quartus synthesis tool, starting from release 15.0 of Quartus II should be fine.

##### Using terminal
1. From the root directory (using terminal)
```console
CAPI@Precis:~CAPIPrecis$ make run-synth
```
or
```console
CAPI@Precis:~CAPIPrecis$ cd 01_capi_integration/accelerator_synth/
CAPI@Precis:~CAPIPrecis/01_capi_integration/accelerator_synth$ make
```

2. Check CAPIPrecis.sta.rpt for timing requirements violations

##### Using Quartus GUI
1. From the root directory (using terminal)
```console
CAPI@Precis:~CAPIPrecis$ make run-synth-gui
```
or
```console
CAPI@Precis:~CAPIPrecis$ cd 01_capi_integration/accelerator_synth/
CAPI@Precis:~CAPIPrecis/01_capi_integration/accelerator_synth$ make gui
```
2. Synthesize using Quartus GUI

##### Using terminal (sweep seeds)
1. From the root directory (using terminal) runs a list of seeds synthesizing for each.
```console
CAPI@Precis:~CAPIPrecis$ make run-synth-sweep
```
or
```console
CAPI@Precis:~CAPIPrecis$ cd 01_capi_integration/accelerator_synth/
CAPI@Precis:~CAPIPrecis/01_capi_integration/accelerator_synth$ make sweep
```

#### Flashing image

1. From the root directory go to CAPI integration directory -> CAPIPrecis binary images:
```console
CAPI@Precis:~CAPIPrecis$ cd 01_capi_integration/accelerator_bin/
```
2. Flash the image to the corresponding `#define DEVICE` you can modify it according to your Power8 system from `00_bench/include/capi_utils/capienv.h`
```console
CAPI@Precis:~CAPIPrecis/01_capi_integration/accelerator_bin$ sudo capi-flash-script capi-precis_GITCOMMIT#_DATETIME.rbf
```

#### Running

1. (Optional) From the root directory go to benchmark directory:
```console
CAPI@Precis:~CAPIPrecis$ cd 00_bench/
```

##### Silent run with no stats output

2. Runs algorithm that communicates with the or PSL (real HW):
```console
CAPI@Precis:~CAPIPrecis/00_bench$ make run-capi-fpga
```

##### Verbose run with stats output

This run outputs different AFU-Control stats based on the responses received from the PSL

2. Runs algorithm that communicates with the or PSL (real HW):
```console
CAPI@Precis:~CAPIPrecis/00_bench$ make run-capi-fpga-verbose
```

# CAPI-Precis Options 

```
Usage: capi-precis-openmp [OPTION...]
            -s <size> -n [num threads] -a [afu config] -c [cu config]  

CAPIPrecis is an open source CAPI enabled FPGA processing framework, it is
designed to abstract the PSL layer for a faster development cycles

  -a, --afu-config=[DEFAULT:0x1]   
                             AFU-Control buffers(read/write/prefetcher)
                             arbitration 0x01 round robin 0x10 fixed priority
  -b, --afu-config2=[DEFAULT:0x0]
                             
                             AFU-Control MMIO register for extensible features
  -c, --cu-config=[DEFAULT:0x01]   
                             CU configurations for requests cached/non
                             cached/prefetcher active or not check Makefile for
                             more examples
  -d, --cu-config2=[DEFAULT:0x00]
                             
                             CU-Control MMIO register for extensible features
  -m, --cu-mode=[DEFAULT:0x03]   
                             CU configurations for read/write engines.
                             disable-both-engines-[0] write-engine-[1]
                             read-engine-[2] enable-both-engines-[3]
  -n, --num-threads=[DEFAULT:MAX]
                             
                             Default: MAX number of threads the system has
  -s, --size=SIZE:512        
                             Size of array to be sent and copied back 
  -?, --help                 Give this help list
      --usage                Give a short usage message
  -V, --version              Print program version

Mandatory or optional arguments to long options are also mandatory or optional
for any corresponding short options.

```


# CAPIPrecis Structure:
<p align="center"><img src="./02_slides/fig/CAPIPrecis_chipplanner.png" width="600" ></p>
<p align="center"><img src="./02_slides/fig/theme2.png" width="650" ></p>

## CU Control

### Interface

## AFU Control

### MMIO

### Command Issue

### Command Restart Issue

### Credit Managment

### Tag Managment

### Read Data

### Write Data

### Error Report

### Work Element Descriptor (WED)

### Prefetch Control

### Async/Sync Reset

### Response Control

# Organization 

* `00_bench` - The SW side that runs on the host(CPU)
  * `include` 
  * `src` 
    * `algorithms` 
      * `openmp`  
        * `algorithm.c` - Contains a version of the code that runs on CPU.
      * `capi`
        * `algorithm.c` - Contains a version of the code that runs on FPGA.
    * `capi-utils` 
      * `capienv.c` - Has the functions for setting up CAPI with our application (setup/start/wait/error).
    * `main`
      * `capi-precis.c` - Our main program execution starts from here.
    * `tests`
      * `test_afu.c` - test file to try things before integration.
      * `test_capi-precis.c` - another test bed to try some functionalities.
    * `utils`
      * `mt19937.c` - Random number generator.
      * `myMalloc.c` - Custom malloc wrapper for aligned allocations.
      * `timer.c` - simple time measurement library.
  * *`Makefile`* - This makefile handles the compilation/and simulation of CAPIPrecis 
* `01_capi_integration` - The SW side that runs on the Device(FPGA)/ModelSim
  * `accelerator_rtl` 
    * `cu_control` - CU Units reside in this folder (read/write engines)
    * `afu_pkgs` - global packages 
    * `afu_control` - AFU Control units in this folder
  * `accelerator_bin` - Binary images of CAPIPrecis (passed time requirements)
    * `capi-precis_GITCOMMIT#_DATETIME.rbf` - flash binary image 
    * `synthesis_reports_capi-precis_GITCOMMIT#_DATETIME` - synthesis reports for that binary image
  * `accelerator_sim`
    * `server` - files for PSLSE layer
      * `pslse.parms`
      * `pslse_server.dat`
      * `shim_host.dat`
    * `sim` - ModelSim file and tcl scripts
      * `vsim.tcl` - when adding files to you RTL project you need to update this script
      * `inerface.do` - Wave files for ModelSim simulation
  * `accelerator_synth` - synthesis scripts
    * `capi` - This folder contains helper scripts that generated the files necessary for synthesizing the project.
    * `psl_fpga` - This folder contains the RTL for the PSL layer, IPs, and the AFU top
    * `capi-precis.tcl`
    * *`Makefile`* - Synthesis Makefile that invokes Quartus.
  * `pslse`
  * `libcxl`
  * `capi-utils`
* *`Makefile`* - Global makefile

Report bugs to: 
- <atmughrabi@gmail.com>
- <atmughra@ncsu.edu>
<p align="right"> <img src="./02_slides/fig/logo1.png" width="200" ></p>