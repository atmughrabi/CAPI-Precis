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
BUILD_ROOT = REPO_ROOT / "00_bench/obj/rtl_unit_reset"
RESET_FILTER = REPO_ROOT / "01_capi_integration/accelerator_rtl/afu_control/reset_filter.sv"
RESET_CONTROL = REPO_ROOT / "01_capi_integration/accelerator_rtl/afu_control/reset_control.sv"
TB = UNIT_ROOT / "reset_tb.sv"
MAIN = UNIT_ROOT / "reset_main.cpp"
SCENARIOS = UNIT_ROOT / "scenarios.json"
COVERAGE_SPEC = UNIT_ROOT / "coverage.json"


def fail(message):
    print(f"FAIL reset_unit {message}", file=sys.stderr)
    raise SystemExit(1)


def run(command, **kwargs):
    return subprocess.run(command, check=False, text=True, **kwargs)


def verilator_version(verilator):
    result = run([verilator, "--version"], capture_output=True)
    match = re.search(r"Verilator\s+(\d+)", result.stdout)
    return int(match.group(1)) if result.returncode == 0 and match else 0


def compile_test(verilator, sources, build_dir, coverage):
    command = [
        verilator,
        "--cc",
        "--exe",
        "--build",
        "--timing",
        "--assert",
        "-Wall",
        "-Wno-ASCRANGE",
        "-Wno-BLKSEQ",
        "-Wno-DECLFILENAME",
        "-Wno-EOFNEWLINE",
        "-Wno-TIMESCALEMOD",
        "-Wno-UNUSEDSIGNAL",
        "-Wno-WIDTHEXPAND",
        "-Wno-WIDTHTRUNC",
        "--top-module",
        "reset_tb",
        "--Mdir",
        str(build_dir),
    ]
    if coverage:
        command.extend(["--coverage-line", "--coverage-toggle"])
    command.extend([str(source) for source in sources])
    command.extend([str(TB), str(MAIN)])
    result = run(command, capture_output=True)
    if result.returncode:
        fail("compile failed\n" + result.stdout + result.stderr)


def run_test(build_dir):
    return run([str(build_dir / "Vreset_tb")], cwd=build_dir, capture_output=True)


def parse_raw_coverage(path):
    source_paths = (str(RESET_FILTER), str(RESET_CONTROL))
    page_names = {"v_line/": "line", "v_branch/": "branch", "v_toggle/": "toggle"}
    totals = {metric: {"hit": 0, "found": 0} for metric in page_names.values()}
    for line in path.read_bytes().decode("latin1").splitlines():
        if not any(source_path in line for source_path in source_paths):
            continue
        for marker, metric in page_names.items():
            if f"\x01page\x02{marker}" not in line:
                continue
            count_match = re.search(r"'\s+(\d+)$", line)
            if not count_match:
                fail(f"could not parse {metric} coverage record")
            totals[metric]["found"] += 1
            totals[metric]["hit"] += int(count_match.group(1)) > 0
            break
    for metric, values in totals.items():
        if values["found"] == 0:
            fail(f"DUT {metric} coverage contains no instrumented points")
    return totals


def percent(hit, total):
    return 0.0 if total == 0 else 100.0 * hit / total


