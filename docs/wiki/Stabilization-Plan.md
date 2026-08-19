# Stabilization plan

## Scope and acceptance

The stabilization boundary is the CAPI-Precis host/AFU protocol. A release is
acceptable when host-only tests pass, AFU waits are bounded, completion reset is
observed before reuse, errors return non-zero, and the simulator or FPGA run
produces matching output data.

## Failure model

| Boundary | Previous risk | Control | Acceptance evidence |
| --- | --- | --- | --- |
| Device open | Null handle passed onward | Correct handle validation | Missing device fails immediately |
| WED attach/MMIO map | Return values ignored | Checked calls and cleanup | Injected setup failure returns non-zero |
| libcxl call | PSLSE or detach could block inside one synchronous call | Monotonic process watchdog | Deliberately blocked call terminates |
| AFU/CU configuration | Infinite repeated writes | Single write plus bounded status poll | Timeout test and successful status transition |
| CU execution | Infinite busy poll | Progress-aware stall and absolute deadlines | Counter-progress and frozen-counter tests |
| Error register | Error printed but run continued | Error acknowledgement and failed process | Non-zero exit with register snapshot |
| Completion reuse | Next CU started before reset drain | ACK plus completion/status clear verification | Repeated-job simulation or hardware trace |
| Regression target | Build failures hidden by `grep` | Direct test status propagation | Deliberate compile or data mismatch fails `make test` |
| Matrix verification | Output buffer started non-zero and one CPU path was a stub | Zeroed output and complete tiled-transposed reference | All CPU matrix checksums match |
| Matrix completion | Host waited for tile area while RTL reports matrix size | Match `cu_stop` to `size_n` | Healthy matrix CU completion does not false-stall |
| RTL protocol | Host evidence could not detect an internal publication/reset violation | Bind bounded monitor to `cached_afu` | Verilator pass/negative tests and ModelSim bind |

## Delivery stages

1. **Host baseline:** run `make accelerator-verification` and `make test` on a
   standard Linux host.
2. **Compile boundary:** compile CAPI host sources against the selected libcxl
   headers for both simulator and hardware flags.
3. **Simulator liveness:** run a small memory-copy workload, then repeated jobs,
   with short diagnostic deadlines.
4. **Hardware canary:** run one healthy workload per CU image and preserve
   status/progress evidence.
5. **Stress:** sweep sizes and repeated launches, including a duration longer
   than the stall window while counters continue to move.
6. **Release:** record the image, commit, timeout overrides, platform, workload,
   result checksum, and elapsed time.

## Verification matrix

| Layer | Required checks |
| --- | --- |
| Host unit | Defaults, overrides, invalid values, progress, stall, timeout, completion, device error |
| OpenMP | Existing memory-copy correctness test |
| Simulator | Setup, configuration, progress, completion ACK/reset, output comparison |
| RTL monitor | Configuration acceptance, monotonic progress, done publication, ACK stability, reset clear, error register |
| FPGA | Same protocol checks plus image identity and device error register |
| Repetition | Back-to-back launches without stale completion or status |

## Rollout and rollback

Deploy to one accelerator first. Increase deadlines only from measured healthy
runs; never disable them. Roll back the host binary and FPGA image together if
the protocol or output checksum changes. Keep the first failing diagnostic line
and associated image/workload metadata for comparison.
