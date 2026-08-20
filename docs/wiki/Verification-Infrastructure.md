# Verification infrastructure

## Purpose

CAPI-Precis owns the reusable verification infrastructure for the shared
host-to-accelerator and AFU-control contract. AccelGraph consumes this
infrastructure through its pinned CAPI-Precis submodule and owns only
graph-specific adapters, scoreboards, fixtures, and algorithm tests.

This page records the portable merge evidence and the remaining
licensed-tool/hardware release evidence.

## Current baseline

| Area | Current evidence | Remaining release evidence |
| --- | --- | --- |
| Host runtime | Timeout parsing, blocked-call watchdog, fake-libcxl setup/MMIO/error/completion/reset tests | Fault injection across every libcxl operation and structured test reports |
| RTL lifecycle | Bound configuration/progress/error/done/ACK/reset monitor plus complete module-family assertions, coverage, and mutations | Licensed ModelSim execution and hardware traces |
| Real bind | Real `cached_afu` elaboration for `memcpy`, `memcpy-tutorial`, and `mmtiled`, with implicit nets rejected and no CU stub | Licensed ModelSim and Quartus analysis/elaboration evidence |
| Algorithms | Independent memcpy, tutorial, and 2×2 mmtiled goldens with cycle-accurate CU scoreboards | Licensed simulator and hardware equivalence runs |
| Simulation | Portable Verilator suites with deterministic backpressure, scoreboards, exact structural census, and replayable evidence | ModelSim parity and automated cross-backend comparison |
| CI | Host, monitor, real-CU bind, exact source/inventory/module-plan gates, executable family suites, and measured closure | Licensed-tool jobs and retained hardware failure artifacts |

### Phase 0 manifest gate

The executable Phase 0 baseline lives in
`01_capi_integration/accelerator_verification/rtl`:

- three ordered modern design manifests contain 44 modules and 13 packages;
- `rtl-inventory.json` classifies every production and executable verification
  RTL file with declarations, SHA-256,
  build membership, verification unit, and evidence;
- 25 legacy modules and 5 legacy packages remain explicitly
  `legacy-supported`;
- the three incomplete mmtiled drafts are `quarantined` and cannot enter a
  modern manifest;
- ModelSim source order must match each variant manifest exactly;
- the Quartus Tcl loader is executed under `tclsh` and must preserve that exact
  order without `glob`;
- Verilator elaborates each real `cached_afu + cu_control` variant with
  implicit nets promoted to errors.

```console
make rtl-manifest-verification
make rtl-real-elaboration
```

G0 and portable G1 are active merge gates. Licensed ModelSim and Quartus
analysis/elaboration remain required release evidence before Phase 0 is marked
closed on supported hardware.

### Exact module coverage plan

`coverage-plan.json` defines reusable test strategies, family-specific
scenarios, backpressure, assertions, oracles, artifacts, and closure rules.
`module-test-matrix.json` is generated from the RTL inventory and must map every
active production module exactly once.

Current planning baseline:

| Measure | Value |
| --- | ---: |
| Active production module declarations | 44 |
| Distinct active source hashes | 33 |
| Active package declarations | 13 |
| Module/build context executions | 114 |
| Test families | 23 |
| Modules mapped to one family | 44/44 |
| Executable family suites complete | 23/23 |
| Package-contract suites complete | 1/1 |

Implemented P0 evidence:

- `parity` / `dw_parity`: 1,544 deterministic vectors, 28/28 functional bins,
  100% instrumented DUT toggle points, and 4/4 output/mode/lane mutations
  detected. Continuous-assignment-only statement/branch/FSM metrics are
  explicitly not applicable.
- package contracts: all 3 modern variants, 13 active packages, 128-byte C/SV
  WED ABI, interface/type widths, endian functions through 1,024 bits, CABT,
  descriptor/error maps, reachable function coverage, and 3/3 mutations.
