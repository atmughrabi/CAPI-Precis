#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path


SCRIPT = Path(__file__).resolve()
REPO_ROOT = SCRIPT.parents[4]
RTL_ROOT = REPO_ROOT / "01_capi_integration/accelerator_rtl"
VERIFICATION_RTL_ROOT = (
    REPO_ROOT / "01_capi_integration/accelerator_verification/rtl"
)
MANIFEST_ROOT = (
    REPO_ROOT /
    "01_capi_integration/accelerator_verification/rtl/manifests"
)
INVENTORY_PATH = MANIFEST_ROOT / "rtl-inventory.json"

VARIANTS = {
    "memcpy": "01_capi_integration/accelerator_sim/sim/sim_memcpy.tcl",
    "memcpy-tutorial":
        "01_capi_integration/accelerator_sim/sim/sim_memcpy-tutorial.tcl",
    "mmtiled": "01_capi_integration/accelerator_sim/sim/sim_mmtiled.tcl",
}

QUARANTINED = {
    "01_capi_integration/accelerator_rtl/cu_control/cu_mmtiled/"
    "global_cu/loop_index_generator.sv":
        "Incomplete legacy draft references undeclared matrix-job state.",
    "01_capi_integration/accelerator_rtl/cu_control/cu_mmtiled/"
    "mmtiled/cu/cu_data_read_engine_control.sv":
        "Not instantiated by the modern mmtiled CU; excluded from ModelSim.",
    "01_capi_integration/accelerator_rtl/cu_control/cu_mmtiled/"
    "mmtiled/cu/cu_data_write_engine_control.sv":
        "Not instantiated by the modern mmtiled CU; excluded from ModelSim.",
}

LEGACY_PREFIXES = (
    "01_capi_integration/accelerator_rtl/cu_control/cu_helloAFU/",
    "01_capi_integration/accelerator_rtl/cu_control/cu_tutorial/",
    "01_capi_integration/accelerator_rtl/cu_control/cu_mmtiled/port/",
)

MONITOR_TB = (
    "01_capi_integration/accelerator_verification/rtl/"
    "accelerator_verification_tb.sv"
)

DECLARATION_RE = re.compile(
    r"\b(package|module|interface)\s+(?:automatic\s+)?"
    r"([A-Za-z_][A-Za-z0-9_$]*)"
)
RTL_SUFFIXES = {".sv", ".v", ".vhd", ".vhdl"}


def fail(message):
    print(f"FAIL {message}", file=sys.stderr)
    raise SystemExit(1)


def relative(path):
    return path.resolve().relative_to(REPO_ROOT).as_posix()


def read_manifest(name):
    path = MANIFEST_ROOT / f"{name}.f"
    if not path.is_file():
        fail(f"missing manifest: {relative(path)}")

    sources = []
    for line_number, raw_line in enumerate(path.read_text().splitlines(), 1):
        source = raw_line.strip()
        if not source or source.startswith("#"):
            continue
        if any(character in source for character in "*?[]$"):
            fail(f"{relative(path)}:{line_number}: wildcard is not allowed")
        source_relative = Path(source)
        if source_relative.is_absolute() or ".." in source_relative.parts:
            fail(
                f"{relative(path)}:{line_number}: source must stay below "
                f"the repository root: {source}"
            )
        if source in sources:
            fail(f"{relative(path)}:{line_number}: duplicate source {source}")
        source_path = REPO_ROOT / source
        if not source_path.is_file():
            fail(f"{relative(path)}:{line_number}: missing source {source}")
        if source_path.suffix.lower() != ".sv":
            fail(
                f"{relative(path)}:{line_number}: design manifests accept "
                f"SystemVerilog only: {source}"
            )
        if relative(source_path) != source:
            fail(
                f"{relative(path)}:{line_number}: source is not canonical: "
                f"{source}"
            )
        sources.append(source)
    if not sources:
        fail(f"empty manifest: {relative(path)}")
    return sources


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    return re.sub(r"//.*", "", text)


