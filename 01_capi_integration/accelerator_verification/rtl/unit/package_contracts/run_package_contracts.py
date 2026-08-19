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
VERIFICATION_ROOT = SCRIPT.parents[2]
MANIFEST_ROOT = VERIFICATION_ROOT / "manifests"
BUILD_ROOT = REPO_ROOT / "00_bench/obj/rtl_unit_package_contracts"
TB = UNIT_ROOT / "package_contract_tb.sv"
MAIN = UNIT_ROOT / "package_contract_main.cpp"
C_TEST = UNIT_ROOT / "package_contracts.c"
SCENARIOS = UNIT_ROOT / "scenarios.json"
COVERAGE_SPEC = UNIT_ROOT / "coverage.json"
VARIANTS = ("memcpy", "memcpy-tutorial", "mmtiled")


def fail(message):
    print(f"FAIL package_contracts {message}", file=sys.stderr)
    raise SystemExit(1)


def run(command, **kwargs):
    return subprocess.run(command, check=False, text=True, **kwargs)


def source_list(variant):
    sources = []
    for raw_line in (MANIFEST_ROOT / f"{variant}.f").read_text().splitlines():
        source = raw_line.strip()
        if not source or source.startswith("#"):
            continue
        sources.append(REPO_ROOT / source)
        if len(sources) == 7:
            break
    if len(sources) != 7:
        fail(f"{variant} package source list changed")
    return sources


def compile_test(verilator, sources, build_dir, coverage, defines=()):
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
        "-Wno-IMPORTSTAR",
        "-Wno-UNUSEDSIGNAL",
        "-Wno-UNUSEDPARAM",
        "-Wno-WIDTHEXPAND",
        "-Wno-WIDTHTRUNC",
        "--top-module",
        "package_contract_tb",
        "--Mdir",
        str(build_dir),
    ]
    if coverage:
        command.extend(["--coverage-line", "--coverage-toggle"])
    command.extend(defines)
    command.extend(str(source) for source in sources)
    command.extend([str(TB), str(MAIN)])
    result = run(command, capture_output=True)
    if result.returncode:
        fail("compile failed\n" + result.stdout + result.stderr)


def run_test(build_dir):
    return run(
        [str(build_dir / "Vpackage_contract_tb")],
        cwd=build_dir,
        capture_output=True,
    )


def coverage_points(path, package_sources, allowed_unreachable):
    source_names = {str(source) for source in package_sources}
    counters = {
        "line": [0, 0],
        "branch": [0, 0],
        "toggle": [0, 0],
    }
    for line in path.read_bytes().decode("latin1").splitlines():
        if not any(source in line for source in source_names):
            continue
        match = re.search(r"'\s+(\d+)$", line)
        if not match:
            fail("cannot parse package coverage record")
        count = int(match.group(1))
        file_match = re.search(r"\x01f\x02([^\x01]+)", line)
        line_match = re.search(r"\x01l\x02(\d+)", line)
        if not file_match or not line_match:
            fail("coverage record lacks source location")
        source_path = Path(file_match.group(1))
        line_number = int(line_match.group(1))
        source_line = source_path.read_text().splitlines()[line_number-1].strip()
        for metric, marker in (
            ("line", "\x01page\x02v_line/"),
            ("branch", "\x01page\x02v_branch/"),
            ("toggle", "\x01page\x02v_toggle/"),
        ):
            if marker in line:
                if count == 0 and source_line in allowed_unreachable:
                    break
                counters[metric][1] += 1
                counters[metric][0] += count > 0
                break
    return counters


def percent(hit, total):
    return 0.0 if total == 0 else 100.0 * hit / total


def compile_c_contract():
    output = BUILD_ROOT / "package_contracts_c"
    command = [
        os.environ.get("CC", "gcc"),
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-I" + str(REPO_ROOT / "00_bench/include/capi_utils"),
        "-I" + str(REPO_ROOT / "00_bench/include/algorithms/capi"),
        "-I" + str(REPO_ROOT / "00_bench/include/utils"),
        "-I" + str(REPO_ROOT / "01_capi_integration/libcxl"),
        str(C_TEST),
        "-o",
        str(output),
    ]
    result = run(command, capture_output=True)
    if result.returncode:
        fail("C ABI compile failed\n" + result.stdout + result.stderr)
    result = run([str(output)], capture_output=True)
    if result.returncode:
        fail("C ABI executable failed")


