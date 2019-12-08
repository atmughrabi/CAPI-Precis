// -----------------------------------------------------------------------------
//
//      "CAPIPrecis"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi
// Email  : atmughra@ncsu.edu||atmughrabi@gmail.com
// File   : capi-precis.c
// Create : 2019-07-29 16:52:00
// Revise : 2019-11-12 18:34:03
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

const char *argp_program_version =
    "CAPIPrecis 1.0";
const char *argp_program_bug_address =
    "<atmughra@ncsu.edu>";
/* Program documentation. */
static char doc[] =
    "CAPIPrecis is an open source CAPI enabled FPGA processing framework, it is designed to abstract the PSL layer for a faster development cycle";

/* A description of the arguments we accept. */
static char args_doc[] = "-s <size> -n [num threads] -a [afu config] -c [cu config]  ";

/* The options we understand. */
static struct argp_option options[] =
{
    {
        "num-threads",       'n', "[DEFAULT:MAX]",      0,
        "\nDefault:max number of threads the system has"
    },
    {
        "size",         's', "SIZE:512",      0,
        "\nSize of array to be sent and copied back "
    },
    {
        "afu-config",         'a', "[DEFAULT:0x1]",      0,
        "\nafu buffer arbitration 0x01 round robin 0x10 fix priority"
    },
    {
        "cu-config",         'c', "[DEFAULT:0x01]",      0,
        "\nCU configurations for requests cached/non cached/prefetcher active or not check README for more explanation"
    },
    { 0 }
};



/* Parse a single option. */
static error_t
parse_opt (int key, char *arg, struct argp_state *state)
{
    /* Get the input argument from argp_parse, which we
       know is a pointer to our arguments structure. */
    struct Arguments *arguments = state->input;
    char *eptr;

    switch (key)
    {
    case 's':
        arguments->size = strtoll(arg, &eptr, 0);
        break;
    case 'n':
        arguments->numThreads = atoi(arg);
        break;
    case 'a':
        arguments->afu_config = strtoll(arg, &eptr, 0);
        break;
    case 'c':
        arguments->cu_config = strtoll(arg, &eptr, 0);
        break;
    default:
        return ARGP_ERR_UNKNOWN;
    }
    return 0;
}


static struct argp argp = { options, parse_opt, args_doc, doc };



int
main (int argc, char **argv)
{

    struct Arguments arguments;

    arguments.numThreads = omp_get_max_threads();
    arguments.size = 512;
    arguments.afu_config = 0x01;
    arguments.cu_config  = 0x01;

     argp_parse (&argp, argc, argv, 0, 0, &arguments);

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
    printf("| %-30s %-20llu | \n", "Allocating Data Arrays (SIZE)", arguments.size);
    printf(" -----------------------------------------------------\n");

    struct DataArrays *dataArrays = newDataArrays(&arguments);

    printf("*-----------------------------------------------------*\n");
    printf("| %-30s %-20u | \n", "Populating Data Arrays (Seed)", 27491095);
    printf(" -----------------------------------------------------\n");

    initializeDataArrays(dataArrays);

    printf("*-----------------------------------------------------*\n");
    printf("| %-30s %-20llu | \n", "Copy data (SIZE)", arguments.size);
    printf(" -----------------------------------------------------\n");

    Start(timer);
    copyDataArrays(dataArrays, &arguments);
    Stop(timer);
    printf("| %-22s | %-27.20lf| \n","Time (Seconds)", Seconds(timer));
       
    double bandwidth_GB = (double)((double)(dataArrays->size)/(double)(1024*1024*256))/Seconds(timer);  //GB/s
    double bandwidth_MB = (double)((double)(dataArrays->size)/(double)(1024*256))/Seconds(timer); //MB/s

    printf("| %-22s | %-27.20lf| \n","BandWidth MB/s", bandwidth_MB);
    printf("| %-22s | %-27.20lf| \n","BandWidth GB/s", bandwidth_GB);

    __u64 missmatch = 0;
    missmatch = compareDataArrays(dataArrays);

    printf("*-----------------------------------------------------*\n");
    printf("| %-30s | %-20llu | \n", "Data Missmatched (#)", missmatch);
    printf(" -----------------------------------------------------\n");

       if(missmatch != 0)
    {
        printf("FAIL\n");
    }  else
    {
        printf("PASS\n");
    }

    printf("*-----------------------------------------------------*\n");
    printf("| %-30s %-20llu | \n", "Freeing Data Arrays (SIZE)", arguments.size);
    printf(" -----------------------------------------------------\n");

    freeDataArrays(dataArrays);
    free(timer);
    exit (0);
}





