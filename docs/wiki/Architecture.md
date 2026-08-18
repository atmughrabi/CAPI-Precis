# Architecture

## Repository boundaries

| Path | Responsibility |
| --- | --- |
| `00_bench` | Host applications, OpenMP references, CAPI launch code, tests |
| `01_capi_integration/accelerator_rtl/afu_control` | PSL command, response, credit, tag, data, error, and completion control |
| `01_capi_integration/accelerator_rtl/cu_control` | Application compute units and their read/write engines |
| `01_capi_integration/accelerator_sim` | ModelSim design and PSLSE endpoint configuration |
| `01_capi_integration/accelerator_synth` | Quartus project generation and implementation |
| `01_capi_integration/accelerator_bin` | Platform images and implementation reports |

## Runtime path

1. The host allocates cache-line-aligned data and builds a 128-byte WED.
2. libcxl attaches the WED to the selected AFU and maps big-endian MMIO.
3. AFU configuration sets arbitration, credits, caching, and prefetch behavior.
4. CU configuration selects engines, thread/CU count, and workload-specific
   arguments.
5. CU commands enter AFU-control buffers and are issued to the PSL.
6. Responses update running counters, error state, and the final completion
   registers.
7. The host acknowledges completion, waits for CU reset, and compares output.

The bounded host protocol is defined in
[Accelerator verification](Accelerator-Verification.md).

## Simulation and hardware

Simulation replaces the platform PSL and libcxl with PSLSE while keeping the
same WED and MMIO contract. Hardware uses the platform libcxl implementation and
a matching flashed `.rbf` image. A host binary, CU selection, and FPGA image are
one compatibility unit.
