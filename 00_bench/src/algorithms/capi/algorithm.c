// -----------------------------------------------------------------------------
//
//      "00_AccelGraph"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi
// Email  : atmughra@ncsu.edu||atmughrabi@gmail.com
// File   : algorithm.c
// Create : 2019-09-28 14:41:30
// Revise : 2019-11-12 18:54:51
// Editor : Abdullah Mughrabi
// -----------------------------------------------------------------------------

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <math.h>
#include <omp.h>

#include "timer.h"
#include "myMalloc.h"
#include "config.h"


#include "libcxl.h"
#include "capienv.h"

#include "algorithm.h"

struct DataArrays *newDataArrays(struct Arguments *arguments){

	struct DataArrays *dataArrays = (struct DataArrays *) my_malloc(sizeof(struct DataArrays));

	dataArrays->size = arguments->size;

	dataArrays->array_send = (__u32 *) my_malloc(sizeof(__u32)* (dataArrays->size));
	dataArrays->array_receive = (__u32 *) my_malloc(sizeof(__u32)* (dataArrays->size));

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

	__u32 i;

	#pragma omp parallel for
    for(i = 0; i < dataArrays->size; i++)
    {
        dataArrays->array_send[i] = generateRandInt(mt19937var);
        dataArrays->array_receive[i] = 0;
    }
}


__u32 compareDataArrays(struct DataArrays *dataArrays){

	__u32 missmatch = 0;
	__u32 i;

	#pragma omp parallel for shared(dataArrays) reduction(+: missmatch)
    for(i = 0; i < dataArrays->size; i++)
    {
        if(dataArrays->array_receive[i] != dataArrays->array_send[i])
        	missmatch ++;
    }

    return missmatch;
}

void copyDataArrays(struct DataArrays *dataArrays){

	__u32 i;

	#pragma omp parallel for
    for(i = 0; i < dataArrays->size; i++)
    {
        dataArrays->array_receive[i] = dataArrays->array_send[i];
    }

}
