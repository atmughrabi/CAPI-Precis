# Architecture

<p align="center">
  <img src="https://raw.githubusercontent.com/atmughrabi/CAPI-Precis/master/docs/fig/capi-precis-architecture.png" width="900" alt="CAPI-Precis accelerator architecture">
</p>

## Repository boundaries

| Path | Responsibility |
| --- | --- |
| `00_bench` | Host applications, OpenMP references, CAPI launch code, tests |
| `01_capi_integration/accelerator_rtl/afu_control` | PSL command, response, credit, tag, data, error, and completion control |
| `01_capi_integration/accelerator_rtl/cu_control` | Application compute units and their read/write engines |
| `01_capi_integration/accelerator_rtl/verification` | Bound RTL protocol and liveness monitor |
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
[Accelerator verification](https://github.com/atmughrabi/CAPI-Precis/wiki/Accelerator-Verification).

## Diagram blocks

| Block | Responsibility | Primary RTL |
| --- | --- | --- |
| Host application | Allocates aligned data, builds the WED, configures MMIO, waits, and checks results | `00_bench` |
| Power Service Layer (PSL) | Coherent command, response, data, MMIO, and job transport | Platform PSL / PSLSE |
| WED control | Fetches and decodes the 128-byte work descriptor | `afu_control/wed_control.sv` |
| MMIO | Receives AFU/CU configuration and publishes status, counters, errors, and completion | `afu_control/mmio.sv` |
| Command buffers | Separate WED, read, write, and prefetch request queues | `afu_control/fifo.sv` |
| Arbiter | Selects eligible command/data producers using fixed or round-robin policy | `afu_control/*priority_arbiter*.sv` |
| Credit control | Prevents requests from exceeding PSL credits | `afu_control/credit_control.sv` |
| Tag control | Allocates tags and preserves request metadata until response | `afu_control/tag_control.sv` |
| Command issue/restart | Issues PSL commands and replays restartable transactions | `afu_control/command_control.sv`, `restart_control.sv` |
| Read/write data | Routes cache-line data between PSL buffers and CUs | `afu_control/read_data_control.sv`, `write_data_control.sv` |
| Response/error | Classifies responses, reports protocol errors, and gathers statistics | `afu_control/response_control.sv`, `error_control.sv`, `response_statistics_control.sv` |
| Done/reset | Freezes final counters, requests CU reset, publishes completion, and waits for host ACK | `afu_control/done_control.sv`, `reset_control.sv` |
| Compute unit (CU) | Implements application-specific read, write, and compute engines | `accelerator_rtl/cu_control` |

## AFU-control detail

<p align="center">
  <img src="https://raw.githubusercontent.com/atmughrabi/CAPI-Precis/master/docs/fig/capi-precis-afu-control.png" width="520" alt="CAPI-Precis AFU-control architecture">
</p>

AFU control owns credit and tag management, command issue/restart, read and
write data, WED loading, MMIO, error reporting, reset, and response statistics.

## Implementation example

<p align="center">
  <img src="https://raw.githubusercontent.com/atmughrabi/CAPI-Precis/master/docs/fig/capi-precis-chip-planner.png" width="620" alt="CAPI-Precis FPGA chip planner">
</p>

## Simulation and hardware

Simulation replaces the platform PSL and libcxl with PSLSE while keeping the
same WED and MMIO contract. Hardware uses the platform libcxl implementation and
a matching flashed `.rbf` image. A host binary, CU selection, and FPGA image are
one compatibility unit.
