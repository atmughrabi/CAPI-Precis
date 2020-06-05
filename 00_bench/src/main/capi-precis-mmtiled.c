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
#include "mmtiled.h"

int numThreads;
mt19937state *mt19937var;

const char *argp_program_version =
    "CAPIPrecis 1.0";
const char *argp_program_bug_address =
    "<atmughra@ncsu.edu>\n<atmughra@ncsu.edu>";
/* Program documentation. */
static char doc[] =
    "CAPIPrecis is an open source CAPI enabled FPGA processing framework, it is designed to abstract the PSL layer for a faster development cycles";

/* A description of the arguments we accept. */
static char args_doc[] = "-s <size> -n [num threads] -a [afu config] -c [cu config]  ";

/* The options we understand. */
static struct argp_option options[] =
{
    {
        "num-threads",           'n', "[DEFAULT:MAX]",      0,
        "\nDefault: MAX number of threads the system has"
    },
    {
        "size",                  's', "SIZE:512",      0,
        "\n[Matrix Size] n of n*n Matrix"
    },
    {
        "afu-config",            'a', "[DEFAULT:0x1]",      0,
        "\nAFU-Control buffers(read/write/prefetcher) arbitration 0x01 round robin 0x10 fixed priority"
    },
    {
        "afu-config2",           'b', "[DEFAULT:0x0]",      0,
        "\nAFU-Control MMIO register for extensible features"
    },
    {
        "cu-config",             'c', "[DEFAULT:0x01]",      0,
        "\nCU configurations for requests cached/non cached/prefetcher active or not check README for more explanation"
    },
    {
        "cu-config2",            'd', "[DEFAULT:0x00]",      0,
        "\n[Tile size] CU-Control MMIO register for extensible features"
    },
    {
        "cu-mode",               'm', "[DEFAULT:0x03]",      0,
        "\nCU configurations use Tiled or non Tiled iteration"
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
    case 'b':
        arguments->afu_config_2 = strtoll(arg, &eptr, 0);
        break;
    case 'c':
        arguments->cu_config = strtoll(arg, &eptr, 0);
        break;
    case 'd':
        arguments->cu_config_2 = strtoll(arg, &eptr, 0);
        break;
    case 'm':
        arguments->cu_mode = atoi(arg);
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

    struct Arguments arguments = {0};

    arguments.numThreads = omp_get_max_threads();
    arguments.size = 512;
    arguments.afu_config = 0x01;
    arguments.cu_config  = 0x01;
    arguments.cu_mode    = 0x01;
    arguments.cu_config_2  = 128;

    argp_parse (&argp, argc, argv, 0, 0, &arguments);

    struct Timer *timer = (struct Timer *) my_malloc(sizeof(struct Timer));
    numThreads = arguments.numThreads;
    mt19937var = (mt19937state *) my_malloc(sizeof(mt19937state));
    initializeMersenneState (mt19937var, 27491095);
    uint64_t checksum = 0;

    omp_set_nested(1);
    omp_set_num_threads(numThreads);

    printf("*-----------------------------------------------------*\n");
    printf("| %-20s %-30u | \n", "Number of Threads :", numThreads);
    printf(" -----------------------------------------------------\n");

    double size_GB = (double)((double)(arguments.size* arguments.size) / (double)(1024 * 1024 * 256)); //GB/s
    double size_MB = (double)((double)(arguments.size* arguments.size) / (double)(1024 * 256)); //MB/s

    printf("*-----------------------------------------------------*\n");
    printf("| %-35s %-15lu | \n", " Matrix Arrays (SIZE Elements) |", arguments.size*arguments.size);
    printf("| %-35s %-15lf | \n", "               (SIZE MB)       |", size_MB);
    printf("| %-35s %-15lf | \n", "               (SIZE GB)       |", size_GB);
    printf(" -----------------------------------------------------\n");

    struct MatrixArrays *matrixArrays = newMatrixArrays(&arguments);

    printf("*-----------------------------------------------------*\n");
    printf("| %-35s %-15u | \n", "Populating Matrix Arrays (Seed)", 27491095);
    printf(" -----------------------------------------------------\n");

    initializeMatrixArrays(matrixArrays);

    printf("*-----------------------------------------------------*\n");
    printf("| %-35s %-15lu | \n", "Multiply Matrix C=A*B (TILE SIZE)", arguments.cu_config_2);
    printf(" -----------------------------------------------------\n");

    Start(timer);
    matrixMultiplyStandard(matrixArrays);
    Stop(timer);

    checksum = 0;
    checksum = checksumMatrixArrays(matrixArrays);
    printf("*-----------------------------------------------------*\n");
    printf("| %-30s | %-18lu | \n", "Standard MM checksum (#)", checksum);
    printf(" -----------------------------------------------------\n");

    double bandwidth_GB = size_GB / Seconds(timer); //GB/s
    double bandwidth_MB = size_MB / Seconds(timer); //MB/s
    printf("| %-22s | %-27.20lf| \n", "Time (Seconds)", Seconds(timer));
    printf("| %-22s | %-27.20lf| \n", "BandWidth MB/s", bandwidth_MB);
    printf("| %-22s | %-27.20lf| \n", "BandWidth GB/s", bandwidth_GB);


    Start(timer);
    matrixMultiplyTiled(matrixArrays);
    Stop(timer);

    checksum = 0;
    checksum = checksumMatrixArrays(matrixArrays);
    printf("*-----------------------------------------------------*\n");
    printf("| %-30s | %-18lu | \n", "Tiled MM checksum (#)", checksum);
    printf(" -----------------------------------------------------\n");

    bandwidth_GB = size_GB / Seconds(timer); //GB/s
    bandwidth_MB = size_MB / Seconds(timer); //MB/s
    printf("| %-22s | %-27.20lf| \n", "Time (Seconds)", Seconds(timer));
    printf("| %-22s | %-27.20lf| \n", "BandWidth MB/s", bandwidth_MB);
    printf("| %-22s | %-27.20lf| \n", "BandWidth GB/s", bandwidth_GB);
    printf("*-----------------------------------------------------*\n");

    Start(timer);
    matrixTranspose(matrixArrays);
    Stop(timer);

    printf("*-----------------------------------------------------*\n");
    printf("| %-35s %-15lu | \n", "Transpose Matrix B (SIZE)", arguments.size*arguments.size);
    printf(" -----------------------------------------------------\n");
    printf("| %-22s | %-27.20lf| \n", " Time (Seconds)", Seconds(timer));
    printf(" -----------------------------------------------------\n");

    Start(timer);
    matrixMultiplyStandardTransposed(matrixArrays);
    Stop(timer);

    checksum = 0;
    checksum = checksumMatrixArrays(matrixArrays);
    printf("*-----------------------------------------------------*\n");
    printf("| %-30s | %-18lu | \n", "StandardTrans MM checksum (#)", checksum);
    printf(" -----------------------------------------------------\n");

    bandwidth_GB = size_GB / Seconds(timer); //GB/s
    bandwidth_MB = size_MB / Seconds(timer); //MB/s
    printf("| %-22s | %-27.20lf| \n", "Time (Seconds)", Seconds(timer));
    printf("| %-22s | %-27.20lf| \n", "BandWidth MB/s", bandwidth_MB);
    printf("| %-22s | %-27.20lf| \n", "BandWidth GB/s", bandwidth_GB);


    Start(timer);
    matrixMultiplyTiledTransposed(matrixArrays);
    Stop(timer);

    checksum = 0;
    checksum = checksumMatrixArrays(matrixArrays);
    printf("*-----------------------------------------------------*\n");
    printf("| %-30s | %-18lu | \n", "TiledTrans MM checksum (#)", checksum);
    printf(" -----------------------------------------------------\n");

    bandwidth_GB = size_GB / Seconds(timer); //GB/s
    bandwidth_MB = size_MB / Seconds(timer); //MB/s
    printf("| %-22s | %-27.20lf| \n", "Time (Seconds)", Seconds(timer));
    printf("| %-22s | %-27.20lf| \n", "BandWidth MB/s", bandwidth_MB);
    printf("| %-22s | %-27.20lf| \n", "BandWidth GB/s", bandwidth_GB);

    printf("*-----------------------------------------------------*\n");
    printf("| %-30s %-20lu | \n", "Freeing Data Arrays (SIZE)", arguments.size);
    printf(" -----------------------------------------------------\n");

    freeMatrixArrays(matrixArrays);
    free(timer);
    exit (0);
}





