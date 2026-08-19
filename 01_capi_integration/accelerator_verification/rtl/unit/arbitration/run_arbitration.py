#!/usr/bin/env python3

"""Standalone unit runner for the CAPI-Precis arbitration modules."""

import json
import os
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path


SCRIPT = Path(__file__).resolve()
UNIT_ROOT = SCRIPT.parent
REPO_ROOT = SCRIPT.parents[5]
MANIFEST_ROOT = SCRIPT.parents[2] / "manifests"
BUILD_ROOT = REPO_ROOT / "00_bench/obj/rtl_unit_arbitration"
RTL_ROOT = REPO_ROOT / "01_capi_integration/accelerator_rtl/afu_control"

DUT_SOURCES = (
    RTL_ROOT / "priority_arbiters.sv",
    RTL_ROOT / "fixed_priority_arbiter.sv",
    RTL_ROOT / "round_robin_priority_arbiter.sv",
)
TB = UNIT_ROOT / "arbitration_tb.sv"
MAIN = UNIT_ROOT / "arbitration_main.cpp"
SCENARIOS = UNIT_ROOT / "scenarios.json"
COVERAGE_SPEC = UNIT_ROOT / "coverage.json"

PACKAGE_COUNT = 7
PACKAGE_MANIFEST = "memcpy.f"

# The devices under test are legacy sources that are linted elsewhere; only
# waivers required to elaborate them under -Wall are listed here.
LINT_WAIVERS = (
    "-Wno-ASCRANGE",
    "-Wno-BLKSEQ",
    "-Wno-DECLFILENAME",
    "-Wno-EOFNEWLINE",
    "-Wno-GENUNNAMED",
    "-Wno-IMPORTSTAR",
    "-Wno-UNOPTFLAT",
    "-Wno-UNUSEDPARAM",
    "-Wno-UNUSEDSIGNAL",
    "-Wno-WIDTHEXPAND",
    "-Wno-WIDTHTRUNC",
)

COVERAGE_PAGES = (
    ("line", "\x01page\x02v_line/"),
    ("branch", "\x01page\x02v_branch/"),
    ("toggle", "\x01page\x02v_toggle/"),
)

# The fan-in payload gate follows the delayed grant that caused the buffer pop.
PUBLISH_ANCHOR = "assign publish = grant_latched & submit;"

# The fan-out payload register gains an asynchronous reset; the mutation
# restores the unreset form that leaks a stale payload.
FANOUT_RESET_BLOCK = (
    '  always_ff @(posedge clock or negedge rstn) begin\n'
    '    if(~rstn) begin\n'
    '      for (k = 0; k < NUM_REQUESTS; k++) begin\n'
    '        arbiter_out[k] <= 0;\n'
    '      end\n'
    '    end else begin\n'
    '      arbiter_out <= arbiter_out_latch;\n'
    '    end\n'
    '  end'
)
FANOUT_RESET_REMOVED = (
    '  always_ff @(posedge clock) begin\n'
    '    arbiter_out <= arbiter_out_latch;\n'
    '  end'
)

