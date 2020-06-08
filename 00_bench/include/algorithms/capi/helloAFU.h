#ifndef HELLOAFU_H
#define HELLOAFU_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdint.h>

typedef struct
{
    uint64_t size;
    void *stripe1;
    void *stripe2;
    void *parity;
    uint64_t done;
} parity_request;


int my_main_call(int argc, char *argv[]);

#endif