- protocol control: credit, command, response, response statistics, tag, and
  restart DUTs; 708/708 functional bins, 100% of every reachable
  line/branch/toggle denominator after exact structural exclusions, and 9/9
  diagnostic mutations.
- reset: 83 checks, 18/18 functional bins, 100% reachable line/branch/toggle,
  PULSE_HOLD=1 and multi-stage release, and 9/9 mutations.
- storage: 257 vectors, 1,280 checks, 33/33 bins, 100% reachable
  line/branch/toggle, DEPTH=1/non-power-of-two wrap, and 15/15 mutations.
- arbitration: all 11 primitive/wrapper modules, 4,443 vectors, 538/538 bins,
  100% reachable line/branch/toggle, N=1 and non-power-of-two cases, aligned
  payload/grants and reset behavior, and 21/21 mutations.
- protocol data/lifecycle: read/write data, WED, MMIO, job, done, and error
  DUTs across all 3 variants; 15,790 checks, 258/258 bins, 100% reachable
  line/branch/toggle, beat-associated parity and fully initialized WED
  metadata, and 32/32 mutations.
- CU families: memcpy, tutorial, and 2×2 mmtiled; 54/54 RTL bins, 14/14
  independent golden bins, 100% reachable coverage per mapped module, 17/17
  mutations, AFU-accurate cacheline-half timing, edge tiles, repeated launch,
  reorder, and backpressure.
- integration: AFU-control, cached-AFU, and physical wrapper across all three
  manifests; 23/23 bins, 621 assertions, fixed/RR concurrency, exact
  credit/tag/restart/NLOCK/error
  lifecycles, 100% reachable coverage, and 3/3 mutations.

Coverage closure requires 100% of reachable statements, branches, FSM
states/transitions, functional bins, assertion goals, and reachable control
toggles. A waiver must record reason, owner, issue, affected items/metric,
approval, and expiry; waived logic remains visible and is not counted as
silently covered.

### Inventory

- 35 synthesizable declarations in shared `afu_control`.
- 8 active modern CU modules: 3 `memcpy`, 3 `memcpy-tutorial`, and 2
  `mmtiled`.
- 13 package declarations with variant-local packages sharing names.
- 43 active RTL declarations grouped into 30 verification units.
- 3 stale `mmtiled` declarations quarantined from all modern source manifests.
- 25 legacy module declarations and 5 legacy packages across the direct
  `cu_helloAFU`, direct `cu_tutorial`, and `cu_mmtiled/port` trees. These are
  not active modern targets but remain in the G0 denominator until explicitly
  classified.

The G0 inventory is path-level, not count-only. Every `.sv`, `.v`, `.vhd`, and
`.vhdl` file receives one status:

- `active`
- `legacy-supported`
- `quarantined`
- `generated/external`
- `removed`

The manifest records build membership, ordered compile position, source hash,
verification unit, and evidence. Unclassified RTL fails G0.

Legacy-supported scope must explicitly cover or deprecate `cu_helloAFU`,
`cu_tutorial`, and `cu_mmtiled/port`. The currently stale files are:

- `cu_mmtiled/global_cu/loop_index_generator.sv`
- `cu_mmtiled/mmtiled/cu/cu_data_read_engine_control.sv`
- `cu_mmtiled/mmtiled/cu/cu_data_write_engine_control.sv`

## Verification contract

Every test must provide all applicable evidence:

1. **Protocol assertions** - local safety and bounded liveness properties.
2. **Transaction scoreboard** - expected requests, tags, responses, data, and
   credits matched against observed traffic.
3. **Independent golden model** - expected function derived without calling the
   DUT implementation.
4. **Backpressure schedule** - deterministic ready/credit/response behavior.
5. **Functional coverage** - required scenarios and boundary crossings.
6. **Failure bundle** - first failure, seed, profile, manifest, transaction
   journal, expected/actual diff, and waveform.

Passing a test because no assertion fired is insufficient.

