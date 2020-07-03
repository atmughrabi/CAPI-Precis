#ifndef MEMCPY_TUTORIAL_H
#define MEMCPY_TUTORIAL_H

#include <stdint.h>
#include "config.h"

// ********************************************************************************************
// ***************                        DataStructure                          **************
// ********************************************************************************************

struct __attribute__((__packed__)) DataArraysTut
{
    uint64_t size;                      // 4-Bytes
    uint32_t *array_send;               // 8-Bytes pointer
    uint32_t *array_receive;             // 8-Bytes pointer
};

struct DataArraysTut *newDataArraysTut(struct Arguments *arguments);
void freeDataArraysTut(struct DataArraysTut *dataArraysTut);
void initializeDataArraysTut(struct DataArraysTut *dataArraysTut);
void copyDataArraysTut(struct DataArraysTut *dataArraysTut, struct Arguments *arguments);
uint64_t compareDataArraysTut(struct DataArraysTut *dataArraysTut);

#endif