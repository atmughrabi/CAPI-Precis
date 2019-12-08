#ifndef ALGORITHM_H
#define ALGORITHM_H

#include <linux/types.h>
#include "config.h"

// ********************************************************************************************
// ***************                        DataStructure                          **************
// ********************************************************************************************

struct __attribute__((__packed__)) DataArrays
{
    __u64 size;                      // 4-Bytes
    __u32 *array_send;               // 8-Bytes pointer
    __u32 *array_receive;             // 8-Bytes pointer
}; 


struct DataArrays *newDataArrays(struct Arguments *arguments);
void freeDataArrays(struct DataArrays *dataArrays);
void initializeDataArrays(struct DataArrays *dataArrays);
__u64 compareDataArrays(struct DataArrays *dataArrays);
void copyDataArrays(struct DataArrays *dataArrays, struct Arguments *arguments);

#endif