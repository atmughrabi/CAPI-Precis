// -----------------------------------------------------------------------------
//
//      "CAPIPrecis"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi
// Email  : atmughra@ncsu.edu||atmughrabi@gmail.com
// File   : capienv.c
// Create : 2019-10-09 19:20:39
// Revise : 2019-12-01 00:12:59
// Editor : Abdullah Mughrabi
// -----------------------------------------------------------------------------

#include <linux/types.h>
#include <stdio.h>
#include <stdlib.h>

#include "myMalloc.h"
#include "libcxl.h"
#include "capienv.h"

#include "algorithm.h"

// ********************************************************************************************
// ***************                  AFU General                                  **************
// ********************************************************************************************

int setupAFU(struct cxl_afu_h **afu, struct WEDStruct *wed)
{

    (*afu) = cxl_afu_open_dev(DEVICE_1);
    if(!afu)
    {
        printf("Failed to open AFU: %m\n");
        return 1;
    }

    cxl_afu_attach((*afu), (__u64)wed);
    int base_address = cxl_mmio_map ((*afu), CXL_MMIO_BIG_ENDIAN);

    if (base_address < 0)
    {
        printf("fail cxl_mmio_map %d", base_address);
        return 1;
    }

    return 0;

}

void startAFU(struct cxl_afu_h **afu, struct AFUStatus *afu_status)
{
#ifdef  VERBOSE
    printf("AFU configuration start status(0x%08llx) \n", (afu_status->afu_status) );
#endif
    do
    {
        cxl_mmio_write64((*afu), AFU_CONFIGURE, afu_status->afu_config);
        cxl_mmio_read64((*afu), AFU_STATUS, (uint64_t *) & (afu_status->afu_status));
    }
    while(!(afu_status->afu_status));
#ifdef  VERBOSE
    printf("AFU configuration done status(0x%08llx) \n", (afu_status->afu_status) );
#endif
}

void startCU(struct cxl_afu_h **afu, struct AFUStatus *afu_status)
{
#ifdef  VERBOSE
    printf("CU configuration start status(0x%08llx) \n", (afu_status->cu_status) );
#endif
    do
    {
        cxl_mmio_write64((*afu), CU_CONFIGURE, (uint64_t)afu_status->cu_config);
        cxl_mmio_read64((*afu), CU_STATUS, (uint64_t *) & (afu_status->cu_status));
    }
    while(!((afu_status->cu_status)));
#ifdef  VERBOSE
    printf("CU configuration done status(0x%08llx) \n", (afu_status->cu_status) );
#endif
}

void waitAFU(struct cxl_afu_h **afu, struct AFUStatus *afu_status)
{

    struct CmdResponseStats cmdResponseStats = {0};

    do
    {
        // Poll for errors always
        cxl_mmio_read64((*afu), ERROR_REG, (uint64_t *) & (afu_status->error));
        cxl_mmio_write64((*afu), ERROR_REG_ACK, (uint64_t)afu_status->error);

        // read final return result
        cxl_mmio_read64((*afu), CU_RETURN_DONE, (uint64_t *) & (afu_status->cu_return_done));

        // if((((afu_status->cu_return_done) << 32) >> 32) >= (afu_status->cu_stop))
        //     break;

        if((afu_status->cu_return_done) >= (afu_status->cu_stop))
        {
            readCmdResponseStats(afu, &cmdResponseStats);
            cxl_mmio_write64((*afu), CU_RETURN_DONE_ACK, (uint64_t)afu_status->cu_return_done);
            break;
        }
    }
    while((!(afu_status->error)));

#ifdef  VERBOSE
    printCmdResponseStats(&cmdResponseStats);

    printf("*-----------------------------------------------------*\n");
    printf("| %-15s %-18s %-15s  | \n", " ", "Rd/Wrt Stats", " ");
    printf(" -----------------------------------------------------\n");
    printf("| count_read  : %llu\n", (afu_status->cu_return_done));
    printf("| count_write : %llu\n", (afu_status->cu_return_done));
    printf("*-----------------------------------------------------*\n");
#endif

}

