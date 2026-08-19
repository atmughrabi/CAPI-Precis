#!/usr/bin/env python3

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


SCRIPT = Path(__file__).resolve()
UNIT_ROOT = SCRIPT.parent
REPO_ROOT = SCRIPT.parents[5]
BUILD_ROOT = REPO_ROOT / "00_bench/obj/rtl_unit_parity"
DUT = REPO_ROOT / "01_capi_integration/accelerator_rtl/afu_control/parity.sv"
TB = UNIT_ROOT / "parity_tb.sv"
MAIN = UNIT_ROOT / "parity_main.cpp"
SCENARIOS = UNIT_ROOT / "scenarios.json"
COVERAGE_SPEC = UNIT_ROOT / "coverage.json"


def fail(message):
    print(f"FAIL parity_unit {message}", file=sys.stderr)
    raise SystemExit(1)


def run(command, **kwargs):
    return subprocess.run(command, check=False, text=True, **kwargs)


def verilator_version(verilator):
    result = run([verilator, "--version"], capture_output=True)
    if result.returncode:
        return 0
    match = re.search(r"Verilator\s+(\d+)", result.stdout)
    return int(match.group(1)) if match else 0


def compile_test(verilator, source, build_dir, coverage):
    command = [
        verilator,
        "--cc",
        "--exe",
        "--build",
        "--timing",
        "--assert",
        "-Wall",
        "-Wno-ASCRANGE",
        "-Wno-DECLFILENAME",
        "-Wno-EOFNEWLINE",
        "-Wno-UNUSEDSIGNAL",
        "-Wno-WIDTHEXPAND",
        "-Wno-WIDTHTRUNC",
        "--top-module",
        "parity_tb",
        "--Mdir",
        str(build_dir),
    ]
    if coverage:
        command.extend(["--coverage-line", "--coverage-toggle"])
    command.extend([str(source), str(TB), str(MAIN)])
    result = run(command, capture_output=True)
    if result.returncode:
        fail("compile failed\n" + result.stdout + result.stderr)


def run_test(build_dir):
    executable = build_dir / "Vparity_tb"
    result = run(
        [str(executable)],
        cwd=build_dir,
        capture_output=True,
    )
    return result


def parse_toggle_coverage(path):
    found = 0
    hit = 0
    scopes = {}
    marker = "\x01page\x02v_toggle/"
    for line in path.read_bytes().decode("latin1").splitlines():
        if str(DUT) not in line or marker not in line:
            continue
        match = re.search(r"'\s+(\d+)$", line)
        scope_match = re.search(r"\x01h\x02([^']+)'", line)
        if not match or not scope_match:
            fail("could not parse toggle coverage record")
        found += 1
        hit += int(match.group(1)) > 0
        scope = scope_match.group(1)
        scopes[scope] = scopes.get(scope, 0) + 1
    if found == 0:
        fail("DUT toggle coverage contains no instrumented points")
    expected_scopes = {
        "TOP.parity_tb.parity_1": 3,
        "TOP.parity_tb.parity_8": 10,
        "TOP.parity_tb.parity_17": 19,
        "TOP.parity_tb.parity_64": 66,
        "TOP.parity_tb.parity_65": 67,
        "TOP.parity_tb.parity_dw2": 131,
        "TOP.parity_tb.parity_dw4": 261,
    }
    if scopes != expected_scopes:
        fail(f"toggle coverage scope denominator changed: {scopes}")
    return hit, found


def assert_no_procedural_coverage(path):
    contents = path.read_bytes().decode("latin1")
    for page in ("v_line/", "v_branch/"):
        marker = f"\x01page\x02{page}"
        if any(str(DUT) in line and marker in line for line in contents.splitlines()):
            fail(f"DUT unexpectedly contains {page.rstrip('/')} coverage points")


def percent(hit, found):
    return 0.0 if found == 0 else (100.0 * hit / found)