# name, source basename, occurrence index, original text, replacement text,
# behaviour class, diagnostic substrings that must appear in the failure output
MUTATIONS = (
    (
        "fixed-chain-priority-reversal",
        "priority_arbiters.sv",
        (
            (
                0,
                "assign grants_int[i] = !kills[i] && reqs[i];",
                "assign grants_int[i] = !kills[i] && reqs[p_num_reqs-1-i];",
            ),
            (
                0,
                "assign grants = grants_int & {p_num_reqs{~kin}};",
                "assign grants = {<<{grants_int}} & {p_num_reqs{~kin}};",
            ),
        ),
        "fixed-priority",
        ("class=combinational-arbitration", "instance=vc_FixedArbChain", "check=grants"),
    ),
    (
        "fixed-chain-grant-corruption",
        "priority_arbiters.sv",
        (
            (
                0,
                "assign grants = grants_int & {p_num_reqs{~kin}};",
                "assign grants = reqs & {p_num_reqs{~kin}};",
            ),
        ),
        "fixed-priority",
        ("instance=vc_FixedArb", "check=one-hot-grant"),
    ),
    (
        "variable-priority-reversal",
        "priority_arbiters.sv",
        (
            (
                0,
                "assign priority_int = { {p_num_reqs{1'b0}}, priority_ };",
                "assign priority_int = { {p_num_reqs{1'b0}}, {<<{priority_}} };",
            ),
        ),
        "variable-priority",
        ("instance=vc_VariableArbChain", "check=grants"),
    ),
    (
        "variable-chain-stall-ignored",
        "priority_arbiters.sv",
        (
            (
                0,
                "assign grants\n"
                "    = (grants_int[p_num_reqs-1:0] | grants_int[2*p_num_reqs-1:p_num_reqs])\n"
                "      & {p_num_reqs{~kin}};",
                "assign grants\n"
                "    = (grants_int[p_num_reqs-1:0] | grants_int[2*p_num_reqs-1:p_num_reqs]);",
            ),
        ),
        "variable-priority",
        ("instance=vc_VariableArbChain", "kin=1"),
    ),
    (
        "rr-chain-rotation-hold",
        "priority_arbiters.sv",
        ((0, "assign priority_en = |grants;", "assign priority_en = 1'b0;"),),
        "round-robin-rotation",
        ("instance=vc_RoundRobinArbChain", "check=grants"),
    ),
    (
        "rr-arb-rotation-hold",
        "priority_arbiters.sv",
        ((1, "assign priority_en = |grants;", "assign priority_en = 1'b0;"),),
        "round-robin-rotation",
        ("instance=vc_RoundRobinArb[", "check=grants"),
    ),
    (
        "rr-v2-rotation-hold",
        "priority_arbiters.sv",
        (
            (
                0,
                "assign update_ptr = |grants[p_num_reqs-1:0];",
                "assign update_ptr = 1'b0;",
            ),
        ),
        "round-robin-rotation",
        ("instance=vc_RoundRobinArb_V2", "check=grants"),
    ),
    (
        "rr-v2-grant-blackout-removed",
        "priority_arbiters.sv",
        (
            (
                0,
                "else    grants[p_num_reqs-1:0] <= grant_comb[p_num_reqs-1:0] & ~grants[p_num_reqs-1:0];",
                "else    grants[p_num_reqs-1:0] <= grant_comb[p_num_reqs-1:0];",
            ),
        ),
        "round-robin-rotation",
        ("instance=vc_RoundRobinArb_V2", "check=grants"),
    ),
    (
        "fixed-fanin-payload-reversal",
        "fixed_priority_arbiter.sv",
        (
            (
                0,
                "arbiter_out <= buffer_in[i];",
                "arbiter_out <= buffer_in[NUM_REQUESTS-1-i];",
            ),
        ),
        "wrapper-fan-in",
        (
            "class=wrapper-fan-in",
            "instance=fixed_priority_arbiter_N_input_1_ouput",
            "check=payload",
        ),
    ),
    (
        "fixed-fanin-ready-reversal",
        "fixed_priority_arbiter.sv",
        ((0, "ready[i] <= grant[i];", "ready[i] <= grant[NUM_REQUESTS-1-i];"),),
        "wrapper-fan-in",
        (
            "class=wrapper-fan-in",
            "instance=fixed_priority_arbiter_N_input_1_ouput",
            "check=ready",
        ),
    ),
    (
        "fixed-fanin-stall-ignored",
        "fixed_priority_arbiter.sv",
        ((0, "if (enabled) begin", "if (1'b1) begin"),),
        "wrapper-fan-in",
        ("class=wrapper-fan-in", "instance=fixed_priority_arbiter_N_input_1_ouput"),
    ),
    (
        "fixed-fanout-grant-misalign",
        "fixed_priority_arbiter.sv",
        (
            (
                0,
                "if (grant_latched[i]) begin",
                "if (grant_latched[NUM_REQUESTS-1-i]) begin",
            ),
        ),
        "wrapper-fan-out",
        (
            "class=wrapper-fan-out",
            "instance=fixed_priority_arbiter_1_input_N_ouput",
            "check=payload",
        ),
    ),
    (
        "rr-fanin-payload-reversal",
        "round_robin_priority_arbiter.sv",
        (
            (
                0,
                "arbiter_out <= buffer_in[i];",
                "arbiter_out <= buffer_in[NUM_REQUESTS-1-i];",
            ),
        ),
        "wrapper-fan-in",
        (
            "class=wrapper-fan-in",
            "instance=round_robin_priority_arbiter_N_input_1_ouput",
            "check=payload",
        ),
    ),
    (
        "rr-fanin-enable-delay-removed",
        "round_robin_priority_arbiter.sv",
        ((0, "if (enabled_internal) begin", "if (enabled) begin"),),
        "wrapper-fan-in",
        (
            "class=wrapper-fan-in",
            "instance=round_robin_priority_arbiter_N_input_1_ouput",
        ),
    ),
    (
        "rr-fanout-grant-misalign",
        "round_robin_priority_arbiter.sv",
        (
            (
                0,
                "if (grant_latched[i]) begin",
                "if (grant_latched[NUM_REQUESTS-1-i]) begin",
            ),
        ),
        "wrapper-fan-out",
        (
            "class=wrapper-fan-out",
            "instance=round_robin_priority_arbiter_1_input_N_ouput",
            "check=payload",
        ),
    ),
    (
        "rr-chain-single-rotation-broken",
        "priority_arbiters.sv",
        ((0, "assign priority_next = grants;", "assign priority_next = '0;"),),
        "round-robin-rotation",
        ("instance=vc_RoundRobinArbChain[N=1", "check=grants"),
    ),
    (
        "rr-arb-single-rotation-broken",
        "priority_arbiters.sv",
        ((1, "assign priority_next = grants;", "assign priority_next = '0;"),),
        "round-robin-rotation",
        ("instance=vc_RoundRobinArb[N=1]", "check=grants"),
    ),
    (
        "fixed-fanin-publish-highest-submitter",
        "fixed_priority_arbiter.sv",
        ((0, PUBLISH_ANCHOR, "assign publish = submit;"),),
        "wrapper-fan-in",
        (
            "class=wrapper-fan-in",
            "instance=fixed_priority_arbiter_N_input_1_ouput",
            "check=payload",
        ),
    ),
    (
        "rr-fanin-publish-highest-submitter",
        "round_robin_priority_arbiter.sv",
        ((0, PUBLISH_ANCHOR, "assign publish = submit;"),),
        "wrapper-fan-in",
        (
            "class=wrapper-fan-in",
            "instance=round_robin_priority_arbiter_N_input_1_ouput",
            "check=payload",
        ),
    ),
    (
        "fixed-fanout-reset-removed",
        "fixed_priority_arbiter.sv",
        ((0, FANOUT_RESET_BLOCK, FANOUT_RESET_REMOVED),),
        "wrapper-fan-out",
        (
            "class=wrapper-fan-out",
            "instance=fixed_priority_arbiter_1_input_N_ouput",
            "check=payload",
            "rstn=0",
        ),
    ),
    (
        "rr-fanout-reset-removed",
        "round_robin_priority_arbiter.sv",
        ((0, FANOUT_RESET_BLOCK, FANOUT_RESET_REMOVED),),
        "wrapper-fan-out",
        (
            "class=wrapper-fan-out",
            "instance=round_robin_priority_arbiter_1_input_N_ouput",
            "check=payload",
            "rstn=0",
        ),
    ),
    (
        "fixed-fanin-publish-combinational-grant",
        "fixed_priority_arbiter.sv",
        ((0, PUBLISH_ANCHOR, "assign publish = grant & submit;"),),
        "wrapper-fan-in",
        (
            "class=wrapper-fan-in",
            "instance=fixed_priority_arbiter_N_input_1_ouput",
            "check=payload",
        ),
    ),
    (
        "rr-fanin-publish-combinational-grant",
        "round_robin_priority_arbiter.sv",
        ((0, PUBLISH_ANCHOR, "assign publish = grant & submit;"),),
        "wrapper-fan-in",
        (
            "class=wrapper-fan-in",
            "instance=round_robin_priority_arbiter_N_input_1_ouput",
            "check=payload",
        ),
    ),
    (
        "fixed-fanin-publish-undelayed-ready",
        "fixed_priority_arbiter.sv",
        ((0, PUBLISH_ANCHOR, "assign publish = ready & submit;"),),
        "wrapper-fan-in",
        (
            "class=wrapper-fan-in",
            "instance=fixed_priority_arbiter_N_input_1_ouput",
            "check=payload",
        ),
    ),
    (
        "rr-fanin-publish-undelayed-ready",
        "round_robin_priority_arbiter.sv",
        ((0, PUBLISH_ANCHOR, "assign publish = ready & submit;"),),
        "wrapper-fan-in",
        (
            "class=wrapper-fan-in",
            "instance=round_robin_priority_arbiter_N_input_1_ouput",
            "check=payload",
        ),
    ),
)


