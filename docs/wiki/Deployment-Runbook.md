# Deployment runbook

## Before launch

```console
git submodule sync --recursive
git submodule update --init --recursive
sudo apt-get install tcl verilator
verilator --version  # must report version 5 or newer
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

## Workload options

| Option | Purpose |
| --- | --- |
| `-a`, `--afu-config` | AFU arbitration and buffer configuration |
| `-b`, `--afu-config2` | Extensible secondary AFU configuration |
| `-c`, `--cu-config` | Compute-unit cache/prefetch configuration |
| `-d`, `--cu-config2` | Workload-specific secondary CU configuration |
| `-m`, `--cu-mode` | Read/write engine mask: 0 disabled, 1 write, 2 read, 3 both |
| `-n`, `--num-threads` | Host thread count |
| `-s`, `--size` | Workload element count |

Use the selected binary's `--help` output as the exact parser reference.
