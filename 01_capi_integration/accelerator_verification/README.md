# Accelerator verification

This directory owns CAPI-Precis accelerator-contract verification. Runtime
watchdog code remains in `00_bench/src/capi_utils`; benchmark and algorithm
tests remain beside the code they validate.

```text
host/          libcxl/watchdog integration tests and fake libcxl boundary
rtl/           monitor, bind, protocol testbench, manifests, scripts
sim/           ModelSim verification wave configuration
```

Phase 0 replaces implicit accelerator-RTL discovery with reviewed, ordered
source manifests under `rtl/manifests`.

| File | Purpose |
| --- | --- |
| `rtl/manifests/memcpy.f` | Complete modern memcpy design source order |
| `rtl/manifests/memcpy-tutorial.f` | Complete modern tutorial design source order |
| `rtl/manifests/mmtiled.f` | Complete modern tiled-matrix design source order |
| `rtl/manifests/monitor.f` | Stable consumer-facing monitor core |
| `rtl/manifests/monitor-capi-bind.f` | Canonical CAPI-Precis bind |
| `rtl/manifests/rtl-inventory.json` | Every RTL path, declaration, hash, status, membership, unit, and evidence |
| `rtl/manifests/coverage-plan.json` | Family strategies and 100% reachable-coverage closure policy |
| `rtl/manifests/module-test-matrix.json` | Generated one-row-per-active-module test ownership |
| `rtl/scripts/verify_manifests.py` | G0 source-set and inventory gate |
| `rtl/scripts/verify_module_plan.py` | Canonical exact module-plan validator |
| `rtl/scripts/test_verify_module_plan.py` | Mutation regressions for plan/schema enforcement |
| `rtl/scripts/lint_cached_afu_bind.sh` | Real-CU elaboration and interface gate |

Run:

```console
make rtl-manifest-verification
make rtl-real-elaboration
```

The module matrix currently maps all 43 active production modules across 32
source hashes to 23 test families. The parity family is implemented with
exhaustive/deterministic vectors, complete functional/toggle evidence, and
mutation sensitivity; the other 22 families remain planned. A mapped test is
not considered implemented until its executable target and coverage evidence
exist.

After an intentional RTL change, review the diff and refresh hashes with:

```console
make rtl-manifest-update
```

The three incomplete mmtiled drafts are quarantined in the inventory. They
cannot enter a modern design manifest.
ModelSim source order must match each manifest exactly. Quartus loads the same
variant manifest through `accelerator_sources.tcl`.

The portable G0/G1 checks run in CI. Licensed ModelSim and Quartus
analysis/elaboration remain release evidence and are not replaced by the
Verilator/Tcl gates.

The default monitor cycle bounds are intentionally generous for PSLSE/ModelSim
and may be overridden on the bound instance.
