// -----------------------------------------------------------------------------
//
//      "00_AccelGraph"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi
// Email  : atmughra@ncsu.edu||atmughrabi@gmail.com
// File   : capienv.c
// Create : 2019-10-09 19:20:39
// Revise : 2019-11-29 10:29:32
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

void waitJOBRunning(struct cxl_afu_h **afu, struct AFUStatus *afu_status)
{
    do
    {
        cxl_mmio_read64((*afu), AFU_STATUS, &(afu_status->afu_status));

#ifdef  VERBOSE
        printf("waitJOBRunning %lu \n", (afu_status->afu_status) );
#endif

    }
    while(!(afu_status->afu_status));
}

void startAFU(struct cxl_afu_h **afu, struct AFUStatus *afu_status)
{
    do
    {
        cxl_mmio_write64((*afu), ALGO_REQUEST, afu_status->num_cu);
        cxl_mmio_read64((*afu), ALGO_RUNNING, &(afu_status->algo_running));

#ifdef  VERBOSE
        printf("startAFU %lu \n", (afu_status->algo_running) );
#endif

    }
    while(!((afu_status->algo_running)));
}

void waitAFU(struct cxl_afu_h **afu, struct AFUStatus *afu_status)
{

    struct CmdResponseStats cmdResponseStats = {0};

    do
    {

        cxl_mmio_read64((*afu), ERROR_REG, &(afu_status->error));
        cxl_mmio_write64((*afu), ERROR_REG_ACK, afu_status->error);

        cxl_mmio_read64((*afu), ALGO_STATUS_DONE, &(afu_status->algo_status_done));
        // if((((afu_status->algo_status_done) << 32) >> 32) >= (afu_status->algo_stop))
        //     break;

        if((((afu_status->algo_status_done)) >> 32) >= (afu_status->algo_stop)){
            readCmdResponseStats(afu, &cmdResponseStats);
            cxl_mmio_write64((*afu), ALGO_STATUS_DONE_ACK, afu_status->algo_status_done);
            break;
        }
    }
    while((!(afu_status->error)));

#ifdef  VERBOSE
    printCmdResponseStats(&cmdResponseStats);

    printf("*-----------------------------------------------------*\n");
    printf("| %-15s %-18s %-15s | \n", " ", "Rd/Wrt Stats", " ");
    printf(" -----------------------------------------------------\n");
    printf("count_read : %lu\n", (((afu_status->algo_status_done) << 32) >> 32) );
    printf("count_write: %lu\n", ((afu_status->algo_status_done) >> 32));
#endif

}

void readCmdResponseStats(struct cxl_afu_h **afu, struct CmdResponseStats *cmdResponseStats)
{

    cxl_mmio_read64((*afu), DONE_COUNT_REG, &(cmdResponseStats->DONE_count));
    cxl_mmio_read64((*afu), DONE_RESTART_COUNT_REG, &(cmdResponseStats->DONE_RESTART_count));
    cxl_mmio_read64((*afu), PAGED_COUNT_REG, &(cmdResponseStats->PAGED_count));
    cxl_mmio_read64((*afu), FLUSHED_COUNT_REG, &(cmdResponseStats->FLUSHED_count));
    cxl_mmio_read64((*afu), AERROR_COUNT_REG, &(cmdResponseStats->AERROR_count));
    cxl_mmio_read64((*afu), DERROR_COUNT_REG, &(cmdResponseStats->DERROR_count));
    cxl_mmio_read64((*afu), FAILED_COUNT_REG, &(cmdResponseStats->FAILED_count));
    cxl_mmio_read64((*afu), FAULT_COUNT_REG, &(cmdResponseStats->FAULT_count));
    cxl_mmio_read64((*afu), NRES_COUNT_REG, &(cmdResponseStats->NRES_count));
    cxl_mmio_read64((*afu), NLOCK_COUNT_REG, &(cmdResponseStats->NLOCK_count));

}

void printCmdResponseStats(struct CmdResponseStats *cmdResponseStats)
{

    printf("*-----------------------------------------------------*\n");
    printf("| %-15s %-18s %-15s | \n", " ", "Responses Stats", " ");
    printf(" -----------------------------------------------------\n");

    printf("DONE_count        : %lu\n", cmdResponseStats->DONE_count);
    printf("DONE_RESTART_count: %lu\n", cmdResponseStats->DONE_RESTART_count);
    printf("PAGED_count       : %lu\n", cmdResponseStats->PAGED_count);
    printf("FLUSHED_count     : %lu\n", cmdResponseStats->FLUSHED_count);
    printf("AERROR_count      : %lu\n", cmdResponseStats->AERROR_count);
    printf("DERROR_count      : %lu\n", cmdResponseStats->DERROR_count);
    printf("FAILED_count      : %lu\n", cmdResponseStats->FAILED_count);
    printf("NRES_count        : %lu\n", cmdResponseStats->NRES_count);
    printf("NLOCK_count       : %lu\n", cmdResponseStats->NLOCK_count);

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

    if(error >> 12)
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


    wed->afu_config = AFU_CONFIG;

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
    printf("  wed: %p\n", wed);

    printf("  wed->size_send: %u\n", wed->size_send);
    printf("  wed->size_recive: %u\n", wed->size_recive);

    printf("  wed->array_send: %p\n", wed->array_send);
    printf("  wed->array_receive: %p\n", wed->array_receive);

    printf("  wed->afu_config: %p\n", &(wed->afu_config));

}