def fail(message):
    print(f"FAIL arbitration_unit {message}", file=sys.stderr)
    raise SystemExit(1)


def run(command, **kwargs):
    return subprocess.run(command, check=False, text=True, **kwargs)


def verilator_version(verilator):
    result = run([verilator, "--version"], capture_output=True)
    if result.returncode:
        return 0
    match = re.search(r"Verilator\s+(\d+)", result.stdout)
    return int(match.group(1)) if match else 0


def package_sources():
    sources = []
    manifest = MANIFEST_ROOT / PACKAGE_MANIFEST
    for raw_line in manifest.read_text().splitlines():
        source = raw_line.strip()
        if not source or source.startswith("#"):
            continue
        sources.append(REPO_ROOT / source)
        if len(sources) == PACKAGE_COUNT:
            break
    if len(sources) != PACKAGE_COUNT:
        fail(f"package source list changed in {PACKAGE_MANIFEST}")
    for source in sources:
        if not source.is_file():
            fail(f"package source is missing: {source}")
    return sources


def build_jobs():
    return max(1, min(8, os.cpu_count() or 1))


def compile_test(verilator, dut_sources, build_dir, coverage):
    command = [
        verilator,
        "--cc",
        "--exe",
        "--build",
        "--build-jobs",
        str(build_jobs()),
        "--timing",
        "--assert",
        "-Wall",
        *LINT_WAIVERS,
        "--top-module",
        "arbitration_tb",
        "--Mdir",
        str(build_dir),
    ]
    if coverage:
        command.extend(["--coverage-line", "--coverage-toggle"])
    command.extend(str(source) for source in package_sources())
    command.extend(str(source) for source in dut_sources)
    command.extend([str(TB), str(MAIN)])
    result = run(command, capture_output=True)
    if result.returncode:
        fail("compile failed\n" + result.stdout + result.stderr)


