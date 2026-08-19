# RTL verification manifests

Phase 0 replaces implicit accelerator-RTL discovery with reviewed, ordered
source manifests.

| File | Purpose |
| --- | --- |
| `manifests/memcpy.f` | Complete modern memcpy design source order |
| `manifests/memcpy-tutorial.f` | Complete modern tutorial design source order |
| `manifests/mmtiled.f` | Complete modern tiled-matrix design source order |
| `manifests/monitor.f` | Stable verification monitor API sources |
| `manifests/rtl-inventory.json` | Every RTL path, declaration, hash, status, membership, unit, and evidence |
| `scripts/verify_manifests.py` | G0 source-set and inventory gate |

Run:

```console
make rtl-manifest-verification
make rtl-real-elaboration
```

After an intentional RTL change, review the diff and refresh hashes with:

```console
make rtl-manifest-update
```

The three incomplete mmtiled drafts and the compatibility CU stub are
quarantined in the inventory. They cannot enter a modern design manifest.
ModelSim source order must match each manifest exactly. Quartus loads the same
variant manifest through `accelerator_sources.tcl`.

The portable G0/G1 checks run in CI. Licensed ModelSim and Quartus
analysis/elaboration remain release evidence and are not replaced by the
Verilator/Tcl gates.