def main():
    verilator = os.environ.get("VERILATOR", "verilator")
    if not shutil.which(verilator) or verilator_version(verilator) < 5:
        fail("Verilator 5 or newer is required")
    verilator_path = Path(shutil.which(verilator))
    coverage_tool = Path(
        os.environ.get(
            "VERILATOR_COVERAGE",
            str(verilator_path.with_name("verilator_coverage")),
        )
    )
    if not coverage_tool.is_file():
        fail("verilator_coverage is required")

    scenarios = json.loads(SCENARIOS.read_text())
    coverage_spec = json.loads(COVERAGE_SPEC.read_text())
    if scenarios["instances"] != {
        "reset_filter_pulse_hold": [1, 2, 3, 5],
        "reset_control_external_resets": [1, 3],
    }:
        fail("scenario instance denominator changed")
    if sum(
        value
        for name, value in scenarios["required_bins"].items()
        if name != "total"
    ) != scenarios["required_bins"]["total"]:
        fail("functional bin denominator changed")

    shutil.rmtree(BUILD_ROOT, ignore_errors=True)
    production_build = BUILD_ROOT / "production"
    production_build.mkdir(parents=True)
    compile_test(
        verilator,
        [RESET_FILTER, RESET_CONTROL],
        production_build,
        coverage=True,
    )
    result = run_test(production_build)
    if result.returncode:
        fail("production test failed\n" + result.stdout + result.stderr)
    evidence = re.search(r"PASS reset_unit checks=(\d+) bins=(\d+)", result.stdout)
    if not evidence:
        fail("production test did not report evidence")
    checks, bins = map(int, evidence.groups())
    if checks != scenarios["required_checks"]:
        fail(f"checks {checks} != {scenarios['required_checks']}")
    if bins != scenarios["required_bins"]["total"]:
        fail(f"functional bins {bins} != {scenarios['required_bins']['total']}")

    coverage_data = production_build / "coverage.dat"
    coverage_info = production_build / "coverage.info"
    if not coverage_data.is_file():
        fail("coverage.dat was not produced")
    conversion = run(
        [str(coverage_tool), "--write-info", str(coverage_info), str(coverage_data)],
        capture_output=True,
    )
    if conversion.returncode or not coverage_info.is_file():
        fail("could not convert coverage data")
    raw_coverage = parse_raw_coverage(coverage_data)
    for metric, values in raw_coverage.items():
        expected = coverage_spec["raw_dut_denominators"][metric]
        if values["found"] != expected:
            fail(
                f"raw {metric} denominator {values['found']} != {expected}; "
                "update only after reviewing an RTL or instrumentation change"
            )
        measured = percent(values["hit"], values["found"])
        target = coverage_spec["targets"][f"raw_{metric}_percent"]
        if measured < target:
            fail(f"raw {metric} coverage {measured:.2f}% < {target}%")

    filter_text = RESET_FILTER.read_text()
    control_text = RESET_CONTROL.read_text()
    mutations = [
        (
            "filter-ignore-enable",
            "filter",
            filter_text,
            "rstn_reg <= {enable,rstn_reg[0:PULSE_HOLD-2]};",
            "rstn_reg <= {1'b1,rstn_reg[0:PULSE_HOLD-2]};",
        ),
        (
            "filter-P1-stuck-low",
            "filter",
            filter_text,
            "rstn_reg <= enable;",
            "rstn_reg <= 1'b0;",
        ),
        (
            "filter-P1-async-load-one",
            "filter",
            filter_text,
            "rstn_reg <= 1'b0;",
            "rstn_reg <= 1'b1;",
        ),
        (
            "filter-first-stage-output",
            "filter",
            filter_text,
            "assign rstn_filtered = rstn_reg[PULSE_HOLD-1];",
            "assign rstn_filtered = rstn_reg[0];",
        ),
        (
            "filter-async-load-ones",
            "filter",
            filter_text,
            "rstn_reg <= {PULSE_HOLD{1'b0}};",
            "rstn_reg <= {PULSE_HOLD{1'b1}};",
        ),
        (
            "control-combine-or",
            "control",
            control_text,
            "assign sys_rstn = &filtered_rstn;",
            "assign sys_rstn = |filtered_rstn;",
        ),
        (
            "control-external-latency",
            "control",
            control_text,
            "reset_filter rf_extern (",
            "reset_filter #(.PULSE_HOLD(3)) rf_extern (",
        ),
        (
            "control-disconnect-system-reset",
            "control",
            control_text,
            ".rstn_raw(sys_rstn),",
            ".rstn_raw(1'b1),",
        ),
        (
            "control-system-latency",
            "control",
            control_text,
            "reset_filter rf_sys (",
            "reset_filter #(.PULSE_HOLD(3)) rf_sys (",
        ),
    ]
    if len(mutations) != len(scenarios["sensitivity"]["mutations"]):
        fail("mutation denominator changed")
    detected = []
    for name, source_kind, source_text, anchor, replacement in mutations:
        if source_text.count(anchor) != 1:
            fail(f"mutation anchor changed: {name}")
        mutated = BUILD_ROOT / f"{name}.sv"
        mutated.write_text(source_text.replace(anchor, replacement).rstrip() + "\n")
        sources = (
            [mutated, RESET_CONTROL]
            if source_kind == "filter"
            else [RESET_FILTER, mutated]
        )
        mutation_build = BUILD_ROOT / f"mutation-{name}"
        mutation_build.mkdir()
        compile_test(verilator, sources, mutation_build, coverage=False)
        mutation_result = run_test(mutation_build)
        if mutation_result.returncode == 0:
            fail(f"mutation was not detected: {name}")
        diagnostic = mutation_result.stdout + mutation_result.stderr
        expected_instance = "instance=filter" if source_kind == "filter" else "instance=control"
        if "reset mismatch" not in diagnostic or expected_instance not in diagnostic:
            fail(f"mutation failed for the wrong reason: {name}\n{diagnostic}")
        detected.append(name)

    summary = {
        "schema_version": 1,
        "family": "reset",
        "result": "pass",
        "checks": checks,
        "functional_bins": {
            "hit": bins,
            "total": scenarios["required_bins"]["total"],
            "percent": percent(bins, scenarios["required_bins"]["total"]),
        },
        "assertion_goals": {
            "hit": len(detected),
            "total": len(mutations),
            "percent": percent(len(detected), len(mutations)),
        },
        "code_coverage": {
            metric: {
                **values,
                "percent": percent(values["hit"], values["found"]),
            }
            for metric, values in raw_coverage.items()
        },
        "not_applicable": coverage_spec["not_applicable"],
        "unreachable": coverage_spec["unreachable"],
        "mutations_detected": detected,
        "reproduction": "python3 01_capi_integration/accelerator_verification/rtl/unit/reset/run_reset.py",
    }
    (production_build / "summary.json").write_text(
        json.dumps(summary, indent=2) + "\n"
    )
    coverage_text = " ".join(
        f"{metric}={percent(values['hit'], values['found']):.2f}%"
        for metric, values in raw_coverage.items()
    )
    print("OWNERS:reset")
    print(
        f"PASS reset_unit checks={checks} bins={bins}/"
        f"{scenarios['required_bins']['total']} {coverage_text} "
        f"mutations={len(detected)}/{len(mutations)}"
    )


if __name__ == "__main__":
    main()
