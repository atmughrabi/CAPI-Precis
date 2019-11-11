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
// Revise : 2019-11-11 13:54:58
// Editor : ab
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

#include "libcxl.h"
#include "capienv.h"

int numThreads;
mt19937state *mt19937var;


int
main (int argc, char **argv)
{

    struct cxl_afu_h *afu;
  
    struct Timer *timer = (struct Timer *) my_malloc(sizeof(struct Timer));


    mt19937var = (mt19937state *) my_malloc(sizeof(mt19937state));
    initializeMersenneState (mt19937var, 27491095);

    omp_set_nested(1);
    omp_set_num_threads(numThreads);




    printf("*-----------------------------------------------------*\n");
    printf("| %-20s %-30u | \n", "Number of Threads :", numThreads);
    printf(" -----------------------------------------------------\n");




    // ********************************************************************************************
    // ***************                      DataStructure                            **************
    // ********************************************************************************************

    // (struct GraphCSR *)graph

    // ********************************************************************************************
    // ***************                  MAP CSR DataStructure                        **************
    // ********************************************************************************************

    wedGraphCSR = mapToWED();

    wedGraphCSR->auxiliary1 = divclause;
    wedGraphCSR->auxiliary2 = prnext;
    wedGraphCSR->afu_config = 3; // config to use cache
    wedGraphCSR->afu_config = 0; // config to don't use cache


    // ********************************************************************************************
    // ***************                  CSR DataStructure                            **************
    // ********************************************************************************************

    printWED(wedGraphCSR);
    printWEDPointers(wedGraphCSR);

    // ********************************************************************************************
    // ***************                 Setup AFU                                     **************
    // ********************************************************************************************

    setupAFU(&afu, wedGraphCSR);
    

    struct AFUStatus afu_status;
    afu_status.algo_status = 0;
    afu_status.num_cu = 8; // non zero CU triggers the AFU to work
    afu_status.error = 0;
    afu_status.afu_status = 0;
    afu_status.algo_running = 0;
    afu_status.algo_stop = wedGraphCSR->num_vertices;

    waitJOBRunning(&afu, &afu_status);

    // ********************************************************************************************
    // ***************                 START AFU                                     **************
    // ********************************************************************************************
    printf("Start AFU\n");
    startAFU(&afu, &afu_status);
   
    
    // ********************************************************************************************
    // ***************                 WAIT AFU                                     **************
    // ********************************************************************************************
    printf("Waiting for completion by AFU\n");
    waitAFU(&afu, &afu_status);

    printMMIO_error(afu_status.error);

    printf("count: %lu\n", (((afu_status.algo_status) << 32) >> 32));
    printf("sum: %lu\n", ((afu_status.algo_status) >> 32));

     for (__u32 i = 0; i < ((struct GraphCSR *)graph)->num_vertices; ++i)
    {
        printf("prnext[%u] = %u \n", i,prnext[i]);
    }

    // ********************************************************************************************
    // ***************                 Releasing AFU                                     **************
    // ********************************************************************************************

    printf("Releasing AFU\n");
    releaseAFU(&afu);

    free(timer);
    exit (0);
}





