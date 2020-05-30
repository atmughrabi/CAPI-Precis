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
    uint64_t size_t; // tile size
    uint32_t *A;
    uint32_t *B;
    uint32_t *C;            // 8-Bytes pointer
};


struct MatrixArrays *newMatrixArrays(struct Arguments *arguments);
void freeMatrixArrays(struct MatrixArrays *matrixArrays);
void initializeMatrixArrays(struct MatrixArrays *matrixArrays);
uint64_t compareMatrixArrays(struct MatrixArrays *matrixArrays1, struct MatrixArrays *matrixArrays2);
void matrixMultiplyStandard(struct MatrixArrays *matrixArrays, struct Arguments *arguments);
void matrixMultiplyTiled(struct MatrixArrays *matrixArrays, struct Arguments *arguments);

#endif