## Canonical infrastructure

### Testbench services

| Service | Responsibility |
| --- | --- |
| Clock/reset service | Deterministic clocks, asynchronous assertion, synchronous release, reset-phase injection |
| Job BFM | RESET, START, invalid commands, parity, address, and command gaps |
| MMIO BFM | Descriptor reads, register reads/writes, delayed ACK, malformed address/data parity |
| Command sink | Models PSL command-room availability and validates command payload/parity |
| Credit model | Initializes, consumes, and returns credits independently per command class |
| Response source | Generates DONE, PAGED, AERROR, DERROR, FAILED, FAULT, NRES, NLOCK, and reordered responses |
| Read-data source | Emits lower/upper cache-line halves with delay, reorder, and parity injection |
| Buffer-read BFM | Requests write-data halves with independent command/data timing |
| Byte memory | Applies reads/writes to a byte-addressable coherent memory image |
| Transaction journal | Records cycle, channel, tag, command, address, size, metadata, data hash, and response |
| Backpressure scheduler | Produces named deterministic and seeded channel schedules |
| Artifact writer | Emits JUnit, JSON summary, memory diff, transaction log, reproduction command, and failure-only waveform |

### Backpressure profiles

The scheduler owns independent channels:

- `capi.command`: PSL command room / command acceptance
- `capi.credit.wed`
- `capi.credit.read`
- `capi.credit.write`
- `capi.credit.prefetch_read`
- `capi.credit.prefetch_write`
- `capi.response`: PSL response return
- `capi.read_data`: read-data delivery
- `capi.write_buffer`: write-buffer read requests
- `capi.mmio`: MMIO request cadence
- `capi.job`: job request cadence
- `capi.ack`: completion acknowledgement delay
- `capi.reset`: reset injection

Required named profiles:

| Profile | Behavior |
| --- | --- |
| `always_ready` | No artificial stalls; deterministic latency |
| `alternating` | Ready every other cycle |
| `burst_stop` | Long ready burst followed by bounded stop |
| `near_full` | Queue occupancy held around almost-full |
| `zero_credit` | One or more credit classes held at zero, then released |
| `response_reorder` | Legal out-of-order tag completion |
| `half_reorder` | Upper/lower read-data halves returned in both legal orders |
| `reset_phase` | Reset asserted during idle, issue, response, done publication, and ACK wait |
| `seeded_random` | Independent channel streams driven by a specified xorshift implementation |

Identical backend version, seed, profile, fixture, and manifest must reproduce
the byte-identical transaction-journal hash.

Cross-backend comparison uses a canonical projection containing per-channel
transaction order, tag, command, address, size, metadata, response, and data
hash. It excludes cycle numbers, X-valued fields, scheduling metadata, and
backend identity. The projection must match across backends; X-state evidence
remains backend-scoped.

### Combination policy

Full Cartesian expansion is not a PR requirement.

| Tier | Combination rule |
| --- | --- |
| P0 unit | Each channel independently, each boundary profile, and relevant fault injection |
| P0 integration | Every single channel plus all high-risk pairs involving command, credit, response, data, ACK, and reset |
| P1 integration | Pairwise covering array across all CAPI channels and selected risk-based triples |
| P2/nightly | Seeded random overlays across all channels |
| Timeout tests | Selected permanent stalls with an explicit expected timeout/failure |

All non-timeout stalls have a declared maximum duration and eventual-release
assumption. A profile without eventual release must name the timeout or reset
that is expected to terminate it.

The pairwise array is a version-controlled artifact containing factor names,
levels, generator name/version, generator seed, case count, and SHA-256.
Regeneration is reviewed like source. Required risk triples are:

- `capi.command` + a selected `capi.credit.*` class + `capi.response`
- `capi.read_data` + `capi.response` + `capi.reset`
- `capi.write_buffer` + `capi.ack` + `capi.reset`
- `capi.job` + `capi.mmio` + `capi.command`

