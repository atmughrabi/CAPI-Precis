# Accelerator verification

`00_bench/src/capi_utils/accelerator_verification.c` is the host liveness source
of truth. It bounds every AFU phase and distinguishes a device error, a stalled
job, and an absolute runtime timeout.

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

## Local verification

```console
make verify
```

The target exercises configuration parsing, progress refresh, blocked-call
watchdog expiry, stall detection, absolute timeout, mocked libcxl setup/MMIO and
completion reset, CPU matrix equivalence, integration compilation, and the
existing memory-copy test.