def run_test(build_dir):
    return run([str(build_dir / "Varbitration_tb")], cwd=build_dir, capture_output=True)


def normalise_object(name):
    while True:
        stripped = re.sub(r"\[\d+\]$", "", name)
        if stripped == name:
            return name
        name = stripped


def coverage_points(path, dut_names):
    """Returns raw hit/found counters and the unhit point census per source."""
    counters = defaultdict(lambda: [0, 0])
    unhit = defaultdict(int)
    for line in path.read_bytes().decode("latin1").splitlines():
        file_match = re.search("\x01f\x02([^\x01]+)", line)
        if not file_match:
            continue
        name = Path(file_match.group(1)).name
        if name not in dut_names:
            continue
        count_match = re.search(r"'\s+(\d+)$", line)
        line_match = re.search("\x01l\x02(\\d+)", line)
        object_match = re.search("\x01o\x02([^\x01]+)", line)
        if not count_match or not line_match:
            fail("could not parse a DUT coverage record")
        count = int(count_match.group(1))
        for metric, marker in COVERAGE_PAGES:
            if marker not in line:
                continue
            counters[(name, metric)][1] += 1
            counters[(name, metric)][0] += count > 0
            if count == 0:
                signal = normalise_object(
                    object_match.group(1) if object_match else "?"
                )
                unhit[(name, int(line_match.group(1)), signal, metric)] += 1
            break
    return counters, unhit


def percent(hit, found):
    return 0.0 if found == 0 else (100.0 * hit / found)


def check_raw_denominator(counters, coverage_spec):
    raw = coverage_spec["raw_dut_points"]
    totals = {"line": 0, "branch": 0, "toggle": 0}
    for source in DUT_SOURCES:
        expected = raw[source.name]
        for metric in ("line", "branch", "toggle"):
            found = counters[(source.name, metric)][1]
            if found != expected[metric]:
                fail(
                    f"raw {metric} denominator changed for {source.name}: "
                    f"{found} != {expected[metric]}"
                )
            totals[metric] += found
    for metric in ("line", "branch", "toggle"):
        if totals[metric] != raw["total"][metric]:
            fail(f"raw {metric} total changed: {totals[metric]} != {raw['total'][metric]}")
    return totals


