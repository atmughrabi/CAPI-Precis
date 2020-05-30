// -----------------------------------------------------------------------------
//
//      "CAPIPrecis"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Abdullah Mughrabi
// Email  : atmughra@ncsu.edu||atmughrabi@gmail.com
// File   : mmtiled.c
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

#include "timer.h"
#include "myMalloc.h"
#include "config.h"

#include "mmtiled.h"

struct MatrixArrays *newMatrixArrays(struct Arguments *arguments)
{

    struct MatrixArrays *matrixArrays = (struct MatrixArrays *) my_malloc(sizeof(struct MatrixArrays));

    matrixArrays->size_n = arguments->size;
    matrixArrays->size_t = arguments->size_t;

    matrixArrays->A = (uint32_t *) my_malloc(sizeof(uint32_t) * (matrixArrays->size_n) * (matrixArrays->size_n));
    matrixArrays->B = (uint32_t *) my_malloc(sizeof(uint32_t) * (matrixArrays->size_n) * (matrixArrays->size_n));
    matrixArrays->C = (uint32_t *) my_malloc(sizeof(uint32_t) * (matrixArrays->size_n) * (matrixArrays->size_n));

    return matrixArrays;

}

void freeMatrixArrays(struct MatrixArrays *matrixArrays)
{

    if(matrixArrays)
    {
        if(matrixArrays->A)
            free(matrixArrays->A);
        if(matrixArrays->B)
            free(matrixArrays->B);
        if(matrixArrays->C)
            free(matrixArrays->C);
        free(matrixArrays);
    }

}
void initializeMatrixArrays(struct MatrixArrays *matrixArrays)
{

    uint64_t i;
    uint64_t j;

    #pragma omp parallel for
    for(i = 0; i < matrixArrays->size_n; i++)
    {
        for(j = 0; j < matrixArrays->size_n; j++)
        {
            matrixArrays->A[(i * matrixArrays->size_n) + j] = generateRandInt(mt19937var) % 512;
            matrixArrays->B[(i * matrixArrays->size_n) + j] = generateRandInt(mt19937var) % 512;
            matrixArrays->C[(i * matrixArrays->size_n) + j] = 0;
        }
    }

}

uint64_t compareMatrixArrays(struct MatrixArrays *matrixArrays1, struct MatrixArrays *matrixArrays2)
{
    uint64_t missmatch = 0;
    uint64_t i;
    uint64_t j;

    if(matrixArrays1->size_n != matrixArrays2->size_n)
        return 1;

    #pragma omp parallel for shared(matrixArrays1,matrixArrays2) reduction(+: missmatch)
    for(i = 0; i < matrixArrays1->size_n; i++)
    {
        for(j = 0; j < matrixArrays1->size_n; j++)
        {

            if(     matrixArrays1->A[(i * matrixArrays1->size_n) + j] != matrixArrays2->A[(i * matrixArrays2->size_n) + j]
                    ||  matrixArrays1->B[(i * matrixArrays1->size_n) + j] != matrixArrays2->B[(i * matrixArrays2->size_n) + j]
                    ||  matrixArrays1->C[(i * matrixArrays1->size_n) + j] != matrixArrays2->C[(i * matrixArrays2->size_n) + j])
            {
                // printf("[%llu] %u != %u\n", i, dataArrays->array_receive[i], dataArrays->array_send[i] );
                missmatch ++;
            }
        }
    }

    return missmatch;
}
void matrixMultiplyStandard(struct MatrixArrays *matrixArrays, struct Arguments *arguments);
void matrixMultiplyTiled(struct MatrixArrays *matrixArrays, struct Arguments *arguments);