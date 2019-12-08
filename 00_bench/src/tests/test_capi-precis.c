// -----------------------------------------------------------------------------
//
//      "CAPIPrecis"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi
// Email  : atmughra@ncsu.edu||atmughrabi@gmail.com
// File   : test_capi-precis.c
// Create : 2019-07-29 16:52:00
// Revise : 2019-11-12 18:31:25
// Editor : Abdullah Mughrabi
// -----------------------------------------------------------------------------
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <argp.h>
#include <stdbool.h>
#include <omp.h>
#include <assert.h>

#include "myMalloc.h"
#include "mt19937.h"
#include "timer.h"

#include "config.h"
#include "algorithm.h"

int numThreads;
mt19937state *mt19937var;


int
main (int argc, char **argv)
{

    struct Arguments arguments;

    arguments.numThreads = 4;
    arguments.size = 1073741824;

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

    printf("*-----------------------------------------------------*\n");
    printf("| %-30s %-20u | \n", "Copy data (SIZE)", arguments.size);
    printf(" -----------------------------------------------------\n");

    Start(timer);
    copyDataArrays(dataArrays);
    Stop(timer);
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

    freeDataArrays(dataArrays);
    free(timer);
    exit (0);
}