def check_unreachable(unhit, coverage_spec):
    expected = {}
    for entry in (
        coverage_spec["structurally_unreachable"] + coverage_spec["tool_unreachable"]
    ):
        key = (entry["file"], entry["line"], entry["signal"], entry["metric"])
        if key in expected:
            fail(f"duplicate unreachable declaration: {key}")
        expected[key] = entry["points"]
    if dict(unhit) != expected:
        missing = {k: v for k, v in expected.items() if unhit.get(k) != v}
        unexpected = {k: v for k, v in unhit.items() if expected.get(k) != v}
        fail(
            "uncovered point census changed\n"
            f"  declared but not observed: {missing}\n"
            f"  observed but not declared: {unexpected}"
        )
    return sum(expected.values())


def apply_mutation(source_text, edits, name):
    text = source_text
    for occurrence, original, replacement in edits:
        positions = []
        start = 0
        while True:
            index = text.find(original, start)
            if index < 0:
                break
            positions.append(index)
            start = index + 1
        if occurrence >= len(positions):
            fail(f"mutation anchor changed: {name}")
        index = positions[occurrence]
        text = text[:index] + replacement + text[index + len(original):]
    if text == source_text:
        fail(f"mutation produced no change: {name}")
    return text


def main():
    verilator = os.environ.get("VERILATOR", "verilator")
    required = os.environ.get("RTL_VERIFICATION_REQUIRED") == "1"
    if not shutil.which(verilator) or verilator_version(verilator) < 5:
        if required:
            fail("Verilator 5 or newer is required")
        print(
            "SKIP arbitration_unit: install Verilator 5 or set "
            "RTL_VERIFICATION_REQUIRED=1"
        )
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

    bins = scenarios["required_bins"]
    if (
        bins["fixed_priority"] + bins["variable_priority"] +
        bins["round_robin"] + bins["wrappers"] != bins["total"]
    ):
        fail("functional bin denominator changed")
    vectors_by_class = scenarios["stimulus"]["vectors_by_class"]
    class_names = [name for name in vectors_by_class if name != "total"]
    if sum(vectors_by_class[name] for name in class_names) != vectors_by_class["total"]:
        fail("vector denominator changed")
    if len(MUTATIONS) != scenarios["sensitivity"]["mutation_count"]:
        fail("mutation denominator changed")
    if len(scenarios["sensitivity"]["mutations"]) != len(MUTATIONS):
        fail("mutation description list is out of step with the runner")
    for source in DUT_SOURCES:
        if not source.is_file():
            fail(f"device under test is missing: {source}")

    shutil.rmtree(BUILD_ROOT, ignore_errors=True)
    production_build = BUILD_ROOT / "production"
    production_build.mkdir(parents=True)
    compile_test(verilator, DUT_SOURCES, production_build, coverage=True)
    production_result = run_test(production_build)
    if production_result.returncode:
        fail(
            "production test failed\n" +
            production_result.stdout +
            production_result.stderr
        )

    evidence = re.search(r"EVIDENCE arbitration_unit ([^\n]+)", production_result.stdout)
    summary_line = re.search(
        r"PASS arbitration_unit vectors=(\d+) bins=(\d+)",
        production_result.stdout,
    )
    if not evidence or not summary_line:
        fail("production test did not report evidence")
    observed_classes = dict(
        (key, int(value))
        for key, value in re.findall(r"(\w+)=(\d+)", evidence.group(1))
    )
    if observed_classes != {name: vectors_by_class[name] for name in class_names}:
        fail(
            f"per-class vector counts changed: {observed_classes} != "
            f"{ {name: vectors_by_class[name] for name in class_names} }"
        )
    vectors, hit_bins = map(int, summary_line.groups())
    if vectors != vectors_by_class["total"]:
        fail(f"vectors {vectors} != {vectors_by_class['total']}")
    if hit_bins != bins["total"]:
        fail(f"functional bins {hit_bins} != {bins['total']}")

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

    dut_names = {source.name for source in DUT_SOURCES}
    counters, unhit = coverage_points(coverage_data, dut_names)
    raw_totals = check_raw_denominator(counters, coverage_spec)
    unreachable_total = check_unreachable(unhit, coverage_spec)

    metrics = {}
    for metric in ("line", "branch", "toggle"):
        raw_hit = sum(counters[(source.name, metric)][0] for source in DUT_SOURCES)
        raw_found = raw_totals[metric]
        unreachable = sum(
            entry["points"]
            for entry in (
                coverage_spec["structurally_unreachable"] +
                coverage_spec["tool_unreachable"]
            )
            if entry["metric"] == metric
        )
        reachable_found = raw_found - unreachable
        expected = coverage_spec["expected_reachable"][metric]
        if reachable_found != expected["total"] or raw_hit != expected["hit"]:
            fail(
                f"reachable {metric} coverage changed: {raw_hit}/{reachable_found} "
                f"!= {expected['hit']}/{expected['total']}"
            )
        reachable_percent = percent(raw_hit, reachable_found)
        target = coverage_spec["targets"][f"reachable_{'statement' if metric == 'line' else metric}_percent"]
        if reachable_percent < target:
            fail(f"reachable {metric} coverage {reachable_percent:.2f}% < {target}%")
        metrics[metric] = {
            "raw_hit": raw_hit,
            "raw_found": raw_found,
            "unreachable": unreachable,
            "reachable_hit": raw_hit,
            "reachable_found": reachable_found,
            "reachable_percent": reachable_percent,
            "raw_percent": percent(raw_hit, raw_found),
        }
    if unreachable_total != sum(metrics[m]["unreachable"] for m in metrics):
        fail("unreachable point accounting is inconsistent")

    source_text = {source.name: source.read_text() for source in DUT_SOURCES}
    detected = []
    for name, target_name, edits, behaviour, diagnostics in MUTATIONS:
        mutation_root = BUILD_ROOT / f"source-{name}"
        mutation_root.mkdir()
        mutated_sources = []
        for source in DUT_SOURCES:
            destination = mutation_root / source.name
            if source.name == target_name:
                destination.write_text(
                    apply_mutation(source_text[source.name], edits, name)
                )
            else:
                destination.write_text(source_text[source.name])
            mutated_sources.append(destination)
        mutation_build = BUILD_ROOT / f"mutation-{name}"
        mutation_build.mkdir()
        compile_test(verilator, mutated_sources, mutation_build, coverage=False)
        mutation_result = run_test(mutation_build)
        if mutation_result.returncode == 0:
            fail(f"mutation was not detected: {name}")
        output = mutation_result.stdout + mutation_result.stderr
        for diagnostic in diagnostics:
            if diagnostic not in output:
                fail(
                    f"mutation failed for the wrong reason: {name} "
                    f"(missing '{diagnostic}')"
                )
        detected.append({"mutation": name, "behaviour_class": behaviour})

    summary = {
        "schema_version": 1,
        "family": "arbitration",
        "owners": scenarios["owners"],
        "result": "pass",
        "modules": sum(len(v) for v in scenarios["modules"].values()),
        "vectors": vectors,
        "vectors_by_class": observed_classes,
        "functional_bins": {
            "hit": hit_bins,
            "total": bins["total"],
            "percent": percent(hit_bins, bins["total"]),
        },
        "assertion_goals": {
            "hit": len(detected),
            "total": len(MUTATIONS),
            "percent": percent(len(detected), len(MUTATIONS)),
        },
        "code_coverage": {
            "statement": metrics["line"],
            "branch": metrics["branch"],
            "toggle": metrics["toggle"],
            "fsm_state": "not_applicable",
            "fsm_transition": "not_applicable",
        },
        "unreachable_points": unreachable_total,
        "blocked_scenarios": scenarios["blocked_scenarios"],
        "mutations_detected": detected,
        "reproduction": (
            "01_capi_integration/accelerator_verification/rtl/unit/arbitration/"
            "run_arbitration.py"
        ),
    }
    (production_build / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")

    print("OWNERS:afu-arbiter-wrappers,primitive-arbiters")
    print(
        f"PASS arbitration_unit modules={summary['modules']} vectors={vectors} "
        f"bins={hit_bins}/{bins['total']} "
        f"statement={metrics['line']['reachable_percent']:.2f}% "
        f"branch={metrics['branch']['reachable_percent']:.2f}% "
        f"toggle={metrics['toggle']['reachable_percent']:.2f}% "
        f"(raw toggle {metrics['toggle']['raw_hit']}/{metrics['toggle']['raw_found']}, "
        f"{unreachable_total} unreachable) "
        f"mutations={len(detected)}/{len(MUTATIONS)}"
    )


if __name__ == "__main__":
    main()
