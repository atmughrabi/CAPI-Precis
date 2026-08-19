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
BUILD_ROOT = REPO_ROOT / "00_bench/obj/rtl_unit_storage"
RAM = REPO_ROOT / "01_capi_integration/accelerator_rtl/afu_control/ram.sv"
FIFO = REPO_ROOT / "01_capi_integration/accelerator_rtl/afu_control/fifo.sv"
TB = UNIT_ROOT / "storage_tb.sv"
MAIN = UNIT_ROOT / "storage_main.cpp"
SCENARIOS = UNIT_ROOT / "scenarios.json"
COVERAGE_SPEC = UNIT_ROOT / "coverage.json"


def fail(message):
    print(f"FAIL storage_unit {message}", file=sys.stderr)
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
        "-Wno-CMPCONST",
        "-Wno-DECLFILENAME",
        "-Wno-EOFNEWLINE",
        "-Wno-GENUNNAMED",
        "-Wno-TIMESCALEMOD",
        "-Wno-UNSIGNED",
        "-Wno-UNUSEDSIGNAL",
        "-Wno-WIDTHEXPAND",
        "-Wno-WIDTHTRUNC",
        "--top-module",
        "storage_tb",
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
    return run([str(build_dir / "Vstorage_tb")], cwd=build_dir, capture_output=True)


