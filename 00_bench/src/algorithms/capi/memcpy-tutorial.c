// -----------------------------------------------------------------------------
//
//      "CAPIPrecis"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi
// Email  : atmughra@ncsu.edu||atmughrabi@gmail.com
// File   : memcpy.c
// Create : 2019-09-28 14:41:30
// Revise : 2019-11-29 11:17:40
// Editor : Abdullah Mughrabi
// -----------------------------------------------------------------------------
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <string.h>
#include <math.h>
#include <omp.h>

#include "mt19937.h"
#include "timer.h"
#include "myMalloc.h"
#include "config.h"

//CAPI
#include "libcxl.h"
#include "capienv.h"

#include "memcpy-tutorial.h"

struct DataArraysTut *newDataArraysTut(struct Arguments *arguments){

	struct DataArraysTut *dataArraysTut = (struct DataArraysTut *) my_malloc(sizeof(struct DataArraysTut));

	dataArraysTut->size = arguments->size;

	dataArraysTut->array_send = (uint32_t *) my_malloc(sizeof(uint32_t)* (dataArraysTut->size));
	dataArraysTut->array_receive = (uint32_t *) my_malloc(sizeof(uint32_t)* (dataArraysTut->size));

	return dataArraysTut;

}

void freeDataArraysTut(struct DataArraysTut *dataArraysTut){

	if(dataArraysTut){
		if(dataArraysTut->array_send)
			free(dataArraysTut->array_send);
		if(dataArraysTut->array_receive)
			free(dataArraysTut->array_receive);
		free(dataArraysTut);
	}
}

void initializeDataArraysTut(struct DataArraysTut *dataArraysTut){

	uint64_t i;

	#pragma omp parallel for
    for(i = 0; i < dataArraysTut->size; i++)
    {
        dataArraysTut->array_send[i] = i;
        dataArraysTut->array_receive[i] = 0;
    }
}

void copyDataArraysTut(struct DataArraysTut *dataArraysTut, struct Arguments *arguments){

	// uint64_t i;

	// #pragma omp parallel for
 //    for(i = 0; i < dataArraysTut->size; i++)
 //    {
 //    	//generate READ_CL_NA  array_send[i] // read engine
 //    	//generate WRITE_CL  array_receive[i] // write engine
 //        dataArraysTut->array_receive[i] = dataArraysTut->array_send[i];
 //    }

	struct cxl_afu_h *afu;

	// ********************************************************************************************
    // ***************                  MAP CSR DataStructure                        **************
    // ********************************************************************************************

    struct WEDStructTut *wed = mapDataArraysTutToWED(dataArraysTut);

    // ********************************************************************************************
    // ***************                 Setup AFU                                     **************
    // ********************************************************************************************

    setupAFUTut(&afu, wed);

    struct AFUStatus afu_status = {0};
    afu_status.afu_config = arguments->afu_config;
    afu_status.afu_config_2 = arguments->afu_config_2;
    afu_status.cu_config = arguments->cu_config; // non zero CU triggers the AFU to work
    afu_status.cu_config = ((afu_status.cu_config << 24) | (arguments->numThreads));
    afu_status.cu_config_2 = afu_status.cu_config_2;
    afu_status.cu_config_3 = 1 ;
    afu_status.cu_config_4 = 1 ;
    afu_status.cu_stop = wed->size_send;

    startAFU(&afu, &afu_status);

    // ********************************************************************************************
    // ***************                 START AFU                                     **************
    // ********************************************************************************************

    startCU(&afu, &afu_status);

    // ********************************************************************************************
    // ***************                 WAIT AFU                                     **************
    // ********************************************************************************************

    waitAFU(&afu, &afu_status);

    printMMIO_error(afu_status.error);

    releaseAFU(&afu);
    free(wed);



}

uint64_t compareDataArraysTut(struct DataArraysTut *dataArraysTut){

	uint64_t missmatch = 0;
	uint64_t i;

	#pragma omp parallel for shared(dataArraysTut) reduction(+: missmatch)
    for(i = 0; i < dataArraysTut->size; i++)
    {
        if(dataArraysTut->array_receive[i] != dataArraysTut->array_send[i]){
        	// printf("[%llu] %u != %u\n",i , dataArraysTut->array_receive[i], dataArraysTut->array_send[i] );
        	missmatch ++;
        }
    }

    return missmatch;
}