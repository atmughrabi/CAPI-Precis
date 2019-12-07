#ifndef CAPIENV_H
#define CAPIENV_H

#include <linux/types.h>
#include "myMalloc.h"
#include "libcxl.h"

#include "algorithm.h"

// ********************************************************************************************
// ***************                  MMIO General                                 **************
// ********************************************************************************************


#define ALGO_REQUEST            0x3FFFFF0             // 0x3fffff8 >> 2 = 0xfffffc

#define AFU_STATUS              0x3FFFFE0             // running counters that you can read continuosly
#define ALGO_RUNNING            0x3FFFFD8

#define ALGO_STATUS             0x3FFFFF8             // 0x3fffff8 >> 2 = 0xfffffe
#define ALGO_STATUS_ACK         0x3FFFFD0

#define ERROR_REG               0x3FFFFE8
#define ERROR_REG_ACK           0x3FFFFC8

#define  ALGO_STATUS_DONE       0x3FFFFC0
#define  ALGO_STATUS_DONE_ACK   0x3FFFFB8


// ********************************************************************************************
// ***************                  MMIO Stats                                   **************
// ********************************************************************************************


// ********************************************************************************************
// ***************                  AFU  Stats                                   **************
// ********************************************************************************************

#define  DONE_COUNT_REG              0x3FFFFB0
#define  DONE_RESTART_COUNT_REG      0x3FFFFA8

#define  PAGED_COUNT_REG             0x3FFFFA0
#define  FLUSHED_COUNT_REG           0x3FFFF98
#define  AERROR_COUNT_REG            0x3FFFF90
#define  DERROR_COUNT_REG            0x3FFFF88
#define  FAILED_COUNT_REG            0x3FFFF80
#define  FAULT_COUNT_REG             0x3FFFF78
#define  NRES_COUNT_REG              0x3FFFF70
#define  NLOCK_COUNT_REG             0x3FFFF68

#define  CYCLE_COUNT_REG             0x3FFFF58

#define  DONE_READ_COUNT_REG         0x3FFFF50
#define  DONE_WRITE_COUNT_REG        0x3FFFF48
#define  DONE_PREFETCH_READ_COUNT_REG      0x3FFFF60
#define  DONE_PREFETCH_WRITE_COUNT_REG     0x3FFFF40


#ifdef  SIM
#define DEVICE_1              "/dev/cxl/afu0.0d"
#else
#define DEVICE_1              "/dev/cxl/afu0.0d"
#define DEVICE_2              "/dev/cxl/afu1.0d"
#endif

struct AFUStatus
{
    uint64_t algo_stop; // afu stopping condition
    uint64_t algo_status;
    uint64_t num_cu;
    uint64_t error;
    uint64_t afu_status;
    uint64_t algo_running;
    uint64_t algo_status_done;
};


struct CmdResponseStats
{
    uint64_t DONE_count        ;
    uint64_t DONE_RESTART_count;
    uint64_t DONE_PREFETCH_READ_count;
    uint64_t DONE_PREFETCH_WRITE_count;
    uint64_t DONE_READ_count   ;
    uint64_t DONE_WRITE_count  ;
    uint64_t PAGED_count       ;
    uint64_t FLUSHED_count     ;
    uint64_t AERROR_count      ;
    uint64_t DERROR_count      ;
    uint64_t FAILED_count      ;
    uint64_t FAULT_count       ;
    uint64_t NRES_count        ;
    uint64_t NLOCK_count       ;
    uint64_t CYCLE_count       ;
};

// ********************************************************************************************
// ***************                      DataStructure                            **************
// ********************************************************************************************

struct __attribute__((__packed__)) WEDStruct
{
    __u32 size_send;                // 4-Bytes
    __u32 size_recive;              // 4-Bytes
    __u32 size3;                    // 4-Bytes
    void *array_send;               // 8-Bytes
    void *array_receive;             // 8-Bytes
    void *pointer1;                 // 8-Bytes
    void *pointer2;                 // 8-Bytes
    void *pointer3;                 // 8-Bytes
    void *pointer4;                 // 8-Bytes
    //---------------------------------------------------//
    void *pointer5;    // 8-Bytes  --// 64bytes
    //---------------------------------------------------//
    void *pointer6;                 // 8-Bytes
    void *pointer7;                 // 8-Bytes
    void *pointer8;                 // 8-Bytes
    void *pointer9;                 // 8-Bytes
    void *pointer10;                // 8-Bytes
    void *pointer11;                // 8-Bytes
    void *pointer12;                // 8-Bytes
    __u32 afu_config;               // 4-Bytes you can specify the read/write command to use the cache or not. 32-bit [0]-read [1]-write
}; // 108-bytes used from 128-Bytes WED;

// ********************************************************************************************
// ***************                        afu_config BIT-MAPPING                 **************
// ********************************************************************************************

#define STRICT 0b000
#define ABORT  0b001
#define PAGE   0b010
#define PREF   0b011
#define SPEC   0b111

#define READ_CL_S    0b1
#define READ_CL_NA   0b0
#define WRITE_MS     0b1
#define WRITE_NA     0b0

// cu_read_engine_control            5-bits STRICT | READ_CL_NA | WRITE_NA 00000 [27:31] [4] [3] [0:2]
// cu_write_engine_control           5-bits STRICT | READ_CL_NA | WRITE_NA 00000 [22:26] [9] [8] [5:7]

#define AFU_CONFIG_STRICT_1  0x00000000  // 0b 00000 00000 00000 00000 00000 00000 00

#ifndef AFU_CONFIG
#define AFU_CONFIG AFU_CONFIG_STRICT_1
#endif

struct WEDStruct *mapDataArraysToWED(struct DataArrays *dataArrays);
void printWEDPointers(struct  WEDStruct *wed);

// ********************************************************************************************
// ***************                  MMIO General                                 **************
// ********************************************************************************************

void printMMIO_error( uint64_t error );

// ********************************************************************************************
// ***************                  AFU General                                  **************
// ********************************************************************************************

int setupAFU(struct cxl_afu_h **afu, struct WEDStruct *wed);
void startAFU(struct cxl_afu_h **afu, struct AFUStatus *afu_status);
void waitJOBRunning(struct cxl_afu_h **afu, struct AFUStatus *afu_status);
void waitAFU(struct cxl_afu_h **afu, struct AFUStatus *afu_status);
void readCmdResponseStats(struct cxl_afu_h **afu, struct CmdResponseStats *cmdResponseStats);
void printCmdResponseStats(struct CmdResponseStats *cmdResponseStats);
void releaseAFU(struct cxl_afu_h **afu);


#endif
