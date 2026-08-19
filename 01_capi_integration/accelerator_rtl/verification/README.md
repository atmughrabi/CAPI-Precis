# CAPI-Precis RTL accelerator verification

`accelerator_verification.sv` is a simulation-only bounded monitor for the
shared `cached_afu` architecture. `accelerator_verification_bind.sv` connects it
to AFU configuration, CU configuration/status, progress, error, completion,
acknowledgement, and reset signals without changing synthesizable RTL.

The default cycle bounds are intentionally generous for PSLSE/ModelSim and can
be overridden on the bound instance. A violation terminates simulation with
`$fatal`; `+VERIF_FATAL=0` degrades violations to `$error` for bring-up.

`accelerator_verification_tb.sv` provides positive and negative protocol
regression cases. `lint_cached_afu_bind.sh` elaborates the real `cached_afu`,
AFU-control RTL, and each real modern `cu_control` variant from the ordered
Phase 0 manifests. The compatibility CU stub is excluded from this evidence,
and implicit nets or pin mismatches fail elaboration.

Run from the repository root:

```console
make rtl-verification
make rtl-real-elaboration
```