def declarations(path):
    text = strip_comments(path.read_text(errors="replace"))
    return [
        {"kind": kind, "name": name}
        for kind, name in DECLARATION_RE.findall(text)
    ]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verification_unit(source, found_declarations):
    if "/afu_pkgs/" in source or "/global_pkg/" in source or "/pkg/" in source:
        return "package-contracts"
    if "/accelerator_verification/rtl/unit/" in source:
        return "unit-" + source.split("/rtl/unit/", 1)[1].split("/", 1)[0]
    if "/accelerator_verification/rtl/integration/" in source:
        return "integration-" + source.split(
            "/rtl/integration/", 1
        )[1].split("/", 1)[0]
    if "/accelerator_verification/" in source:
        return "rtl-lifecycle"
    if "/afu_control/" in source:
        names = [item["name"] for item in found_declarations]
        return names[0] if len(names) == 1 else Path(source).stem
    if any(source.startswith(prefix) for prefix in LEGACY_PREFIXES):
        return "legacy-" + source.split("/cu_control/", 1)[1].split("/", 1)[0]
    for variant in VARIANTS:
        if f"/cu_{variant}/" in source:
            return f"{variant}-cu"
    return Path(source).stem


def modelsim_sources(variant, script_relative):
    script = REPO_ROOT / script_relative
    sources = []
    for raw_line in script.read_text().splitlines():
        line = raw_line.strip()
        if (
            not line or
            line.startswith("#") or
            not (line.startswith("vlog ") or line.startswith("vcom "))
        ):
            continue
        matches = re.findall(r"(\S+\.(?:sv|v|vhd|vhdl))(?=\s|$)", line)
        for match in matches:
            token = match.replace("$algorithm", variant)
            source_path = (script.parent / token).resolve()
            try:
                source = relative(source_path)
            except ValueError:
                fail(
                    f"{relative(script)} compiles a source outside the "
                    f"repository: {token}"
                )
            if (
                source_path.is_relative_to(RTL_ROOT) or
                source_path.is_relative_to(VERIFICATION_RTL_ROOT)
            ):
                sources.append(source)
            elif source != (
                "01_capi_integration/pslse/afu_driver/verilog/top.v"
            ):
                fail(
                    f"{relative(script)} compiles unmanifested RTL: {source}"
                )
    return sources


def validate_source_sets(manifests):
    for variant, script in VARIANTS.items():
        simulator = modelsim_sources(variant, script)
        expected = (
            manifests[variant] +
            manifests["monitor"] +
            manifests["monitor-capi-bind"]
        )
        if simulator != expected:
            for index, (actual, wanted) in enumerate(
                    zip(simulator, expected), 1):
                if actual != wanted:
                    fail(
                        f"{variant} ModelSim source {index}: "
                        f"{actual} != {wanted}"
                    )
            fail(
                f"{variant} ModelSim source count "
                f"{len(simulator)} != {len(expected)}"
            )
        print(
            f"PASS source_set {variant} "
            f"files={len(expected)} modelsim=exact"
        )

    synth_root = (
        REPO_ROOT / "01_capi_integration/accelerator_synth"
    )
    synth_script = synth_root / "capi-precis.tcl"
    synth = synth_script.read_text()
    if "add_accelerator_manifest" not in synth:
        fail("Quartus does not load the ordered accelerator manifest")
    for path in sorted(synth_root.rglob("*.tcl")):
        if path.name == "accelerator_sources.tcl":
            continue
        for line_number, raw_line in enumerate(path.read_text().splitlines(), 1):
            line = raw_line.strip()
            if (
                line.startswith("#") or
                not any(
                    root in line
                    for root in ("accelerator_rtl", "accelerator_verification")
                )
            ):
                continue
            if "glob" in line or re.search(
                r"set_global_assignment\s+-name\s+"
                r"(?:SYSTEMVERILOG|VERILOG|VHDL)_FILE",
                line,
            ):
                fail(
                    f"{relative(path)}:{line_number}: accelerator RTL "
                    "must be loaded through the manifest"
                )
    synth_makefile = (synth_root / "Makefile").read_text()
    if "$(wildcard" in synth_makefile:
        fail("synthesis Makefile still discovers sources by wildcard")
    for required in ("ACCEL_MANIFEST", "$(ACCEL_MANIFEST)"):
        if required not in synth_makefile:
            fail(f"synthesis Makefile is missing {required}")
    tclsh = shutil.which("tclsh")
    if not tclsh:
        fail("tclsh is required to validate the Quartus manifest loader")
    test_script = SCRIPT.with_name("test_accelerator_sources.tcl")
    try:
        subprocess.run(
            [tclsh, str(test_script), str(REPO_ROOT)],
            check=True,
        )
    except subprocess.CalledProcessError:
        fail("Quartus manifest loader regression failed")

    for variant in VARIANTS:
        make_environment = os.environ.copy()
        for variable in ("MAKEFLAGS", "MAKELEVEL", "MFLAGS"):
            make_environment.pop(variable, None)
        try:
            result = subprocess.run(
                [
                    "make",
                    "-s",
                    "--no-print-directory",
                    "-C",
                    str(synth_root),
                    f"CU_ALGORITHM={variant}",
                    "print-accelerator-sources",
                ],
                check=True,
                capture_output=True,
                env=make_environment,
                text=True,
            )
        except subprocess.CalledProcessError:
            fail(f"Quartus Make source-list regression failed: {variant}")
        make_sources = [
            relative(synth_root / line)
            for line in result.stdout.splitlines()
            if line
        ]
        if make_sources != manifests[variant]:
            for index, (actual, expected) in enumerate(
                    zip(make_sources, manifests[variant]), 1):
                if actual != expected:
                    fail(
                        f"Quartus Make source {index} differs for {variant}: "
                        f"{actual} != {expected}"
                    )
            fail(
                f"Quartus Make source count differs for {variant}: "
                f"{len(make_sources)} != {len(manifests[variant])}"
            )
    print("PASS source_set quartus=manifest make=exact")


