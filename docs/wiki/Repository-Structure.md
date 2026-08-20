# Repository structure

## Rules

1. Numbered roots have one owner; new roots require a documented responsibility.
2. `accelerator_rtl` contains synthesizable design only.
3. Accelerator-contract tests and infrastructure live under
   `01_capi_integration/accelerator_verification`.
4. Benchmark/application tests stay beside the code they validate.
5. Generic CAPI verification is maintained here and consumed by pin; it is not
   copied into AccelGraph.
6. Generated work libraries, reports, waveforms, and coverage databases are
   ignored artifacts, never source.
7. A move lands only after Make, ModelSim, Quartus-source, CI, documentation,
   and downstream pin checks pass.

## Naming convention

- Numbered repository roots use two digits and snake case.
- Integration roles use `accelerator_<role>`:
  `accelerator_rtl`, `accelerator_sim`, `accelerator_synth`,
  `accelerator_bin`, and `accelerator_verification`.
- Product names remain `CAPI-Precis` in prose and repository links; source
  paths are written exactly as they appear on disk.
- Legacy external paths such as `capi-utils` remain unchanged when renaming
  would break a submodule or public flow.

## Owned roots

| Path | Responsibility |
| --- | --- |
| `00_bench` | Host applications, runtime watchdog, OpenMP references, benchmark tests |
| `01_capi_integration` | CAPI/PSLSE integration, accelerator design/build/verification |
| `02_slides` | Historical presentations and brand source assets |
| `03_scripts` | Legacy benchmark/build selection helpers |
| `docs` | Maintained documentation and published-wiki source |
| `tools` | Repository environment wrapper and its tests |

## Integration layout

```text
01_capi_integration/
  accelerator_rtl/              synthesizable AFU/CU RTL only
  accelerator_sim/              PSLSE/ModelSim execution flow
  accelerator_synth/            Quartus execution flow
  accelerator_bin/              released implementation outputs
  accelerator_verification/
    host/                        libcxl/watchdog contract tests
    sim/                         verification wave configuration
    rtl/
      manifests/                 inventory, source, coverage, module matrix
      scripts/                   validators and real-CU gates
      unit/
        parity/                  parity functions
        package_contracts/       C/SystemVerilog ABI and package contracts
        reset/                   reset primitives
        storage/                 RAM and FIFO
        arbitration/             primitive and wrapper arbiters
        protocol_control/        command, credit, response, restart, tag
        protocol_data/           data, WED, MMIO, job, completion, error
        cu/                      memcpy, tutorial, and mmtiled compute units
      integration/               AFU/CU cross-module suites
```

Directories below `unit` and `integration` are added with their first
executable test; empty scaffolding is not committed.

## Migration order

| Stage | Work | Gate |
| --- | --- | --- |
| S0 | Consolidate existing verification | Complete: public Make targets and all current tests pass |
| S1 | Implement P0 utility/arbitration unit families | Complete: exact module matrix remains 44/44 |
| S2 | Implement AFU protocol families | Complete: protocol scoreboards and mutations close |
| S3 | Implement CU and full-system suites | Complete: real CU goldens, repeat launch, reset, and integration close |
| S4 | Delegate ModelSim/Quartus flows to canonical runner | Old entry points produce identical ordered sources |
| S5 | Archive unreferenced slides/assets | Link audit, release notes, clean worktree |

No production RTL or historical content moves merely for visual symmetry.

## Structure gate

A structural change is complete only when:

- `make verify`, `make rtl-manifest-verification`, and
  `make rtl-real-elaboration` pass;
- every active production RTL module and package contract has exactly one test
  owner;
- ModelSim and Quartus resolve the reviewed source order;
- the AccelGraph compatibility pin passes;
- documentation links and wiki mirrors match;
- no generated or duplicate source appears in `git status`.
