// -----------------------------------------------------------------------------
//
//      "00_AccelGraph"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi
// Email  : atmughra@ncsu.edu||atmughrabi@gmail.com
// File   : test_afu.c
// Create : 2019-09-28 15:19:20
// Revise : 2019-11-12 19:48:21
// Editor : Abdullah Mughrabi
// -----------------------------------------------------------------------------

#include <string.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <argp.h>
#include <stdbool.h>
#include <omp.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "myMalloc.h"
#include "mt19937.h"
#include "timer.h"
#include "config.h"


#include "libcxl.h"
#include "capienv.h"
#include "algorithm.h"



int numThreads;
mt19937state *mt19937var;


int
main (int argc, char **argv)
{

    struct cxl_afu_h *afu;
    struct Arguments arguments;

    arguments.numThreads = 4;
    arguments.size = 256;

    struct Timer *timer = (struct Timer *) my_malloc(sizeof(struct Timer));
    numThreads = arguments.numThreads;
    mt19937var = (mt19937state *) my_malloc(sizeof(mt19937state));
    initializeMersenneState (mt19937var, 27491095);

    omp_set_nested(1);
    omp_set_num_threads(numThreads);


    printf("*-----------------------------------------------------*\n");
    printf("| %-20s %-30u | \n", "Number of Threads :", numThreads);
    printf(" -----------------------------------------------------\n");


    printf("*-----------------------------------------------------*\n");
    printf("| %-30s %-20u | \n", "Allocating Data Arrays (SIZE)", arguments.size);
    printf(" -----------------------------------------------------\n");

    struct DataArrays *dataArrays = newDataArrays(&arguments);

    printf("*-----------------------------------------------------*\n");
    printf("| %-30s %-20u | \n", "Populating Data Arrays (Seed)", 27491095);
    printf(" -----------------------------------------------------\n");

    initializeDataArrays(dataArrays);

    // ********************************************************************************************
    // ***************                  MAP CSR DataStructure                        **************
    // ********************************************************************************************

    struct WEDStruct *wed = mapDataArraysToWED(dataArrays);

    // ********************************************************************************************
    // ***************                  CSR DataStructure                            **************
    // ********************************************************************************************

    printWEDPointers(wed);

    // ********************************************************************************************
    // ***************                 Setup AFU                                     **************
    // ********************************************************************************************

    setupAFU(&afu, wed);
    
    struct AFUStatus afu_status;
    afu_status.algo_status = 0;
    afu_status.num_cu = 8; // non zero CU triggers the AFU to work
    afu_status.error = 0;
    afu_status.afu_status = 0;
    afu_status.algo_running = 0;
    afu_status.algo_stop = wed->size_send;

    waitJOBRunning(&afu, &afu_status);

    // ********************************************************************************************
    // ***************                 START AFU                                     **************
    // ********************************************************************************************
    printf("Start AFU\n");
    startAFU(&afu, &afu_status);
   
    // ********************************************************************************************
    // ***************                 WAIT AFU                                     **************
    // ********************************************************************************************

    printf("*-----------------------------------------------------*\n");
    printf("| %-30s %-20u | \n", "Copy data (SIZE)", arguments.size);
    printf(" -----------------------------------------------------\n");

   

    printf("Waiting for completion by AFU\n");
    Start(timer);
    waitAFU(&afu, &afu_status);
    Stop(timer);
    printMMIO_error(afu_status.error);

    printf("count_read: %lu\n", (((afu_status.algo_status) << 32) >> 32));
    printf("count_write: %lu\n", ((afu_status.algo_status) >> 32));

  
    printf("| %-22s | %-27.20lf| \n","Time (Seconds)", Seconds(timer));
       
    double bandwidth_GB = (double)((double)(dataArrays->size)/(double)(1024*1024*256))/Seconds(timer);  //GB/s
    double bandwidth_MB = (double)((double)(dataArrays->size)/(double)(1024*256))/Seconds(timer); //MB/s

    printf("| %-22s | %-27.20lf| \n","BandWidth MB/s", bandwidth_MB);
    printf("| %-22s | %-27.20lf| \n","BandWidth GB/s", bandwidth_GB);

    __u32 missmatch = 0;
    missmatch = compareDataArrays(dataArrays);

    printf("*-----------------------------------------------------*\n");
    printf("| %-30s %-20u | \n", "Data Missmatched (#)", missmatch);
    printf(" -----------------------------------------------------\n");

       if(missmatch != 0)
    {
        printf("FAIL\n");
    }  else
    {
        printf("PASS\n");
    }

    printf("*-----------------------------------------------------*\n");
    printf("| %-30s %-20u | \n", "Freeing Data Arrays (SIZE)", arguments.size);
    printf(" -----------------------------------------------------\n");



    // ********************************************************************************************
    // ***************                 Releasing AFU                                     **************
    // ********************************************************************************************

    printf("Releasing AFU\n");
    releaseAFU(&afu);

    freeDataArrays(dataArrays);
    free(timer);
    exit (0);
}





