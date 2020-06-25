#ifndef MMTILED_H
#define MMTILED_H

#include <stdint.h>
#include "config.h"

// ********************************************************************************************
// ***************                        DataStructure                          **************
// ********************************************************************************************

struct __attribute__((__packed__)) MatrixArrays
{
    uint64_t size_n; // nxn matrix size
    uint64_t size_tile; // tile size
    uint32_t *A;
    uint32_t *B;
    uint32_t *C;            // 8-Bytes pointer
};

#define MIN(a,b) (((a)<(b))?(a):(b))
#define IS_ZERO(a) (((a==0))?(1):(a))

struct MatrixArrays *newMatrixArrays(struct Arguments *arguments);
void freeMatrixArrays(struct MatrixArrays *matrixArrays);
void initializeMatrixArrays(struct MatrixArrays *matrixArrays);
void resetMatrixArrays(struct MatrixArrays *matrixArrays);
uint64_t compareMatrixArrays(struct MatrixArrays *matrixArrays1, struct MatrixArrays *matrixArrays2);
uint64_t checksumMatrixArrays(struct MatrixArrays *matrixArrays);
void matrixTranspose(struct MatrixArrays *matrixArrays);
void matrixMultiplyStandard(struct MatrixArrays *matrixArrays);
void matrixMultiplyStandardTransposed(struct MatrixArrays *matrixArrays);
void matrixMultiplyTiled(struct MatrixArrays *matrixArrays);
void matrixMultiplyTiledTransposed(struct MatrixArrays *matrixArrays, struct Arguments *arguments);

#endif