# Deployment runbook

## Before launch

```console
git submodule update --init --recursive
make verify
```

Confirm the flashed image matches the selected CU algorithm and set timeout
overrides only when a measured healthy run requires them.

## Launch

Use the existing simulator or FPGA target:

```console
make run-capi-sim-verbose2
make run-capi-fpga-verbose2
```

Simulation targets default to 5-minute start/call, 15-minute stall, and 2-hour
run limits. Override the `SIM_ACCELERATOR_*` make variables when measured
ModelSim latency requires different bounds.

## Failure evidence

Preserve the single `Accelerator verification failed` line, the AFU/CU status,
error register, progress counters, target count, selected image name, command
line, and simulator `debug.log` when applicable.

| Reason | First check |
| --- | --- |
| `device-error` | Decode the error register and inspect WED/MMIO addresses |
| `stalled` | Compare running counters and PSL response statistics |
| `timeout` | Confirm workload size, image/CU match, and configured deadline |
| MMIO failure | Check device node, attach state, permissions, and PSLSE health |

Do not restart an accelerator job until the previous completion acknowledgement
has drained and `CU_STATUS` is clear.