## Scoreboards and goldens

### Protocol scoreboards

- Credit conservation per command class.
- Outstanding-tag uniqueness, exhaustion, metadata retention, and safe reuse.
- Command-to-response classification and restart eligibility.
- Read-data half association with the issuing tag and destination.
- Write-command, write-data-half, mask, address, and size coupling.
- Restart replay without command loss or duplication.
- WED fetch and decode exactly once per job.
- Completion snapshot, publication, stability, acknowledgement, and reset.
- Response-statistic and byte-count agreement with observed traffic.

### Independent models

- Odd/even parity and per-doubleword parity.
- FIFO and RAM contents/latency.
- Fixed, variable, and round-robin arbitration.
- Endian conversion and WED/descriptor field maps.
- Command chunking by address alignment, cache-line boundary, and size.
- Byte-for-byte memory copy.
- Tiled matrix multiplication with edge tiles.

Golden code must not reuse DUT functions except immutable type declarations.

## Module test matrix

Priority meanings:

- **P0** - required before the infrastructure can gate merges.
- **P1** - required before simulator/hardware release.
- **P2** - parameter sweeps, long random runs, and coverage closure.

### Packages and utilities

| Verification unit | RTL modules | Priority | Required scenarios |
| --- | --- | --- | --- |
| Package contracts | `GLOBALS_AFU_PKG`, `CAPI_PKG`, `CREDIT_PKG`, `AFU_PKG`, variant `GLOBALS_CU_PKG`, `WED_PKG`, `CU_PKG` | P0 | Struct widths/offsets, endian functions, CABT mapping, descriptor values, error bits, command sizes; C/SV WED ABI agreement |
| Parity | `parity`, `dw_parity` | P0 | Exhaustive small widths, random large widths, odd/even mode, independent doublewords |
| Reset | `reset_filter`, `reset_control` | P0 | Async assertion, synchronized release, hold length, repeated and overlapping sources |
| RAM | `ram`, `ram_2xrd`, `mixed_width_ram` | P0/P2 | Every address, latency, dual-read coherence, read-during-write, mixed-width ratios |
| FIFO | `fifo` | P0 | Order, wrap, empty/full/almost-full, simultaneous push/pop, blocked underflow/overflow |

### Arbitration

| Verification unit | RTL modules | Priority | Required scenarios |
| --- | --- | --- | --- |
| Primitive arbiters | `vc_FixedArbChain`, `vc_FixedArb`, `vc_VariableArbChain`, `vc_VariableArb`, `vc_RoundRobinArbChain`, `vc_RoundRobinArb`, `vc_RoundRobinArb_V2` | P0/P2 | No request, single/all request, held request, priority order, round-robin rotation, fairness, N=1/non-power-of-two |
| AFU arbiter wrappers | `fixed_priority_arbiter_N_input_1_ouput`, `fixed_priority_arbiter_1_input_N_ouput`, `round_robin_priority_arbiter_N_input_1_ouput`, `round_robin_priority_arbiter_1_input_N_ouput` | P0 | Payload/grant alignment, one-hot grant, fan-in/fan-out policy, stalled destination |

The misspelled `ouput` names are current module ABI. Keep them until wrappers
allow a compatible rename.

### AFU-control protocol

