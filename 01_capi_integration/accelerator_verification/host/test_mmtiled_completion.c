#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "capienv.h"

#define EXPECTED_LAUNCHES 8

struct ExpectedLaunch
{
    uint64_t start_i;
    uint64_t start_j;
    uint64_t completion_target;
};

static const struct ExpectedLaunch expected_launches[EXPECTED_LAUNCHES] = {
    {0, 0, 9},
    {0, 0, 9},
    {0, 3, 6},
    {0, 3, 6},
    {3, 0, 6},
    {3, 0, 6},
    {3, 3, 4},
    {3, 3, 4}
};

static struct cxl_afu_h fake_afu;
static struct WEDStructMM *fake_wed;
static uint64_t fake_afu_status;
static uint64_t fake_cu_status;
static uint64_t fake_config_2;
static uint64_t fake_config_3;
static uint64_t fake_completion;
static uint64_t fake_completion_target;
static struct ExpectedLaunch observed_launches[EXPECTED_LAUNCHES];
static uint32_t observed_launch_count;
static int fake_completion_ack;
static int fake_failure;

int cxl_mmio_install_sigbus_handler(void)
{
    return 0;
}

struct cxl_afu_h *cxl_afu_open_dev(char *path)
{
    if(!path)
    {
        errno = ENODEV;
        return NULL;
    }

    fake_afu.active = 1;
    return &fake_afu;
}

int cxl_afu_attach(struct cxl_afu_h *afu, uint64_t wed)
{
    if(!afu || !wed)
        return -1;

    fake_wed = (struct WEDStructMM *)wed;
    return 0;
}

void cxl_afu_free(struct cxl_afu_h *afu)
{
    if(afu)
        afu->active = 0;
}

int cxl_mmio_map(struct cxl_afu_h *afu, uint32_t flags)
{
    return (!afu || flags != CXL_MMIO_BIG_ENDIAN) ? -1 : 0;
}

int cxl_mmio_unmap(struct cxl_afu_h *afu)
{
    return afu ? 0 : -1;
}

int cxl_mmio_write64(struct cxl_afu_h *afu, uint64_t offset, uint64_t data)
{
    uint64_t start_i;
    uint64_t start_j;
    uint64_t rows;
    uint64_t columns;

    if(!afu)
        return -1;

    switch(offset)
    {
    case AFU_CONFIGURE:
        fake_afu_status = data;
        break;
    case CU_CONFIGURE:
        fake_completion = 0;
        fake_completion_ack = 0;
        fake_cu_status = data ? 1 : 0;
        break;
    case CU_CONFIGURE_2:
        fake_config_2 = data;
        break;
    case CU_CONFIGURE_3:
        fake_config_3 = data;
        break;
    case CU_CONFIGURE_4:
        if(!fake_wed)
            return -1;
        start_i = fake_config_2 >> 1;
        start_j = fake_config_3 >> 1;
        if(start_i >= fake_wed->size_n || start_j >= fake_wed->size_n)
            return -1;
        rows = fake_wed->size_tile < fake_wed->size_n - start_i ?
            fake_wed->size_tile : fake_wed->size_n - start_i;
        columns = fake_wed->size_tile < fake_wed->size_n - start_j ?
            fake_wed->size_tile : fake_wed->size_n - start_j;
        fake_completion_target = rows * columns;
        break;
    case CU_RETURN_DONE_ACK:
        if(!data)
            break;
        if(observed_launch_count >= EXPECTED_LAUNCHES)
        {
            fake_failure = 1;
            break;
        }
        observed_launches[observed_launch_count].start_i = fake_config_2 >> 1;
        observed_launches[observed_launch_count].start_j = fake_config_3 >> 1;
        observed_launches[observed_launch_count].completion_target = data;
        observed_launch_count++;
        fake_completion_ack = 1;
        fake_cu_status = 0;
        break;
    default:
        break;
    }

    return 0;
}

int cxl_mmio_read64(struct cxl_afu_h *afu, uint64_t offset, uint64_t *data)
{
    if(!afu || !data)
        return -1;

    switch(offset)
    {
    case AFU_STATUS:
        *data = fake_afu_status;
        break;
    case CU_STATUS:
        *data = fake_cu_status;
        break;
    case CU_RETURN:
    case CU_RETURN_2:
        *data = fake_completion;
        break;
    case CU_RETURN_DONE:
        if(fake_completion_ack)
            *data = 0;
        else
        {
            if(fake_completion < fake_completion_target)
                fake_completion++;
            *data = fake_completion;
        }
        break;
    case CU_RETURN_DONE_2:
    case ERROR_REG:
        *data = 0;
        break;
    default:
        *data = 0;
        break;
    }

    return 0;
}

static int verifyCompletionTargetHelper(void)
{
    uint64_t target;

    if(matrixTileCompletionTarget(5, 3, 0, 0, &target) || target != 9)
        return 1;
    if(matrixTileCompletionTarget(5, 3, 0, 3, &target) || target != 6)
        return 1;
    if(matrixTileCompletionTarget(5, 3, 3, 0, &target) || target != 6)
        return 1;
    if(matrixTileCompletionTarget(5, 3, 3, 3, &target) || target != 4)
        return 1;
    if(!matrixTileCompletionTarget(UINT64_MAX, UINT64_MAX, 0, 0, &target))
        return 1;
    if(!matrixTileCompletionTarget(5, 0, 0, 0, &target))
        return 1;
    if(!matrixTileCompletionTarget(5, 3, 5, 0, &target))
        return 1;

    return 0;
}

int main(void)
{
    struct Arguments arguments = {0};
    struct MatrixArrays matrix_arrays = {0};
    uint32_t matrix_storage = 1;

    if(verifyCompletionTargetHelper())
        return EXIT_FAILURE;

    if(setenv("CAPI_DEVICE", "/dev/cxl/mmtiled-test", 1) ||
       setenv("ACCELERATOR_START_TIMEOUT_MS", "100", 1) ||
       setenv("ACCELERATOR_STALL_TIMEOUT_MS", "100", 1) ||
       setenv("ACCELERATOR_RUN_TIMEOUT_MS", "500", 1) ||
       setenv("ACCELERATOR_CALL_TIMEOUT_MS", "100", 1) ||
       setenv("ACCELERATOR_POLL_INTERVAL_US", "1", 1))
        return EXIT_FAILURE;

    arguments.afu_config = 1;
    arguments.cu_config = 1;
    arguments.numThreads = 1;
    matrix_arrays.size_n = 5;
    matrix_arrays.size_tile = 3;
    matrix_arrays.A = &matrix_storage;
    matrix_arrays.B = &matrix_storage;
    matrix_arrays.C = &matrix_storage;

    matrixMultiplyTiledTransposed(&matrix_arrays, &arguments);

    if(fake_failure || observed_launch_count != EXPECTED_LAUNCHES)
        return EXIT_FAILURE;

    for(uint32_t launch = 0; launch < EXPECTED_LAUNCHES; launch++)
    {
        if(observed_launches[launch].start_i != expected_launches[launch].start_i ||
           observed_launches[launch].start_j != expected_launches[launch].start_j ||
           observed_launches[launch].completion_target !=
               expected_launches[launch].completion_target)
            return EXIT_FAILURE;
    }

    printf(
        "PASS mmtiled_completion targets=9,9,6,6,6,6,4,4 launches=%u\n",
        observed_launch_count);
    return EXIT_SUCCESS;
}
