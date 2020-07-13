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
    matrixArrays->size_tile = arguments->cu_config_2;

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

    #pragma omp parallel for private(j)
    for(i = 0; i < matrixArrays->size_n; i++)
    {
        for(j = 0; j < matrixArrays->size_n; j++)
        {
            // matrixArrays->A[(i * matrixArrays->size_n) + j] = generateRandInt(mt19937var) % 512;
            // matrixArrays->B[(i * matrixArrays->size_n) + j] = generateRandInt(mt19937var) % 512;
            matrixArrays->A[(i * matrixArrays->size_n) + j] = (i * matrixArrays->size_n) + j;
            matrixArrays->B[(i * matrixArrays->size_n) + j] = (i * matrixArrays->size_n) + j;
            matrixArrays->C[(i * matrixArrays->size_n) + j] = (i * matrixArrays->size_n) + j;
        }
    }

}

void resetMatrixArrays(struct MatrixArrays *matrixArrays)
{

    uint64_t i;
    uint64_t j;

    #pragma omp parallel for private(j)
    for(i = 0; i < matrixArrays->size_n; i++)
    {
        for(j = 0; j < matrixArrays->size_n; j++)
        {
            matrixArrays->C[(i * matrixArrays->size_n) + j] = (i * matrixArrays->size_n) + j;
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

    #pragma omp parallel for shared(matrixArrays1,matrixArrays2) private(j) reduction(+: missmatch)
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

uint64_t checksumMatrixArrays(struct MatrixArrays *matrixArrays)
{
    uint64_t checksum = 0;
    uint64_t i;
    uint64_t j;

    #pragma omp parallel for shared(matrixArrays) private(j) reduction(+: checksum)
    for(i = 0; i < matrixArrays->size_n; i++)
    {
        for(j = 0; j < matrixArrays->size_n; j++)
        {
            checksum += matrixArrays->C[(i * matrixArrays->size_n) + j];
        }
    }

    return checksum;
}

void matrixTranspose(struct MatrixArrays *matrixArrays)
{

    uint64_t i;
    uint64_t j;
    uint32_t temp;

    for(i = 0; i < matrixArrays->size_n; i++)
    {
        #pragma omp parallel for private(temp)
        for(j = i + 1; j < matrixArrays->size_n; j++)
        {
            temp = matrixArrays->B[(i * matrixArrays->size_n) + j];
            matrixArrays->B[(i * matrixArrays->size_n) + j] = matrixArrays->B[(j * matrixArrays->size_n) + i];
            matrixArrays->B[(j * matrixArrays->size_n) + i] = temp;
        }
    }

}

void matrixMultiplyStandard(struct MatrixArrays *matrixArrays)
{

    uint64_t i;
    uint64_t j;
    uint64_t k;
    uint32_t sum;

    #pragma omp parallel for private(j,k,sum) schedule(dynamic)
    for(i = 0; i < matrixArrays->size_n; i++)
    {
        for(j = 0; j < matrixArrays->size_n; j++)
        {
            sum = 0;
            for(k = 0; k < matrixArrays->size_n; k++)
            {
                sum += matrixArrays->A[(i * matrixArrays->size_n) + k] * matrixArrays->B[(k * matrixArrays->size_n) + j];
            }
            matrixArrays->C[(i * matrixArrays->size_n) + j] = sum;
        }
    }
}

void matrixMultiplyStandardTransposed(struct MatrixArrays *matrixArrays)
{

    uint64_t i;
    uint64_t j;
    uint64_t k;
    uint32_t sum;

    #pragma omp parallel for private(j,k,sum) schedule(dynamic)
    for(i = 0; i < matrixArrays->size_n; i++)
    {
        for(j = 0; j < matrixArrays->size_n; j++)
        {
            sum = 0;
            for(k = 0; k < matrixArrays->size_n; k++)
            {
                sum += matrixArrays->A[(i * matrixArrays->size_n) + k] * matrixArrays->B[(j * matrixArrays->size_n) + k];
            }
            matrixArrays->C[(i * matrixArrays->size_n) + j] = sum;
        }
    }
}

void matrixMultiplyTiled(struct MatrixArrays *matrixArrays)
{

    uint64_t i;
    uint64_t j;
    uint64_t k;
    uint64_t ii;
    uint64_t jj;
    uint64_t kk;
    uint32_t sum;

    #pragma omp parallel for private(j,k,ii,jj,kk,sum) schedule(dynamic)
    for(i = 0; i < matrixArrays->size_n; i += matrixArrays->size_tile)
    {
        for(j = 0; j < matrixArrays->size_n; j += matrixArrays->size_tile)
        {
            for(k = 0; k < matrixArrays->size_n; k += matrixArrays->size_tile)
            {
                for (ii = i; ii < MIN(i + matrixArrays->size_tile,  matrixArrays->size_n); ii++)
                {
                    for (jj = j; jj < MIN(j + matrixArrays->size_tile,  matrixArrays->size_n); jj++)
                    {
                        sum = 0;
                        //#pragma omp parallel for reduction(+:sum)
                        for (kk = k; kk < MIN(k + matrixArrays->size_tile,  matrixArrays->size_n); kk++)
                        {
                            sum += matrixArrays->A[(ii * matrixArrays->size_n) + kk] * matrixArrays->B[(kk * matrixArrays->size_n) + jj];
                        }
                        matrixArrays->C[(ii * matrixArrays->size_n) + jj] += sum;
                    }
                }
            }
        }
    }

}

void matrixMultiplyTiledTransposed(struct MatrixArrays *matrixArrays, struct Arguments *arguments)
{

    uint64_t i;
    uint64_t j;
    uint64_t k;
    uint64_t ii;
    uint64_t jj;
    // uint64_t kk;
    uint32_t sum;

    // #pragma omp parallel for private(j,k,ii,jj,kk,sum) schedule(dynamic)
    for(i = 0; i < matrixArrays->size_n; i += matrixArrays->size_tile)
    {
        for(j = 0; j < matrixArrays->size_n; j += matrixArrays->size_tile)
        {
            for(k = 0; k < matrixArrays->size_n; k += matrixArrays->size_tile)
            {
                for (ii = i; ii < MIN(i + matrixArrays->size_tile,  matrixArrays->size_n); ii++)
                {
                    for (jj = j; jj < MIN(j + matrixArrays->size_tile,  matrixArrays->size_n); jj++)
                    {
                        sum = 0;
                        //#pragma omp parallel for reduction(+:sum)
                        // for (kk = k; kk < MIN(k + matrixArrays->size_tile,  matrixArrays->size_n); kk++)
                        // {
                        //     sum += matrixArrays->A[(ii * matrixArrays->size_n) + kk] * matrixArrays->B[(jj * matrixArrays->size_n) + kk];
                        // }
                        matrixArrays->C[(ii * matrixArrays->size_n) + jj] += sum;
                        printf("i:%lu j:%lu  C:%u \n",ii,jj, matrixArrays->C[(ii * matrixArrays->size_n) + jj]);
                    }
                }

                        break;
            }
                    break;
        }
                break;
    }

}