def parse_raw_coverage(path):
    source_paths = (str(RAM), str(FIFO))
    page_names = {"v_line/": "line", "v_branch/": "branch", "v_toggle/": "toggle"}
    totals = {
        metric: {"hit": 0, "found": 0, "zero_records": []}
        for metric in page_names.values()
    }
    for line in path.read_bytes().decode("latin1").splitlines():
        if not any(source_path in line for source_path in source_paths):
            continue
        for marker, metric in page_names.items():
            if f"\x01page\x02{marker}" not in line:
                continue
            count_match = re.search(r"'\s+(\d+)$", line)
            if not count_match:
                fail(f"could not parse {metric} coverage record")
            count = int(count_match.group(1))
            totals[metric]["found"] += 1
            totals[metric]["hit"] += count > 0
            if count == 0:
                object_match = re.search(r"\x01o\x02([^'\x01]+)", line)
                scope_match = re.search(r"\x01h\x02([^']+)'", line)
                if not object_match or not scope_match:
                    fail(f"could not identify zero-count {metric} record")
                signal = object_match.group(1)
                scope = scope_match.group(1)
                totals[metric]["zero_records"].append(f"{scope}:{signal}")
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
    if sum(
        value
        for name, value in scenarios["required_bins"].items()
        if name != "total"
    ) != scenarios["required_bins"]["total"]:
        fail("functional bin denominator changed")
    if scenarios["instances"]["ram"][0] != {
        "width": 1,
        "depth": 1,
        "addr_bits": 1,
    }:
        fail("N=1 RAM scenario changed")
    if scenarios["instances"]["ram"][1]["depth"] != 3:
        fail("non-power-of-two RAM scenario changed")
    if [entry["ratio"] for entry in scenarios["instances"]["mixed_width_ram"]] != [
        4,
        4,
        1,
    ]:
        fail("mixed-width ratio denominator changed")
    if scenarios["instances"]["fifo"] != [
        {"width": 1, "depth": 1, "addr_bits": 1, "headroom": 0},
        {"width": 8, "depth": 5, "addr_bits": 3, "headroom": 3},
        {"width": 8, "depth": 8, "addr_bits": 3, "headroom": 3},
    ]:
        fail("FIFO parameter denominator changed")

    shutil.rmtree(BUILD_ROOT, ignore_errors=True)
    production_build = BUILD_ROOT / "production"
    production_build.mkdir(parents=True)
    compile_test(verilator, [RAM, FIFO], production_build, coverage=True)
    result = run_test(production_build)
    if result.returncode:
        fail("production test failed\n" + result.stdout + result.stderr)
    evidence = re.search(
        r"PASS storage_unit vectors=(\d+) checks=(\d+) bins=(\d+)",
        result.stdout,
    )
    if not evidence:
        fail("production test did not report evidence")
    vectors, checks, bins = map(int, evidence.groups())
    if vectors != scenarios["required_vectors"]:
        fail(f"vectors {vectors} != {scenarios['required_vectors']}")
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
    reachable_coverage = {}
    for metric, values in raw_coverage.items():
        expected_unreachable = sorted(
            entry["record"] for entry in coverage_spec["unreachable"][metric]
        )
        measured_unreachable = sorted(values["zero_records"])
        if measured_unreachable != expected_unreachable:
            fail(
                f"unreachable {metric} set changed: "
                f"{measured_unreachable} != {expected_unreachable}"
            )
        reachable_total = values["found"] - len(expected_unreachable)
        reachable_percent = percent(values["hit"], reachable_total)
        target = coverage_spec["targets"][f"reachable_{metric}_percent"]
        if reachable_percent < target:
            fail(
                f"reachable {metric} coverage {reachable_percent:.2f}% < {target}%"
            )
        reachable_coverage[metric] = {
            "hit": values["hit"],
            "total": reachable_total,
            "percent": reachable_percent,
        }

    ram_text = RAM.read_text()
    fifo_text = FIFO.read_text()
    mutations = [
        (
            "ram-disable-write",
            "ram",
            "ram",
            ram_text,
            "if (we)\n      memory[wr_addr] <= data_in;",
            "if (1'b0 && we)\n      memory[wr_addr] <= data_in;",
        ),
        (
            "ram-read-write-address",
            "ram",
            "ram",
            ram_text,
            "data_out <= memory[rd_addr];",
            "data_out <= memory[wr_addr];",
        ),
        (
            "ram-dual-same-address",
            "ram",
            "ram-2xrd",
            ram_text,
            ".rd_addr (rd_addr2 )",
            ".rd_addr (rd_addr1 )",
        ),
        (
            "mixed-shift-read-lane",
            "ram",
            "mixed",
            ram_text,
            "ram[rd_addr / R][rd_addr % R]",
            "ram[rd_addr / R][(rd_addr + 1) % R]",
        ),
        (
            "mixed-shift-write-lane",
            "ram",
            "mixed",
            ram_text,
            "ram[wr_addr / R][wr_addr % R] <= data_in;",
            "ram[wr_addr / R][(wr_addr + 1) % R] <= data_in;",
        ),
        (
            "fifo-read-empty",
            "fifo",
            "fifo",
            fifo_text,
            "assign ren          = pop && !empty;",
            "assign ren          = pop;",
        ),
        (
            "fifo-write-full",
            "fifo",
            "fifo",
            fifo_text,
            "wen         <= push && !full;",
            "wen         <= push;",
        ),
        (
            "fifo-count-decrement",
            "fifo",
            "fifo",
            fifo_text,
            "count       <= count + 'd1;",
            "count       <= count - 'd1;",
        ),
        (
            "fifo-read-address-decrement",
            "fifo",
            "fifo",
            fifo_text,
            "assign rd_addr_c    = (rd_addr_q == LAST_ADDR) ? 'd0 :\n"
            "        rd_addr_q + 'd1;",
            "assign rd_addr_c    = (rd_addr_q == LAST_ADDR) ? 'd0 :\n"
            "        rd_addr_q - 'd1;",
        ),
        (
            "fifo-late-almost-full",
            "fifo",
            "fifo",
            fifo_text,
            "count >= DEPTH - HEADROOM",
            "count > DEPTH - HEADROOM",
        ),
        (
            "fifo-early-full",
            "fifo",
            "fifo",
            fifo_text,
            "count == DEPTH - 1 && wen_q && ~ren",
            "count == DEPTH - 2 && wen_q && ~ren",
        ),
        (
            "fifo-invert-valid",
            "fifo",
            "fifo",
            fifo_text,
            "assign valid        = !empty;",
            "assign valid        = empty;",
        ),
        (
            "fifo-depth1-address-width",
            "fifo",
            "fifo",
            fifo_text,
            "parameter ADDR_BITS = (DEPTH > 1) ? $clog2(DEPTH) : 1,",
            "parameter ADDR_BITS = (DEPTH > 1) ? $clog2(DEPTH) : 2,",
        ),
        (
            "fifo-disable-write-wrap",
            "fifo",
            "fifo",
            fifo_text,
            "if ( wr_addr == LAST_ADDR )",
            "if ( 1'b0 )",
        ),
        (
            "fifo-disable-read-wrap",
            "fifo",
            "fifo",
            fifo_text,
            "assign rd_addr_c    = (rd_addr_q == LAST_ADDR) ? 'd0 :\n"
            "        rd_addr_q + 'd1;",
            "assign rd_addr_c    = rd_addr_q + 'd1;",
        ),
    ]
    if len(mutations) != len(scenarios["sensitivity"]["mutations"]):
        fail("mutation denominator changed")
    detected = []
    for name, source_kind, diagnostic_kind, source_text, anchor, replacement in mutations:
        if source_text.count(anchor) != 1:
            fail(f"mutation anchor changed: {name}")
        mutated = BUILD_ROOT / f"{name}.sv"
        mutated.write_text(source_text.replace(anchor, replacement).rstrip() + "\n")
        sources = [mutated, FIFO] if source_kind == "ram" else [RAM, mutated]
        mutation_build = BUILD_ROOT / f"mutation-{name}"
        mutation_build.mkdir()
        compile_test(verilator, sources, mutation_build, coverage=False)
        mutation_result = run_test(mutation_build)
        if mutation_result.returncode == 0:
            fail(f"mutation was not detected: {name}")
        diagnostic = mutation_result.stdout + mutation_result.stderr
        if (
            "storage mismatch" not in diagnostic
            or f"instance={diagnostic_kind}" not in diagnostic
        ):
            fail(f"mutation failed for the wrong reason: {name}\n{diagnostic}")
        detected.append(name)

    summary = {
        "schema_version": 1,
        "family": "storage",
        "result": "pass",
        "vectors": vectors,
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
        "reachable_coverage": reachable_coverage,
        "not_applicable": coverage_spec["not_applicable"],
        "unreachable": coverage_spec["unreachable"],
        "mutations_detected": detected,
        "reproduction": "python3 01_capi_integration/accelerator_verification/rtl/unit/storage/run_storage.py",
    }
    (production_build / "summary.json").write_text(
        json.dumps(summary, indent=2) + "\n"
    )
    coverage_text = " ".join(
        f"{metric}={percent(values['hit'], values['found']):.2f}%"
        for metric, values in raw_coverage.items()
    )
    reachable_text = " ".join(
        f"reachable_{metric}={values['percent']:.2f}%"
        for metric, values in reachable_coverage.items()
    )
    print("OWNERS:storage")
    print(
        f"PASS storage_unit vectors={vectors} checks={checks} bins={bins}/"
        f"{scenarios['required_bins']['total']} {coverage_text} {reachable_text} "
        f"mutations={len(detected)}/{len(mutations)}"
    )


if __name__ == "__main__":
    main()
