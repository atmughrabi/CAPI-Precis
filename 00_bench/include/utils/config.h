#ifndef CONFIG_H
#define CONFIG_H

#include <stdint.h>
#include "mt19937.h"

extern int numThreads;
extern mt19937state *mt19937var;

/* Used by main to communicate with parse_opt. */
struct Arguments
{
    uint64_t size;
    uint32_t numThreads;
    uint64_t afu_config;
    uint64_t afu_config_2;
    uint64_t cu_config;
    uint64_t cu_config_2;
    uint32_t cu_mode;
    uint64_t size_t; // added for tiled matrix multiply TILE size
};

#endif