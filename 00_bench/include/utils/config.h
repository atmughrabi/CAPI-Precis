#ifndef CONFIG_H
#define CONFIG_H

#include <linux/types.h>
#include "mt19937.h"

extern int numThreads;
extern mt19937state *mt19937var;

/* Used by main to communicate with parse_opt. */
struct Arguments
{
    __u32 size;
    __u32 numThreads;
};

#endif