def build_inventory(manifests):
    memberships = defaultdict(list)
    for manifest_name, sources in manifests.items():
        for index, source in enumerate(sources):
            memberships[source].append({
                "manifest": manifest_name,
                "order": index,
            })
    memberships[MONITOR_TB].append({
        "manifest": "monitor-testbench",
        "order": 0,
    })

    discovered = sorted({
        relative(path)
        for root in (RTL_ROOT, VERIFICATION_RTL_ROOT)
        for path in root.rglob("*")
        if path.is_file() and path.suffix.lower() in RTL_SUFFIXES
    })
    files = []
    unexpected = []
    for source in discovered:
        path = REPO_ROOT / source
        if source in QUARANTINED:
            status = "quarantined"
            evidence = QUARANTINED[source]
        elif source in memberships:
            status = "active"
            evidence = ", ".join(
                item["manifest"] for item in memberships[source]
            )
        elif source.startswith((
            "01_capi_integration/accelerator_verification/rtl/unit/",
            "01_capi_integration/accelerator_verification/rtl/integration/",
        )):
            status = "active"
            if "/rtl/unit/" in source:
                kind = "unit"
                suite = source.split("/rtl/unit/", 1)[1].split("/", 1)[0]
                suite_root = VERIFICATION_RTL_ROOT / kind / suite
            else:
                kind = "integration"
                tail = source.split("/rtl/integration/", 1)[1]
                if "/" in tail:
                    suite = tail.split("/", 1)[0]
                    suite_root = VERIFICATION_RTL_ROOT / kind / suite
                else:
                    suite = "capi"
                    suite_root = VERIFICATION_RTL_ROOT / kind
            runners = list(suite_root.glob("run_*.py"))
            scenarios = list(suite_root.glob("*scenarios*.json"))
            coverage = list(suite_root.glob("*coverage*.json"))
            if len(runners) != 1 or not scenarios or not coverage:
                fail(
                    f"{kind} testbench lacks executable evidence: "
                    f"{relative(suite_root)}"
                )
            memberships[source].append({
                "manifest": f"{kind}-{suite}",
                "order": 0,
            })
            evidence = f"executable {kind} testbench: {suite}"
        elif source.startswith(LEGACY_PREFIXES):
            status = "legacy-supported"
            evidence = "Classified legacy tree; excluded from modern manifests."
        else:
            unexpected.append(source)
            continue

        found_declarations = declarations(path)
        kind = "bind" if source.endswith("_bind.sv") else "rtl"
        if found_declarations:
            kinds = sorted({item["kind"] for item in found_declarations})
            kind = kinds[0] if len(kinds) == 1 else "multi-declaration"
        files.append({
            "path": source,
            "status": status,
            "kind": kind,
            "declarations": found_declarations,
            "sha256": sha256(path),
            "verification_unit": verification_unit(
                source, found_declarations
            ),
            "build_membership": memberships[source],
            "evidence": evidence,
        })

    if unexpected:
        fail("unclassified RTL: " + ", ".join(unexpected))
    if set(QUARANTINED) - set(discovered):
        fail(
            "missing quarantined RTL: " +
            ", ".join(sorted(set(QUARANTINED) - set(discovered)))
        )

    counts = defaultdict(int)
    declaration_counts = defaultdict(lambda: defaultdict(int))
    declaration_count = 0
    for item in files:
        counts[item["status"]] += 1
        declaration_count += len(item["declarations"])
        for declaration in item["declarations"]:
            declaration_counts[item["status"]][declaration["kind"]] += 1

    design_sources = {
        source
        for variant in VARIANTS
        for source in manifests[variant]
    }
    modern_design_counts = defaultdict(int)
    for item in files:
        if item["path"] in design_sources:
            for declaration in item["declarations"]:
                modern_design_counts[declaration["kind"]] += 1
    expected_design_counts = {"module": 44, "package": 13}
    if dict(sorted(modern_design_counts.items())) != expected_design_counts:
        fail(
            "modern declaration count changed: "
            f"{dict(sorted(modern_design_counts.items()))} != "
            f"{expected_design_counts}"
        )

    expected_legacy_counts = {"module": 25, "package": 5}
    actual_legacy_counts = dict(sorted(
        declaration_counts["legacy-supported"].items()
    ))
    if actual_legacy_counts != expected_legacy_counts:
        fail(
            f"legacy declaration count changed: {actual_legacy_counts} != "
            f"{expected_legacy_counts}"
        )

    return {
        "schema_version": 2,
        "rtl_roots": [
            relative(RTL_ROOT),
            relative(VERIFICATION_RTL_ROOT),
        ],
        "generated_by": relative(SCRIPT),
        "summary": {
            "files": len(files),
            "declarations": declaration_count,
            "status_counts": dict(sorted(counts.items())),
            "declaration_status_counts": {
                status: dict(sorted(kind_counts.items()))
                for status, kind_counts in sorted(declaration_counts.items())
            },
            "modern_design_declarations": expected_design_counts,
        },
        "files": files,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Validate CAPI-Precis RTL manifests and inventory"
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="rewrite the deterministic version-controlled inventory",
    )
    args = parser.parse_args()

    manifests = {
        name: read_manifest(name)
        for name in (*VARIANTS, "monitor", "monitor-capi-bind")
    }
    for source in QUARANTINED:
        for manifest_name, sources in manifests.items():
            if source in sources:
                fail(f"quarantined source {source} is in {manifest_name}")

    validate_source_sets(manifests)
    inventory = build_inventory(manifests)
    serialized = json.dumps(inventory, indent=2) + "\n"

    if args.write:
        INVENTORY_PATH.write_text(serialized)
        print(f"WROTE {relative(INVENTORY_PATH)}")
    elif not INVENTORY_PATH.is_file():
        fail(f"missing inventory: {relative(INVENTORY_PATH)}; run --write")
    elif INVENTORY_PATH.read_text() != serialized:
        fail(
            "RTL inventory is stale; review changes and run "
            "01_capi_integration/accelerator_verification/rtl/"
            "scripts/verify_manifests.py --write"
        )

    summary = inventory["summary"]
    counts = summary["status_counts"]
    print(
        "PASS rtl_inventory "
        f"files={summary['files']} declarations={summary['declarations']} "
        f"active={counts.get('active', 0)} "
        f"legacy={counts.get('legacy-supported', 0)} "
        f"quarantined={counts.get('quarantined', 0)}"
    )


if __name__ == "__main__":
    main()