| Verification unit | Priority | Golden/scoreboard | Required backpressure and faults |
| --- | --- | --- | --- |
| `credit_control` | P0 | Credit ledger | Zero credits, issue/return same cycle, burst replenish, limit boundaries |
| `command_control` | P0 | Command encoder/parity model | Command-room stalls; every command, size, address, ABT, tag |
| `response_control` | P0/P1 | Outstanding-tag router | Reordered tags; every PSL response; parity errors |
| `response_statistics_control` | P1/P2 | Journal-derived counters | Bursty responses, byte counts, rollover |
| `tag_control` | P0 | Tag allocation model | Exhaustion, wrap, out-of-order return, metadata read/reuse |
| `read_data_control` | P0/P1 | Read-half/tag scoreboard | Both half orders, data gaps, WED/read routing, parity injection |
| `write_data_control` | P0/P1 | Write-half coupling scoreboard | Independent command/data stalls, requested-half combinations |
| `restart_control` | P0/P1 | Replay ledger | PAGED/AERROR/DERROR by ABT, credit starvation, flush/replay/drain |
| `wed_control` | P0 | Independent WED decoder | Full command queue, response/data ordering, exactly one fetch |
| `mmio` | P0/P1 | Register map oracle | Every descriptor/register width, pulse, ACK, unmapped address, parity fault |
| `job` | P0 | Job FSM model | RESET/START/invalid commands, parity, command gaps |
| `done_control` | P0 | Completion lifecycle scoreboard | Zero/nonzero result, delayed/missing ACK, repeated jobs, reset phase |
| `error_control` | P0/P1 | Sticky-error model | Simultaneous/repeated errors, delayed ACK, reset |

### Integration

| Verification unit | Priority | Required scenarios |
| --- | --- | --- |
| `afu_control` | P0/P1 | Concurrent WED/read/write/prefetch traffic, fixed/RR policy, tag/credit exhaustion, restart, response reorder |
| `cached_afu` | P0/P1 | Job through WED, MMIO, CU, PSL, completion, error, reset, repeated launch |
| `afu` | P1 | Pin-to-record ordering, parity, full wrapper smoke |

### Compute units

| Verification unit | Priority | Required scenarios |
| --- | --- | --- |
| `cu_memcpy` read engine | P0/P1 | Zero/one/tail/full/multi-cacheline, cached/noncached, prefetch/TLB, exact request sequence |
| `cu_memcpy` write engine | P0/P1 | Half pairing, masks, address/size/CABT, cached/noncached writes |
| `cu_memcpy` control | P0 | Real port closure, config/status/done, read-to-write coupling, byte-exact copy |
| Tutorial `read_engine` | P0/P1 | Chunk/tail generation, responses, counters |
| Tutorial `write_engine` | P0/P1 | Command/data coherence, half pairing, counters |
| Tutorial control | P0 | Config/status/done, exact memory copy, repeated jobs |
| `cu_matrix_C_job_control` | P1 | Tile clipping, partial rows, half extraction, address formula, counters |
| `mmtiled` control | P0 compile/P1 function | Four config words, routing, edge tiles, counters/done, independent matrix oracle |

## Cross-engine matrix

The P0/P1 integration runner must execute:

1. `afu_control` with concurrent synthetic WED/read/write/prefetch producers.
2. `cached_afu + memcpy`.
3. `cached_afu + memcpy-tutorial`.
4. `cached_afu + mmtiled`.
5. Existing PSLSE/ModelSim compatibility smoke.

For each applicable suite:

- Run all combinations of independent command, response, read-data,
  write-buffer, MMIO, and ACK/reset stalls.
- Run bounded deterministic pauses.
- Run fixed seeds `{13, 52, 1024, 27491095, 37491095, 1461247482}`.
- Run nightly random seeds with replay metadata.
- Require zero scoreboard mismatches, zero unexpected assertions, and full
  required coverage bins.

## Toolchain and dependency contract

Phase 0 publishes and CI enforces this matrix before reusable infrastructure is
implemented:

| Tool/backend | Role | Gate | Version policy | License/runner |
| --- | --- | --- | --- | --- |
| Verilator | Portable lint, unit tests, assertions, deterministic scoreboards | Required PR | Pin exact version; >= 5.050 for coverage jobs | Open-source hosted runner |
| GCC | Host tests and DPI/native helpers | Required PR | Pin CI image/compiler major | Open-source hosted runner |
| Python | Manifest, result, schema, and oracle tooling | Required PR | Lock interpreter and package hashes | Open-source hosted runner |
| ModelSim/Questa | PSLSE compatibility, 4-state/X checks, covergroups, wave evidence | Required release; selected nightly | Record exact supported releases | Licensed self-hosted runner |
| PSLSE | End-to-end CAPI protocol simulation | Required release; selected nightly | Pinned submodule plus build hash | Self-hosted runner |
| Quartus | Analysis/elaboration, timing, and representative implementation | Required release | Record supported releases and IP versions | Licensed self-hosted runner |

