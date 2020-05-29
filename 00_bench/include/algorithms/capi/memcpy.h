#ifndef ALGORITHM_H
#define ALGORITHM_H

#include <stdint.h>
#include "config.h"

// ********************************************************************************************
// ***************                        DataStructure                          **************
// ********************************************************************************************

struct __attribute__((__packed__)) DataArrays
{
    uint64_t size;                      // 4-Bytes
    uint32_t *array_send;               // 8-Bytes pointer
    uint32_t *array_receive;             // 8-Bytes pointer
}; 


struct DataArrays *newDataArrays(struct Arguments *arguments);
void freeDataArrays(struct DataArrays *dataArrays);
void initializeDataArrays(struct DataArrays *dataArrays);
uint64_t compareDataArrays(struct DataArrays *dataArrays);
void copyDataArrays(struct DataArrays *dataArrays, struct Arguments *arguments);

#endif