def mutated_sources(variant, name):
    sources = source_list(variant)
    mutation_root = BUILD_ROOT / f"source-{name}"
    mutation_root.mkdir()
    copied = []
    for source in sources:
        destination = mutation_root / source.name
        destination.write_text(source.read_text())
        copied.append(destination)

    if name == "quad-width":
        target = copied[2]
        original = "function logic [0:127] swap_endianness_quad_word"
        replacement = "function logic [0:63] swap_endianness_quad_word"
        expected = "quadword endian"
    elif name == "cabt-default":
        target = copied[3]
        original = "cabt = STRICT;"
        index = target.read_text().rfind(original)
        if index < 0:
            fail("CABT mutation anchor changed")
        text = target.read_text()
        target.write_text(
            (text[:index] + "cabt = SPEC;" + text[index+len(original):]).rstrip() +
            "\n"
        )
        return copied, "CABT default"
    elif name == "wed-byte-order":
        target = copied[3]
        original = "swap_endianness_double_word(in[0:63])"
        replacement = "swap_endianness_double_word(in[64:127])"
        expected = "WED byte mapping"
    else:
        fail(f"unknown mutation: {name}")

    text = target.read_text()
    if text.count(original) != 1:
        fail(f"mutation anchor changed: {name}")
    target.write_text(text.replace(original, replacement).rstrip() + "\n")
    return copied, expected


def main():
    verilator = os.environ.get("VERILATOR", "verilator")
    required = os.environ.get("RTL_VERIFICATION_REQUIRED") == "1"
    verilator_path = shutil.which(verilator)
    if not verilator_path:
        if required:
            fail("Verilator is required")
        print("SKIP package_contracts: install Verilator or set RTL_VERIFICATION_REQUIRED=1")
        return

    scenarios = json.loads(SCENARIOS.read_text())
    coverage_spec = json.loads(COVERAGE_SPEC.read_text())
    if tuple(scenarios["variants"]) != VARIANTS:
        fail("variant denominator changed")
    unreachable = {
        source_line
        for item in coverage_spec["structurally_unreachable"]
        for source_line in item["source_lines"]
    }

    shutil.rmtree(BUILD_ROOT, ignore_errors=True)
    BUILD_ROOT.mkdir(parents=True)
    compile_c_contract()

    summaries = {}
    for variant in VARIANTS:
        build_dir = BUILD_ROOT / variant
        build_dir.mkdir()
        defines = ("-DHAS_CU_ENDIAN",) if variant != "memcpy-tutorial" else ()
        sources = source_list(variant)
        compile_test(verilator, sources, build_dir, coverage=True, defines=defines)
        result = run_test(build_dir)
        if result.returncode:
            fail(f"{variant} failed\n" + result.stdout + result.stderr)
        match = re.search(r"PASS package_contracts checks=(\d+) bins=(\d+)", result.stdout)
        if not match:
            fail(f"{variant} did not report evidence")
        checks, bins = map(int, match.groups())
        expected_bins = scenarios["required_bins"][variant]
        if bins != expected_bins or checks != expected_bins:
            fail(
                f"{variant} checks/bins {checks}/{bins} != "
                f"{expected_bins}/{expected_bins}"
            )
        coverage_data = build_dir / "coverage.dat"
        if not coverage_data.is_file():
            fail(f"{variant} did not produce coverage")
        counters = coverage_points(coverage_data, sources, unreachable)
        line_hit, line_total = counters["line"]
        expected_line_points = scenarios["expected_reachable_line_points"][variant]
        if line_total != expected_line_points:
            fail(
                f"{variant} line denominator {line_total} != "
                f"{expected_line_points}"
            )
        if line_total == 0 or percent(line_hit, line_total) < 100.0:
            fail(
                f"{variant} line coverage "
                f"{line_hit}/{line_total}={percent(line_hit, line_total):.2f}%"
            )
        for metric in ("branch", "toggle"):
            if counters[metric][1] != 0:
                fail(f"{variant} N/A metric now has points: {metric}")
        summaries[variant] = {
            "checks": checks,
            "bins": bins,
            "coverage": counters,
        }

    mutations = {}
    if len(scenarios["mutations"]) != 3:
        fail("mutation denominator changed")
    for name in ("quad-width", "cabt-default", "wed-byte-order"):
        sources, diagnostic = mutated_sources("memcpy", name)
        build_dir = BUILD_ROOT / f"mutation-{name}"
        build_dir.mkdir()
        compile_test(
            verilator,
            sources,
            build_dir,
            coverage=False,
            defines=("-DHAS_CU_ENDIAN",),
        )
        result = run_test(build_dir)
        output = result.stdout + result.stderr
        if result.returncode == 0 or diagnostic not in output:
            fail(f"mutation was not detected correctly: {name}")
        mutations[name] = "detected"

    summary = {
        "schema_version": 1,
        "suite": "package-contracts",
        "result": "pass",
        "variants": summaries,
        "c_abi": "pass",
        "mutations": mutations,
        "reproduction": "make rtl-unit-package-contracts",
    }
    (BUILD_ROOT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    total_bins = sum(item["bins"] for item in summaries.values())
    total_lines = sum(item["coverage"]["line"][1] for item in summaries.values())
    print("OWNERS:package-contracts")
    print(
        f"PASS package_contracts variants=3 bins={total_bins}/{total_bins} "
        f"lines={total_lines}/{total_lines} C_ABI=3/3 "
        f"mutations={len(mutations)}/{len(mutations)}"
    )


if __name__ == "__main__":
    main()