void readCmdResponseStats(struct cxl_afu_h **afu, struct CmdResponseStats *cmdResponseStats)
{


    cxl_mmio_read64((*afu), DONE_COUNT_REG, (uint64_t *) & (cmdResponseStats->DONE_count));
    cxl_mmio_read64((*afu), DONE_RESTART_COUNT_REG, (uint64_t *) & (cmdResponseStats->DONE_RESTART_count));

    cxl_mmio_read64((*afu), DONE_PREFETCH_READ_COUNT_REG, (uint64_t *) & (cmdResponseStats->DONE_PREFETCH_READ_count));
    cxl_mmio_read64((*afu), DONE_PREFETCH_WRITE_COUNT_REG, (uint64_t *) & (cmdResponseStats->DONE_PREFETCH_WRITE_count));

    cxl_mmio_read64((*afu), PAGED_COUNT_REG, (uint64_t *) & (cmdResponseStats->PAGED_count));
    cxl_mmio_read64((*afu), FLUSHED_COUNT_REG, (uint64_t *) & (cmdResponseStats->FLUSHED_count));
    cxl_mmio_read64((*afu), AERROR_COUNT_REG, (uint64_t *) & (cmdResponseStats->AERROR_count));
    cxl_mmio_read64((*afu), DERROR_COUNT_REG, (uint64_t *) & (cmdResponseStats->DERROR_count));
    cxl_mmio_read64((*afu), FAILED_COUNT_REG, (uint64_t *) & (cmdResponseStats->FAILED_count));
    cxl_mmio_read64((*afu), FAULT_COUNT_REG, (uint64_t *) & (cmdResponseStats->FAULT_count));
    cxl_mmio_read64((*afu), NRES_COUNT_REG, (uint64_t *) & (cmdResponseStats->NRES_count));
    cxl_mmio_read64((*afu), NLOCK_COUNT_REG, (uint64_t *) & (cmdResponseStats->NLOCK_count));
    cxl_mmio_read64((*afu), CYCLE_COUNT_REG, (uint64_t *) & (cmdResponseStats->CYCLE_count));
    cxl_mmio_read64((*afu), DONE_READ_COUNT_REG, (uint64_t *) & (cmdResponseStats->DONE_READ_count));
    cxl_mmio_read64((*afu), DONE_WRITE_COUNT_REG, (uint64_t *) & (cmdResponseStats->DONE_WRITE_count));

}

void printCmdResponseStats(struct CmdResponseStats *cmdResponseStats)
{
    printf("*-----------------------------------------------------*\n");
    printf("| %-15s %-18s %-15s | \n", " ", "AFU Stats", " ");
    printf(" -----------------------------------------------------\n");
    printf("| CYCLE_count        : %llu\n", cmdResponseStats->CYCLE_count);
    printf("*-----------------------------------------------------*\n");
    printf("| %-15s %-18s %-15s | \n", " ", "Responses Stats", " ");
    printf(" -----------------------------------------------------\n");
    printf("| DONE_count               : %llu\n", cmdResponseStats->DONE_count);
    printf(" -----------------------------------------------------\n");
    printf("| DONE_READ_count          : %llu\n", cmdResponseStats->DONE_READ_count);
    printf("| DONE_WRITE_count         : %llu\n", cmdResponseStats->DONE_WRITE_count);
    printf(" -----------------------------------------------------\n");
    printf("| DONE_RESTART_count       : %llu\n", cmdResponseStats->DONE_RESTART_count);
    printf(" -----------------------------------------------------\n");
    printf("| DONE_PREFETCH_READ_count : %llu\n", cmdResponseStats->DONE_PREFETCH_READ_count);
    printf("| DONE_PREFETCH_WRITE_count: %llu\n", cmdResponseStats->DONE_PREFETCH_WRITE_count);
    printf(" -----------------------------------------------------\n");
    printf("| PAGED_count        : %llu\n", cmdResponseStats->PAGED_count);
    printf("| FLUSHED_count      : %llu\n", cmdResponseStats->FLUSHED_count);
    printf("| AERROR_count       : %llu\n", cmdResponseStats->AERROR_count);
    printf("| DERROR_count       : %llu\n", cmdResponseStats->DERROR_count);
    printf("| FAILED_count       : %llu\n", cmdResponseStats->FAILED_count);
    printf("| NRES_count         : %llu\n", cmdResponseStats->NRES_count);
    printf("| NLOCK_count        : %llu\n", cmdResponseStats->NLOCK_count);
    printf("*-----------------------------------------------------*\n");
}