def main():
    verilator = os.environ.get("VERILATOR", "verilator")
    required = os.environ.get("RTL_VERIFICATION_REQUIRED") == "1"
    if not shutil.which(verilator) or verilator_version(verilator) < 5:
        if required:
            fail("Verilator 5 or newer is required")
        print("SKIP parity_unit: install Verilator 5 or set RTL_VERIFICATION_REQUIRED=1")
        return
    verilator_path = Path(shutil.which(verilator))
    coverage_tool = os.environ.get(
        "VERILATOR_COVERAGE",
        str(verilator_path.with_name("verilator_coverage")),
    )
    if not Path(coverage_tool).is_file():
        fail("verilator_coverage is required")

    scenarios = json.loads(SCENARIOS.read_text())
    coverage_spec = json.loads(COVERAGE_SPEC.read_text())
    if scenarios["instances"] != {
        "parity_bits": [1, 8, 17, 64, 65],
        "double_words": [2, 4],
    }:
        fail("scenario instance set changed")
    if scenarios["stimulus"]["deterministic_samples"] != 1024:
        fail("deterministic sample denominator changed")
    bin_components = (
        scenarios["required_bins"]["parity_modes"] +
        scenarios["required_bins"]["data_parity_classes_by_width"] +
        scenarios["required_bins"]["doubleword_lane_parity_classes"] +
        scenarios["required_bins"]["boundary_classes"]
    )
    if bin_components != scenarios["required_bins"]["total"]:
        fail("scenario bin denominator changed")

    shutil.rmtree(BUILD_ROOT, ignore_errors=True)
    production_build = BUILD_ROOT / "production"
    production_build.mkdir(parents=True)
    compile_test(verilator, DUT, production_build, coverage=True)
    production_result = run_test(production_build)
    if production_result.returncode:
        fail(
            "production test failed\n" +
            production_result.stdout +
            production_result.stderr
        )
    match = re.search(
        r"PASS parity_unit vectors=(\d+) bins=(\d+)",
        production_result.stdout,
    )
    if not match:
        fail("production test did not report evidence")
    vectors, bins = map(int, match.groups())
    expected_vectors = 4 * 2 + 256 * 2 + 1024
    if vectors != expected_vectors:
        fail(f"vectors {vectors} != {expected_vectors}")
    if bins != scenarios["required_bins"]["total"]:
        fail(f"functional bins {bins} != {scenarios['required_bins']['total']}")

    coverage_data = production_build / "coverage.dat"
    coverage_info = production_build / "coverage.info"
    if not coverage_data.is_file():
        fail("coverage.dat was not produced")
    coverage_result = run(
        [coverage_tool, "--write-info", str(coverage_info), str(coverage_data)],
        capture_output=True,
    )
    if coverage_result.returncode or not coverage_info.is_file():
        fail("could not convert coverage data")
    toggle_hit, toggle_found = parse_toggle_coverage(coverage_data)
    assert_no_procedural_coverage(coverage_data)
    toggle_percent = percent(toggle_hit, toggle_found)
    if toggle_percent < coverage_spec["targets"]["reachable_toggle_percent"]:
        fail(
            f"toggle coverage {toggle_percent:.2f}% < "
            f"{coverage_spec['targets']['reachable_toggle_percent']}%"
        )

    source_text = DUT.read_text()
    mutations = [
        (
            "parity-output",
            "assign par = ^{data, odd};",
            "assign par = ~^{data, odd};",
        ),
        (
            "parity-ignore-odd",
            "assign par = ^{data, odd};",
            "assign par = ^data;",
        ),
        (
            "dw-parity-output",
            "assign par[i] = ^{data[64*i +: 64], odd};",
            "assign par[i] = ~^{data[64*i +: 64], odd};",
        ),
        (
            "dw-parity-lane-order",
            "assign par[i] = ^{data[64*i +: 64], odd};",
            "assign par[DOUBLE_WORDS-1-i] = ^{data[64*i +: 64], odd};",
        ),
    ]
    expected_diagnostics = {
        "parity-output": "instance=parity-bits-",
        "parity-ignore-odd": "instance=parity-bits-",
        "dw-parity-output": "instance=dw-parity-",
        "dw-parity-lane-order": "instance=dw-parity-",
    }
    if len(mutations) != len(scenarios["sensitivity"]["mutations"]):
        fail("mutation denominator changed")
    detected_mutations = []
    for name, original, replacement in mutations:
        if source_text.count(original) != 1:
            fail(f"mutation anchor changed: {name}")
        mutated_source = BUILD_ROOT / f"{name}.sv"
        mutated_source.write_text(
            source_text.replace(original, replacement).rstrip() + "\n"
        )
        mutation_build = BUILD_ROOT / f"mutation-{name}"
        mutation_build.mkdir()
        compile_test(verilator, mutated_source, mutation_build, coverage=False)
        mutation_result = run_test(mutation_build)
        if mutation_result.returncode == 0:
            fail(f"mutation was not detected: {name}")
        diagnostic = mutation_result.stdout + mutation_result.stderr
        if (
            "parity mismatch" not in diagnostic or
            expected_diagnostics[name] not in diagnostic
        ):
            fail(f"mutation failed for the wrong reason: {name}")
        detected_mutations.append(name)

    summary = {
        "schema_version": 1,
        "family": "parity",
        "result": "pass",
        "vectors": vectors,
        "functional_bins": {
            "hit": bins,
            "total": scenarios["required_bins"]["total"],
            "percent": percent(bins, scenarios["required_bins"]["total"]),
        },
        "assertion_goals": {
            "hit": len(detected_mutations),
            "total": len(mutations),
            "percent": 100.0,
        },
        "code_coverage": {
            "toggle_hit": toggle_hit,
            "toggle_found": toggle_found,
            "toggle_percent": toggle_percent,
            "statement": "not_applicable",
            "branch": "not_applicable",
            "fsm_state": "not_applicable",
            "fsm_transition": "not_applicable",
        },
        "mutations_detected": detected_mutations,
        "reproduction": "make rtl-unit-parity",
    }
    (production_build / "summary.json").write_text(
        json.dumps(summary, indent=2) + "\n"
    )
    print(
        f"PASS parity_unit vectors={vectors} bins={bins}/"
        f"{scenarios['required_bins']['total']} "
        f"toggle={toggle_percent:.2f}% "
        f"mutations={len(detected_mutations)}/{len(mutations)}"
    )


if __name__ == "__main__":
    main()
