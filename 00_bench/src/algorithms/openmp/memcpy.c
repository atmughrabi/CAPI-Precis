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

#include "memcpy.h"

struct DataArrays *newDataArrays(struct Arguments *arguments){

	struct DataArrays *dataArrays = (struct DataArrays *) my_malloc(sizeof(struct DataArrays));

	dataArrays->size = arguments->size;

	dataArrays->array_send = (uint32_t *) my_malloc(sizeof(uint32_t)* (dataArrays->size));
	dataArrays->array_receive = (uint32_t *) my_malloc(sizeof(uint32_t)* (dataArrays->size));

	return dataArrays;

}

void freeDataArrays(struct DataArrays *dataArrays){

	if(dataArrays){
		if(dataArrays->array_send)
			free(dataArrays->array_send);
		if(dataArrays->array_receive)
			free(dataArrays->array_receive);
		free(dataArrays);
	}
}


void initializeDataArrays(struct DataArrays *dataArrays){

	uint64_t i;

	#pragma omp parallel for
    for(i = 0; i < dataArrays->size; i++)
    {
        dataArrays->array_send[i] = i;
        dataArrays->array_receive[i] = 0;
    }
}


uint64_t compareDataArrays(struct DataArrays *dataArrays){

	uint64_t missmatch = 0;
	uint64_t i;

	#pragma omp parallel for shared(dataArrays) reduction(+: missmatch)
    for(i = 0; i < dataArrays->size; i++)
    {
        if(dataArrays->array_receive[i] != dataArrays->array_send[i]){
        	// printf("[%llu] %u != %u\n",i , dataArrays->array_receive[i], dataArrays->array_send[i] );
        	missmatch ++;
        }
    }

    return missmatch;
}

void copyDataArrays(struct DataArrays *dataArrays, struct Arguments *arguments){

	uint64_t i;

	#pragma omp parallel for
    for(i = 0; i < dataArrays->size; i++)
    {
        dataArrays->array_receive[i] = dataArrays->array_send[i];
    }

}
