#ifndef CAPIENV_H
#define CAPIENV_H

#include <linux/types.h>
#include "myMalloc.h"
#include "libcxl.h"

#include "algorithm.h"

// ********************************************************************************************
// ***************                  MMIO General                                 **************
// ********************************************************************************************

#define AFU_CONFIGURE           0x3FFFFF8
#define AFU_STATUS              0x3FFFFF0             // running counters that you can read continuosly

#define CU_CONFIGURE            0x3FFFFE8             // 0x3fffff8 >> 2 = 0xfffffc
#define CU_STATUS               0x3FFFFE0

#define CU_RETURN               0x3FFFFD8             // 0x3fffff8 >> 2 = 0xfffffe
#define CU_RETURN_ACK           0x3FFFFD0

#define  CU_RETURN_DONE         0x3FFFFC8
#define  CU_RETURN_DONE_ACK     0x3FFFFC0

#define ERROR_REG               0x3FFFFB8
#define ERROR_REG_ACK           0x3FFFFB0

// ********************************************************************************************
// ***************                  AFU  Stats                                   **************
// ********************************************************************************************

#define  DONE_COUNT_REG                     0x3FFFFA8
#define  DONE_RESTART_COUNT_REG             0x3FFFFA0
#define  DONE_READ_COUNT_REG                0x3FFFF98
#define  DONE_WRITE_COUNT_REG               0x3FFFF90
#define  DONE_PREFETCH_READ_COUNT_REG       0x3FFFF88
#define  DONE_PREFETCH_WRITE_COUNT_REG      0x3FFFF80

#define  PAGED_COUNT_REG                    0x3FFFF78
#define  FLUSHED_COUNT_REG                  0x3FFFF70
#define  AERROR_COUNT_REG                   0x3FFFF68
#define  DERROR_COUNT_REG                   0x3FFFF60
#define  FAILED_COUNT_REG                   0x3FFFF58
#define  FAULT_COUNT_REG                    0x3FFFF50
#define  NRES_COUNT_REG                     0x3FFFF48
#define  NLOCK_COUNT_REG                    0x3FFFF40
#define  CYCLE_COUNT_REG                    0x3FFFF38



#ifdef  SIM
#define DEVICE_1              "/dev/cxl/afu0.0d"
#else
#define DEVICE_1              "/dev/cxl/afu0.0d"
#define DEVICE_2              "/dev/cxl/afu1.0d"
#endif

struct AFUStatus
{
    __u64 cu_stop;  // afu stopping condition
    __u64 cu_config;
    __u64 cu_status;
    __u64 cu_mode;
    __u64 afu_config;
    __u64 afu_status;
    __u64 error;
    __u64 cu_return; // running return
    __u64 cu_return_done; // final return when cu send done
};


struct CmdResponseStats
{
    __u64 DONE_count        ;
    __u64 DONE_RESTART_count;
    __u64 DONE_PREFETCH_READ_count;
    __u64 DONE_PREFETCH_WRITE_count;
    __u64 DONE_READ_count   ;
    __u64 DONE_WRITE_count  ;
    __u64 PAGED_count       ;
    __u64 FLUSHED_count     ;
    __u64 AERROR_count      ;
    __u64 DERROR_count      ;
    __u64 FAILED_count      ;
    __u64 FAULT_count       ;
    __u64 NRES_count        ;
    __u64 NLOCK_count       ;
    __u64 CYCLE_count       ;
};

// ********************************************************************************************
// ***************                      DataStructure                            **************
// ********************************************************************************************

struct __attribute__((__packed__)) WEDStruct
{
    __u64 size_send;                // 8-Bytes
    __u64 size_recive;              // 8-Bytes
    void *array_send;               // 8-Bytes
    void *array_receive;            // 8-Bytes
    void *pointer1;                 // 8-Bytes
    void *pointer2;                 // 8-Bytes
    void *pointer3;                 // 8-Bytes
    void *pointer4;                 // 8-Bytes
    //---------------------------------------------------//--// 64bytes
    void *pointer5;                 // 8-Bytes
    void *pointer6;                 // 8-Bytes
    void *pointer7;                 // 8-Bytes
    void *pointer8;                 // 8-Bytes
    void *pointer9;                 // 8-Bytes
    void *pointer10;                // 8-Bytes
    void *pointer11;                // 8-Bytes
    void *pointer12;                // 8-Bytes
}; // 32-bytes used from 128-Bytes WED;

// ********************************************************************************************
// ***************                        afu_config BIT-MAPPING                 **************
// ********************************************************************************************

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
void startCU(struct cxl_afu_h **afu, struct AFUStatus *afu_status);
void waitAFU(struct cxl_afu_h **afu, struct AFUStatus *afu_status);
void readCmdResponseStats(struct cxl_afu_h **afu, struct CmdResponseStats *cmdResponseStats);
void printCmdResponseStats(struct CmdResponseStats *cmdResponseStats);
void releaseAFU(struct cxl_afu_h **afu);


#endif
