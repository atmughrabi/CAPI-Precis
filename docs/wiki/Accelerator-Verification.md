# Accelerator verification

CAPI-Precis has two complementary verification layers:

- `00_bench/src/capi_utils/accelerator_verification.c` bounds host/libcxl
  execution.
- `01_capi_integration/accelerator_rtl/verification/accelerator_verification.sv`
  is bound to `cached_afu` during simulation and verifies the RTL protocol.

![CAPI-Precis accelerator verification](https://raw.githubusercontent.com/atmughrabi/CAPI-Precis/master/docs/fig/accelerator-verification-f01-host-liveness.svg)

## Contract

1. Bound each libcxl open, attach, map, MMIO, unmap, and free call with a
   process watchdog. Install the MMIO fault handler before mapping. A blocked or
   failed call terminates the process with a non-zero status.
2. Re-issue the idempotent AFU or CU configuration pulse until accepted,
   require AFU status to echo the primary configuration, and bound the poll.
3. During execution, read the running return counters on every poll. Counter
   movement refreshes the stall deadline.
4. Treat a non-zero error register as a failed run.
5. After completion, acknowledge `CU_RETURN_DONE` and wait until both completion
   registers and `CU_STATUS` clear before launching another job.

Tutorial jobs that expose only a binary completion flag use the absolute run
deadline; stall detection requires a real progress counter.

Phase deadlines are evaluated between libcxl calls. The call watchdog is the
hard bound while one synchronous libcxl operation is in progress.

## Runtime controls

| Variable | Default | Purpose |
| --- | ---: | --- |
| `ACCELERATOR_START_TIMEOUT_MS` | `10000` | AFU/CU configuration and reset-drain deadline |
| `ACCELERATOR_STALL_TIMEOUT_MS` | `60000` | Maximum time without counter movement |
| `ACCELERATOR_RUN_TIMEOUT_MS` | `1800000` | Absolute execution deadline |
| `ACCELERATOR_CALL_TIMEOUT_MS` | `30000` | Maximum duration of one libcxl call |
| `ACCELERATOR_POLL_INTERVAL_US` | `1000` | Delay between MMIO polls |

Values must be positive decimal integers. Timeouts are limited to 24 hours,
polling is limited to one second, and the polling interval cannot exceed a
configured timeout. Values are loaded on first accelerator use; invalid values
fail before a job is started.

The first 100 polls spin without sleeping; later polls use the configured
interval. Record a non-default interval with benchmark results.

## RTL verification

The RTL monitor checks:

- AFU and CU configuration acceptance within bounded cycle counts;
- unknown values on the active control/status path;
- monotonic CU progress and bounded no-progress intervals;
- `cu_done` causing reset and completion publication;
- completion remaining stable until a valid acknowledgement;
- completion and `CU_STATUS` clearing after acknowledgement;
- any asserted RTL error register.

The `memcpy`, `memcpy-tutorial`, and `mmtiled` ModelSim scripts compile and bind
the monitor automatically. The older direct `helloAFU` and `tutorial` examples
do not use the shared `cached_afu` architecture and are outside this bind. A
violated RTL contract terminates simulation with `$fatal`. The verification
wave group is defined in `watch_accelerator_verification.do`.

For first-platform bring-up, add `+VERIF_FATAL=0` to the `vsim` command to
record `$error`, `failure_count`, and wave evidence without terminating at the
first violation.

`cover_mask[6:0]` records AFU configuration, CU configuration, progress,
`cu_done`, completion publication, acknowledgement, and reset-clear witnesses.

## Local verification

```console
make rtl-verification
make verify
```

`make rtl-verification` validates the ordered Phase 0 manifests, elaborates the
real `cached_afu`, AFU-control, and `cu_control` RTL across the `memcpy`,
`memcpy-tutorial`, and `mmtiled` variants without the compatibility CU stub,
then runs positive and negative protocol tests with Verilator. Implicit nets
and pin mismatches fail the gate. `make verify` includes that RTL evidence
alongside host and benchmark checks. Local verification skips the RTL stage
when Verilator 5 is unavailable; GitHub Actions sets
`RTL_VERIFICATION_REQUIRED=1`.