void releaseAFU(struct cxl_afu_h **afu)
{
    cxl_mmio_unmap ((*afu));
    cxl_afu_free((*afu));
}

// ********************************************************************************************
// ***************                  MMIO General                                 **************
// ********************************************************************************************

void printMMIO_error( uint64_t error )
{
    if(error >> 14)
    {
        printf("(BIT-14) Credit Overflow AFU Error\n");
    }
    else if(error >> 12)
    {
        switch(error >> 12)
        {
        case 1:
            printf("(BIT-12) Job Address Error\n");
            break;
        case 2:
            printf("(BIT-13) Job Command Error\n");
            break;
        }
    }
    else if(error >> 10)
    {
        switch(error >> 10)
        {
        case 1:
            printf("(BIT-10) MMIO Address Parity-Error\n");
            break;
        case 2:
            printf("(BIT-11) MMIO Data Parity-Error\n");
            break;
        }

    }
    else if(error >> 9)
    {
        printf("(BIT-9) Write Tag Parity-Error\n");
    }
    else if(error >> 7)
    {
        switch(error >> 7)
        {
        case 1:
            printf("(BIT-7) Read Data Parity-Error\n");
            break;
        case 2:
            printf("(BIT-8) Read Tag Parity-Error\n");
            break;
        }

    }
    else if(error >> 0)
    {
        switch(error >> 0)
        {
        case 1:
            printf("(BIT-0) Response AERROR\n");
            break;
        case 2:
            printf("(BIT-1) Response DERROR\n");
            break;
        case 4:
            printf("(BIT-2) Response FAILD\n");
            break;
        case 8:
            printf("(BIT-3) Response FAULT\n");
            break;
        case 16:
            printf("(BIT-4) Response NRES\n");
            break;
        case 32:
            printf("(BIT-5) Response NLOCK\n");
            break;
        case 64:
            printf("(BIT-6) Response tag Parity-Error\n");
            break;
        }
    }

}

// ********************************************************************************************
// ***************                  CSR DataStructure                            **************
// ********************************************************************************************

struct  WEDStruct *mapDataArraysToWED(struct DataArrays *dataArrays)
{

    struct WEDStruct *wed = my_malloc(sizeof(struct WEDStruct));

    wed->size_send    = dataArrays->size;
    wed->size_recive  = dataArrays->size;
    wed->array_send     = dataArrays->array_send;
    wed->array_receive  = dataArrays->array_receive;


#ifdef  VERBOSE
    printWEDPointers(wed);
#endif

    return wed;
}


void printWEDPointers(struct  WEDStruct *wed)
{

    printf("*-----------------------------------------------------*\n");
    printf("| %-15s %-18s %-15s | \n", " ", "WEDStruct structure", " ");
    printf(" -----------------------------------------------------\n");
    printf("  wed               : %p\n", wed);
    printf("  wed->size_send    : %llu\n", wed->size_send);
    printf("  wed->size_recive  : %llu\n", wed->size_recive);
    printf("  wed->array_send   : %p\n", wed->array_send);
    printf("  wed->array_receive: %p\n", wed->array_receive);


}
