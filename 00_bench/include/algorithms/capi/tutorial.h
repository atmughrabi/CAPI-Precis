#ifndef TUTORIAL_H
#define TUTORIAL_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdint.h>

typedef struct //base
{
    uint64_t size;//8
    void *stripe1;//8
    void *stripe2;//8
    void *parity; //8
    uint64_t done;// base + 32bytes
} parity_request;


int tutorial_main_call(int argc, char *argv[]);

#endif