### Portability rules

- The common BFM/model/scoreboard core uses a documented synthesizable and
  simulator-portable SystemVerilog subset.
- Tool-specific SVA, covergroup, DPI, waveform, or vendor-IP code lives behind
  explicit backends.
- A required gate that lacks a runner or license is **blocked/failing**, never
  silently passed.
- Optional local checks may skip with an explicit message; CI release gates may
  not.
- Every added package records name, version, source, license, and lock/hash.
- Artifacts whitelist logs, JSON/JUnit, transaction journals, diffs, and
  failure-only open wave formats. Never upload vendor IP, license files,
  encrypted libraries, restricted datasets, or proprietary binaries.

## CI tiers and measurable closure

| Tier | Scope | Runtime target | Sharding | Retention |
| --- | --- | ---: | --- | ---: |
| PR-fast | Compile/manifests, package contracts, P0 utility units, changed-module tests, fixed smoke seed | <= 20 min | By verification unit | 14 days on failure |
| PR-full | All P0 units, one all-ready integration per active CU, required assertions | <= 60 min | Shared AFU / each CU variant | 30 days on failure |
| Nightly | P0+P1, named profiles, pairwise covering arrays, fixed seeds plus random seeds | <= 6 h | Unit/profile/variant | 30 days |
| Release | All P0/P1, required licensed backends, source-set equivalence, coverage closure, representative Quartus evidence | Scheduled | Backend/variant | Release lifetime |
| P2 campaign | Parameter sweeps and long randomized coverage | Budgeted campaign | Seed/profile | Campaign lifetime |

Initial budget model:

- PR-full: 30 verification units x one P0 deterministic case, plus 3 CU
  all-ready integration cases; compile once per unit/variant; target average
  <= 60 seconds per case across at least 8 shards.
- Nightly: named single-channel cases, version-controlled pairwise array,
  required risk triples, and fixed seeds rotated across CU variants; compile
  once per variant and reuse snapshots across profiles.
- Release: full P0/P1 matrix on licensed and open backends. Phase 1 records
  measured per-case runtimes and fails planning review if the stated budgets
  cannot be met without reducing a required denominator.

### Coverage policy

`accelerator_verification/rtl/manifests/coverage-plan.json` is normative:

- 100% of reachable statements, branches, FSM states/transitions, functional
  bins, assertion goals, and reachable control toggles;
- 100% execution of every mapped module context;
- zero unexplained assertion disables or scoreboard mismatches;
- only versioned, approved, expiring waivers with an owner and issue;
- missing required coverage data fails the tier.

Partial percentages may be reported while suites are under construction, but
they are progress measurements, not release floors.

| Metric | Backend | Earliest required tier |
| --- | --- | --- |
| Assertions | Pinned Verilator | PR-fast |
| Functional bins implemented in portable counters | Pinned Verilator | PR-full |
| Statement/branch/toggle | Verilator >= 5.050 or pinned Questa backend | Nightly |
| FSM state/transition | Pinned coverage-capable backend | Nightly |
| Cross coverage / covergroups | Pinned Questa backend unless portable implementation exists | Release |

## Replay, manifest, and artifact schemas

All schemas are versioned and stored under
`01_capi_integration/accelerator_verification/schema`.

### Consumer API

`01_capi_integration/accelerator_verification/schema/api_version.json` will
publish semantic version, compatible schema versions, minimum consumer
version, and deprecation policy when Phase 1 introduces the shared schema.

