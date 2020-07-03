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

	uint64_t i;

	#pragma omp parallel for
    for(i = 0; i < dataArraysTut->size; i++)
    {
    	//generate READ_CL_NA  array_send[i] // read engine
    	//generate WRITE_CL  array_receive[i] // write engine
        dataArraysTut->array_receive[i] = dataArraysTut->array_send[i];
    }

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