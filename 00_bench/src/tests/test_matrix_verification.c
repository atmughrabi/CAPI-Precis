#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "config.h"
#include "mmtiled.h"

int main(void)
{
    struct Arguments arguments = {0};
    struct MatrixArrays *matrix_arrays;
    uint64_t reference;
    uint32_t mismatches = 0;

    arguments.size = 16;
    arguments.cu_config_2 = 4;

    matrix_arrays = newMatrixArrays(&arguments);
    initializeMatrixArrays(matrix_arrays);

    matrixMultiplyStandard(matrix_arrays);
    reference = checksumMatrixArrays(matrix_arrays);

    resetMatrixArrays(matrix_arrays);
    matrixMultiplyTiled(matrix_arrays);
    mismatches += checksumMatrixArrays(matrix_arrays) != reference;

    resetMatrixArrays(matrix_arrays);
    matrixTranspose(matrix_arrays);
    matrixMultiplyStandardTransposed(matrix_arrays);
    mismatches += checksumMatrixArrays(matrix_arrays) != reference;

    resetMatrixArrays(matrix_arrays);
    matrixMultiplyTiledTransposed(matrix_arrays, &arguments);
    mismatches += checksumMatrixArrays(matrix_arrays) != reference;

    freeMatrixArrays(matrix_arrays);

    if(mismatches)
        return EXIT_FAILURE;

    printf("PASS matrix_verification\n");
    return EXIT_SUCCESS;
}
