# Verification infrastructure

## Ownership

CAPI-Precis owns reusable verification for the shared host-to-accelerator and
AFU-control contract:

- package and C/SystemVerilog ABI checks;
- parity, reset, storage, and arbitration units;
- command, credit, response, restart, tag, data, WED, MMIO, job, completion,
  and error control;
- memcpy, tutorial, and mmtiled compute units;
- full AFU-control, cached-AFU, and wrapper integration;
- exact manifests, module ownership, mutations, and coverage evidence.

AccelGraph consumes this infrastructure through an exact submodule pin and
owns graph fixtures, engines, algorithm goldens, and graph-specific
backpressure. Generic CAPI tests are not copied downstream.

## Current portable closure

| Measure | Closed value |
| --- | ---: |
| Active production modules | 44/44 |
| Distinct production source hashes | 33 |
| Active packages | 13/13 |
| Module/build contexts | 114/114 |
| Module families | 23/23 |
| Package-contract suites | 1/1 |
| Executable runners | 9 |
| Exact runner owners | 24 |
| Incomplete owners | 0 |
| Waivers | 0 |

`make rtl-coverage-closure` is the canonical portable gate. It validates
inventory and plan provenance before accepting runner output; a suite cannot
claim ownership unless every context, functional bin, required coverage point,
and mutation is complete.

### Measured evidence

| Suite | Evidence |
| --- | --- |
| Package contracts | 3 variants, 246/246 bins, 81/81 reachable lines, 3/3 C ABIs, 3/3 mutations |
| Parity | 1,544 vectors, 28/28 bins, 100% reachable toggles, 4/4 mutations |
| Reset | 83 checks, 18/18 bins, 100% reachable line/branch/toggle, 9/9 mutations |
| Storage | 257 vectors, 1,280 checks, 33/33 bins, 100% reachable line/branch/toggle, 15/15 mutations |
| Arbitration | 11 modules, 4,533 vectors, 538/538 bins, 100% reachable line/branch/toggle, 25/25 mutations |
| Protocol control | 6 DUT families, 708/708 bins, 9/9 mutations |
| Protocol data | 3 variants, 6 families, 15,790 checks, 258/258 bins, 100% line/branch/toggle, 32/32 mutations |
| Compute units | 54/54 RTL bins, 14/14 independent goldens, 17/17 mutations |
| Integration | 23/23 bins across memcpy, tutorial, and mmtiled, 3/3 mutations |

Licensed ModelSim and Quartus analysis/elaboration and hardware traces remain
release evidence; they are not represented as portable passes.

## Canonical layout

```text
01_capi_integration/accelerator_verification/
  host/                        libcxl, timeout, completion, and reset tests
  sim/                         verification wave configuration
  rtl/
    manifests/                 ordered sources, inventory, plan, module matrix
    models/                    executable verification models only
    scripts/                   manifest, ownership, and real-RTL gates
    unit/
      parity/
      package_contracts/
      reset/
      storage/
      arbitration/
      protocol_control/
      protocol_data/
      cu/
    integration/               AFU-control, cached-AFU, and wrapper suites
```

Production RTL remains under `accelerator_rtl`; testbench, bind, injector, and
model sources remain under `accelerator_verification`.

## Evidence contract

Every executable family supplies:

1. **Protocol assertions** for local safety and bounded liveness.
2. **Transaction scoreboards** for commands, tags, responses, data, and
   credits.
3. **Independent goldens** that do not call DUT logic.
4. **Deterministic backpressure** with named schedules and eventual release.
5. **Functional and structural coverage** against an exact denominator.
6. **Diagnostic mutations** that prove the tests detect representative
   defects.
7. **Failure evidence** containing the first mismatch and reproduction path.

A test that merely reaches `$finish` without a scoreboard, assertion, or
required-bin check is not evidence.

## Backpressure profiles

| Profile | Contract |
| --- | --- |
| `always_ready` | Deterministic baseline with no injected stalls |
| `alternating` | Ready every other cycle |
| `burst_stop` | Bounded ready burst followed by a bounded stop |
| `near_full` | Queue occupancy held around almost-full |
| `zero_credit` | Selected credit classes withheld, then released |
| `response_reorder` | Legal out-of-order tagged completion |
| `half_reorder` | Cacheline halves exercised at their legal timing boundaries |
| `reset_phase` | Reset during idle, issue, response, completion, and ACK |
| `seeded_random` | Reproducible independent channel schedules |

Permanent stalls are used only when the expected result is a named timeout or
reset termination. Other profiles declare a maximum stall and eventual
release.

P0 units exercise each relevant channel independently. P0 integration adds
high-risk command/credit/response/data/ACK/reset combinations. Broader
pairwise and seeded campaigns are release or nightly evidence; they do not
replace deterministic P0 cases.

## Scoreboards and goldens

The shared scoreboards prove:

- per-class credit conservation and no over-issue;
- unique outstanding tags, metadata retention, and safe reuse;
- command-to-response classification and restart eligibility;
- cacheline-half association with the issuing tag;
- write command, data, address, size, and mask coupling;
- replay without command loss or duplication;
- one WED fetch/decode per job;
- stable completion until ACK and complete reset drain;
- response and byte statistics matching observed traffic.

Independent models cover parity, FIFO/RAM behavior, fixed and round-robin
arbitration, endian and descriptor maps, cacheline chunking, byte-for-byte
memory copy, and clipped tiled matrix multiplication.

## Exact manifests and ownership

The normative files are:

- `rtl/manifests/memcpy.f`
- `rtl/manifests/memcpy-tutorial.f`
- `rtl/manifests/mmtiled.f`
- `rtl/manifests/rtl-inventory.json`
- `rtl/manifests/coverage-plan.json`
- `rtl/manifests/module-test-matrix.json`

ModelSim and Quartus must resolve each ordered manifest exactly. Wildcard source
discovery, implicit nets, CU stubs, unclassified RTL, stale inventory hashes,
stale plan hashes, duplicate owners, and missing context executions fail the
gate.

Legacy direct examples remain explicitly `legacy-supported`; stale mmtiled
drafts remain quarantined and cannot enter a modern manifest.

## Coverage policy

Closure requires 100% of reachable:

- statements and branches;
- FSM states and transitions where applicable;
- functional bins and assertion goals;
- control toggles;
- mapped module/build contexts.

Tool-generated or structurally unreachable points are recorded by exact
source, scope, signal or branch, metric, and reason. Exercising a declared
unreachable point fails the census.

A waiver must include reason, owner, issue, metric, affected items, approval,
and expiry. Missing data, denominator drift, stale exclusions, or an expired
waiver fails closure.

## Commands

```console
make rtl-manifest-verification
make rtl-real-elaboration
make rtl-unit-verification
make rtl-coverage-closure
make verify
```

`make verify` combines portable RTL evidence with host, environment, benchmark,
and completion/reset checks. GitHub Actions sets
`RTL_VERIFICATION_REQUIRED=1`; local runs report an explicit skip when
Verilator 5 is unavailable.

## Release boundary

Portable closure establishes deterministic behavior under the checked
SystemVerilog backend. A hardware release additionally records:

- CAPI-Precis and recursive submodule commits;
- ModelSim/Quartus versions and ordered source manifest hashes;
- FPGA image and platform identity;
- workload, timeout overrides, result checksum, and elapsed time;
- the first failure diagnostic and trace when a gate fails.

The host binary, CAPI checkout, and FPGA image are one compatibility unit.