Consumer repositories register channel namespaces in a version-controlled
registry assigning stable channel IDs and channel-order indices. `graph.*` is a
reserved downstream namespace. The journal schema supports namespaced record
extensions that retain the required core transaction fields.

A candidate API release is not published until a downstream compatibility job
checks out the declared AccelGraph commit, updates it to the candidate CAPI
commit, and passes its manifest/elaboration/schema self-tests.

### Build manifest

Canonical JSON fields:

- schema version
- repository commit and all submodule commits
- ordered repository-relative source paths and SHA-256 content hashes
- ordered include paths
- defines
- top module
- parameters
- package/library mapping
- vendor libraries/IP identifiers
- tool name/version
- manifest SHA-256

Source-set equivalence compares all fields, not just filenames.

### Replay descriptor

Canonical JSON fields:

- schema version
- build-manifest hash
- fixture/golden hash
- test and variant
- seed
- PRNG algorithm/version
- backpressure profile/version and channel parameters
- clock/reset parameters
- tool/backend identity
- expected outcome

Replay refuses to run when required hashes or schema versions differ unless an
explicit migration mode is selected.

### Transaction journal

Canonical JSONL ordering is cycle, channel-order index, and transaction index.
Each record includes channel, direction, tag, command, address, size, metadata,
data hash, response, and relevant state. SHA-256 is computed over normalized
UTF-8 with sorted object keys and LF endings.

### Failure bundle

- JUnit and JSON result
- replay descriptor
- build manifest
- first assertion/scoreboard failure
- recent transaction window
- expected/actual memory diff
- final counters/coverage
- reproduction command
- failure-only waveform when redistribution is permitted

## Folder migration

Production RTL remains in its current location until verification proves path
equivalence. The target structure is:

```text
01_capi_integration/
  accelerator_rtl/              synthesizable design only
  accelerator_sim/              simulator execution flow
  accelerator_synth/            Quartus execution flow
  accelerator_verification/
    host/                        libcxl/watchdog contract tests
    sim/                         verification wave configuration
    rtl/
      manifests/
      models/
      scripts/
      unit/
      integration/
      fixtures/
      golden/
      common/
        pkg/
        interfaces/
        bfm/
        scoreboards/
        assertions/
        coverage/

docs/
  assets/
  archive/slides/
  wiki/
```

Planned subdirectories are created when their first executable test lands; no
empty scaffolding is committed.

### Compatibility rules

- Keep root `make verify`, `make rtl-verification`, `make run-vsim`,
  `make run-pslse`, and synthesis targets.
- Convert existing Make/Tcl entry points into thin wrappers only after the new
  runner passes from repository root and legacy working directories.
- Compile each CU variant in an isolated work directory because package names
  collide.
- Freeze consumer-facing paths and symbols for verification API v2 at
  `01_capi_integration/accelerator_verification/rtl/accelerator_verification.sv`,
  the bind template, module name, ports, and parameters for one API-major
  version.
- Publish
  `01_capi_integration/accelerator_verification/rtl/manifests/monitor.f`;
  consumers use the manifest instead of hardcoding the monitor source path.
- A path/symbol change requires an API-major bump and a coordinated downstream
  compatibility job. A one-release shim is required only when a supported
  external consumer cannot migrate in the same release.
- Add ordered manifests before replacing any wildcard or explicit source list.
- Switch Quartus source assignment only after manifest/source-set equivalence.
- Move active logos and diagrams to `docs/assets`; retain compatibility links
  until README/wiki references and release notes are updated.
- Move historical slide material to `docs/archive/slides` only after proving
  no synthesis/simulation script references it.
- Publish `docs/wiki` to the GitHub wiki before merging README/sidebar links to
  new pages.
- CI compares normalized SHA-256 content for every `docs/wiki/*.md` page against
  the wiki repository and rejects missing pages or redirects to wiki home.
- A merge-triggered publisher mirrors `docs/wiki` to `CAPI-Precis.wiki.git`.
  Pull requests validate source only; post-merge validates the published hash.
- Wiki editing is restricted to collaborators; direct wiki edits are
  overwritten and must be backported to `docs/wiki`.
- Page existence is checked through `raw.githubusercontent.com/wiki/...` or a
  wiki git clone. Following HTML redirects to wiki home is not a valid page
  check.
- Keep compatibility stubs for moved repository documents for at least one
  release.

## Phased delivery

### Phase 0 - exact manifests and compile closure

**Status:** G0 and portable real-CU elaboration implemented; licensed ModelSim
and Quartus closure pending.

- Record the 35 shared modules, 8 active modern CU modules, 13 packages, and
  explicit exclusions in ordered manifests.
- Repair the `cu_memcpy` buffer-status port mismatch.
- Decide the three stale `mmtiled` declarations: repair, quarantine, or remove.
- Require all three real CU variants to elaborate without a CU stub, implicit
  nets, or unresolved symbols.

**Gate:** source-set audit passes ModelSim and Quartus analysis/elaboration.

### Phase 1 - infrastructure kernel

- Implement interfaces, deterministic PRNG, scheduler, journal, result schema,
  assertion package, scoreboard base, and artifact writer.
- Add one intentionally failing test to prove the artifact contract.

**Gate:** identical seed/profile yields identical journal hash and reproduction
command.

### Phase 2 - utility and arbitration units

- Package, parity, reset, RAM, FIFO, primitive arbiter, and wrapper suites.

**Gate:** all P0 tests pass; all mandatory bins hit; exclusions documented.

### Phase 3 - AFU protocol units

- Credit, command, response, statistics, tag, data, restart, WED, MMIO, job,
  done, and error suites.

**Gate:** zero ledger mismatches across named profiles and fixed seeds.

### Phase 4 - CU units

- `memcpy`, tutorial, and `mmtiled` engine/control suites.

**Gate:** real CU elaboration and byte/matrix golden comparisons pass.

### Phase 5 - integration and stress

- Full `afu_control`, `cached_afu`, and wrapper tests.
- All named backpressure profiles, repeated jobs, fixed seeds, and nightly
  randomized runs.

**Gate:** no leaked tags/credits/state; all required coverage bins hit.

### Phase 6 - flow migration

- Delegate legacy Make/Tcl scripts to manifests and the canonical runner.
- Validate ModelSim, PSLSE, Quartus map, and representative full fits.

**Gate:** old entry points produce equivalent source lists and clean worktrees.

Legacy and wrapper entry points run in dual mode during the one-release
compatibility window. Any G6/G7 failure reverts the wrapper/migration commit
before further cleanup.

### Phase 7 - documentation/archive migration

- Publish verification status and coverage.
- Move active assets and archive historical slides.
- Remove compatibility wrappers only after one release.

## Release gates

| Gate | Requirement |
| --- | --- |
| G0 inventory | Exact manifest with no unexpected wildcard source |
| G1 compile | Every active variant elaborates without stubs or implicit nets |
| G2 unit | Every P0 unit passes; mandatory functional bins are complete |
| G3 integration | Every modern CU passes lifecycle and named backpressure profiles |
| G4 coverage | All reachable closure targets are 100%; every waiver is valid and unexpired |
| G5 reproducibility | Failure artifacts reproduce by test, seed, profile, and manifest hash |
| G6 compatibility | Existing Make, ModelSim, PSLSE, and Quartus entry points remain valid |
| G7 migration | Links validate, generated files are ignored, and `git status` remains clean |

## Known P0 decisions

- Correct the package endian functions whose declared return widths appear
  narrower than their names imply.
- Resolve simulation/synthesis source-set drift.
- Do not claim `mmtiled` synthesis parity until stale wildcard-selected files
  are dispositioned.
- Do not deduplicate or rename legacy module families until unit and
  equivalence tests exist.
