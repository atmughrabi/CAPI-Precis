#!/usr/bin/env python3

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


SCRIPT = Path(__file__).resolve()
SUITE_ROOT = SCRIPT.parent
REPO_ROOT = SCRIPT.parents[4]
BUILD_ROOT = REPO_ROOT / "00_bench/obj/rtl_integration"
MANIFEST_ROOT = (
    REPO_ROOT
    / "01_capi_integration/accelerator_verification/rtl/manifests"
)
MANIFESTS = {
    "memcpy": MANIFEST_ROOT / "memcpy.f",
    "memcpy-tutorial": MANIFEST_ROOT / "memcpy-tutorial.f",
    "mmtiled": MANIFEST_ROOT / "mmtiled.f",
}
MANIFEST = MANIFESTS["memcpy"]
SCENARIOS = SUITE_ROOT / "scenarios.json"
COVERAGE_SPEC = SUITE_ROOT / "coverage.json"

SUITES = {
    "afu-control": {
        "family": "afu-control",
        "tb": SUITE_ROOT / "afu_control_tb.sv",
        "top": "afu_control_tb",
        "pass_re": (
            r"PASS afu_control_integration bins=(\d+)/(\d+) "
            r"assertions=(\d+) tag_capacity=(\d+)"
        ),
        "sources": [
            "01_capi_integration/accelerator_rtl/afu_control/afu_control.sv",
        ],
        "coverage_scopes": {
            "01_capi_integration/accelerator_rtl/afu_control/afu_control.sv":
                "TOP.afu_control_tb.dut",
        },
    },
    "cached-afu": {
        "family": "cached-afu",
        "tb": SUITE_ROOT / "cached_afu_tb.sv",
        "top": "cached_afu_tb",
        "pass_re": r"PASS cached_afu_integration bins=(\d+)/(\d+) assertions=(\d+)",
        "sources": [
            "01_capi_integration/accelerator_rtl/afu_control/cached_afu.sv",
        ],
        "coverage_scopes": {
            "01_capi_integration/accelerator_rtl/afu_control/cached_afu.sv":
                "TOP.cached_afu_tb.dut",
        },
    },
    "afu-wrapper": {
        "family": "afu-wrapper",
        "tb": SUITE_ROOT / "afu_wrapper_tb.sv",
        "top": "afu_wrapper_tb",
        "pass_re": r"PASS afu_wrapper_integration bins=(\d+)/(\d+) assertions=(\d+)",
        "sources": [
            "01_capi_integration/accelerator_rtl/afu_control/afu.sv",
        ],
        "coverage_scopes": {
            "01_capi_integration/accelerator_rtl/afu_control/afu.sv":
                "TOP.afu_wrapper_tb.dut",
        },
    },
}

PROBES = [
    {
        "id": "fixed-concurrent-arbitration",
        "argument": "+PROBE_FIXED_ARBITRATION",
        "expected": "PASS afu_control_probe_fixed",
        "requirement": "fixed arbitration drains simultaneous WED/write/read/prefetch traffic in priority order",
    },
    {
        "id": "round-robin-concurrent-arbitration",
        "argument": "+PROBE_ROUND_ROBIN_ARBITRATION",
        "expected": "PASS afu_control_probe_round_robin",
        "requirement": "round-robin arbitration drains simultaneous WED/write/read/prefetch traffic fairly",
    },
    {
        "id": "restart-replay",
        "argument": "+PROBE_RESTART",
        "expected": "PASS afu_control_probe_restart",
        "requirement": "PAGED/AERROR/DERROR issue RESTART and replay the original transaction exactly once",
    },
    {
        "id": "credit-exhaustion",
        "argument": "+PROBE_CREDIT_EXHAUSTION",
        "blocked_diagnostic": "credit exhaustion expected=2 actual=3",
        "production_location": (
            "01_capi_integration/accelerator_rtl/afu_control/"
            "afu_control.sv:383-387,625-666"
        ),
        "requirement": "two advertised credits permit exactly two commands before a response returns credit",
    },
]

COMMON_WARNINGS = [
    "-Wall",
    "-Wno-fatal",
    "-Wno-ASCRANGE",
    "-Wno-DECLFILENAME",
    "-Wno-EOFNEWLINE",
    "-Wno-GENUNNAMED",
    "-Wno-LATCH",
    "-Wno-MULTIDRIVEN",
    "-Wno-PINCONNECTEMPTY",
    "-Wno-UNOPTFLAT",
    "-Wno-UNUSEDSIGNAL",
    "-Wno-UNUSEDPARAM",
    "-Wno-WIDTHEXPAND",
    "-Wno-WIDTHTRUNC",
]


def fail(message):
    print(f"FAIL integration_suite {message}", file=sys.stderr)
    raise SystemExit(1)


def run(command, **kwargs):
    return subprocess.run(command, check=False, text=True, **kwargs)


def validate_inputs():
    scenarios = json.loads(SCENARIOS.read_text())
    coverage = json.loads(COVERAGE_SPEC.read_text())
    if scenarios.get("suite") != "capi-precis-integration":
        fail("scenario manifest suite id changed")
    if coverage.get("suite") != "capi-precis-integration":
        fail("coverage manifest suite id changed")
    required = [
        "01_capi_integration/accelerator_rtl/afu_control/afu_control.sv",
        "01_capi_integration/accelerator_rtl/afu_control/afu.sv",
        "01_capi_integration/accelerator_rtl/afu_control/cached_afu.sv",
    ]
    for context, manifest in MANIFESTS.items():
        manifest_lines = [
            line.strip()
            for line in manifest.read_text().splitlines()
            if line.strip() and not line.startswith("#")
        ]
        for source in required:
            if source not in manifest_lines:
                fail(f"{context} ordered manifest omits {source}")


def strict_elaboration(verilator):
    log_path = BUILD_ROOT / "strict-elaboration.log"
    command = [
        verilator,
        "--lint-only",
        "--timing",
        "--assert",
        *COMMON_WARNINGS,
        "--top-module",
        "afu_control_tb",
        "-f",
        str(MANIFEST),
        str(SUITES["afu-control"]["tb"]),
    ]
    result = run(command, cwd=REPO_ROOT, capture_output=True)
    output = result.stdout + result.stderr
    log_path.write_text(output)
    diagnostic = "Unsupported: Blocked and non-blocking assignments to same variable"
    if result.returncode == 0:
        return {
            "result": "pass",
            "log": str(log_path.relative_to(REPO_ROOT)),
        }
    if diagnostic not in output or "command_out_latch" not in output:
        fail(f"strict elaboration failed unexpectedly; see {log_path}")
    return {
        "result": "blocked",
        "production_source": (
            "01_capi_integration/accelerator_rtl/afu_control/command_control.sv"
        ),
        "diagnostic": (
            "command_out_latch.context_handle has a continuous assignment while "
            "other fields of the packed struct are assigned nonblocking"
        ),
        "production_location": (
            "01_capi_integration/accelerator_rtl/afu_control/"
            "command_control.sv:41,88-98"
        ),
        "compatibility_flag": "-Wno-BLKANDNBLK",
        "log": str(log_path.relative_to(REPO_ROOT)),
    }


def compile_suite(verilator, name, suite, manifest=None, coverage=True):
    build_dir = BUILD_ROOT / name
    build_dir.mkdir(parents=True, exist_ok=True)
    main_source = (
        build_dir.parent / f"{build_dir.name}-coverage-main.cpp"
    )
    main_source.write_text(
        f'#include "V{suite["top"]}.h"\n'
        '#include "verilated.h"\n'
        '#include "verilated_cov.h"\n\n'
        'int main(int argc, char **argv)\n'
        '{\n'
        '    VerilatedContext context;\n'
        f'    V{suite["top"]} top{{&context}};\n'
        '    context.commandArgs(argc, argv);\n'
        '    while(!context.gotFinish()) {\n'
        '        top.eval();\n'
        '        context.timeInc(1);\n'
        '    }\n'
        '    top.final();\n'
        '#if VM_COVERAGE\n'
        '    context.coveragep()->write("coverage.dat");\n'
        '#endif\n'
        '    return 0;\n'
        '}\n'
    )
    command = [
        verilator,
        "--cc",
        "--exe",
        "--build",
        "--timing",
        "--assert",
        *(["--coverage-line", "--coverage-toggle"] if coverage else []),
        *COMMON_WARNINGS,
        "-Wno-BLKANDNBLK",
        "--top-module",
        suite["top"],
        "--Mdir",
        str(build_dir),
        "-f",
        str(manifest or MANIFEST),
        str(suite["tb"]),
        str(main_source),
    ]
    result = run(command, cwd=REPO_ROOT, capture_output=True)
    log_path = build_dir / "compile.log"
    log_path.write_text(result.stdout + result.stderr)
    if result.returncode:
        fail(f"{name} compatibility compile failed; see {log_path}")
    executable = build_dir / f"V{suite['top']}"
    if not executable.is_file():
        fail(f"{name} executable missing")
    return executable, build_dir


def execute(executable, build_dir, arguments, log_name):
    result = run(
        [str(executable), *arguments],
        cwd=build_dir,
        capture_output=True,
    )
    log_path = build_dir / log_name
    log_path.write_text(result.stdout + result.stderr)
    return result, log_path


def parse_coverage(build_dir, sources):
    coverage_path = build_dir / "coverage.dat"
    if not coverage_path.is_file():
        fail(f"coverage data missing in {build_dir}")
    records = coverage_path.read_bytes().decode("latin1").splitlines()
    metrics = {}
    page_names = {
        "line": "\x01page\x02v_line/",
        "branch": "\x01page\x02v_branch/",
        "toggle": "\x01page\x02v_toggle/",
    }
    for source in sources:
        source_metrics = {}
        for metric, marker in page_names.items():
            counts = []
            for record in records:
                if source not in record or marker not in record:
                    continue
                match = re.search(r"'\s+(\d+)$", record)
                if not match:
                    fail(f"could not parse {metric} record for {source}")
                counts.append(int(match.group(1)))
            source_metrics[metric] = {
                "hit": sum(count > 0 for count in counts),
                "total": len(counts),
                "percent": 0.0 if not counts else 100.0 * sum(count > 0 for count in counts) / len(counts),
            }
        metrics[source] = source_metrics
    return metrics


CONTROL_TOGGLE_RE = re.compile(
    r"(valid|enabled|rstn|reset|running|done|cack|yield|request|pending|"
    r"ready|grant|push|pop|full|alfull|empty|error|ack|init|flushed|"
    r"parity|overflow|paren|tbreq)"
)


def coverage_field(record, key):
    match = re.search(rf"\x01{key}\x02([^\x01']+)", record)
    return match.group(1) if match else ""


def structural_match(point, source, metric, record):
    name = coverage_field(record, "o")
    name_matches = (
        name == point["name"]
        if "name" in point
        else re.fullmatch(point["name_regex"], name) is not None
    )
    return (
        source.endswith(point["source"]) and
        metric == point["metric"] and
        coverage_field(record, "h") == point["hierarchy"] and
        name_matches and
        (
            "line" not in point or
            int(coverage_field(record, "l") or 0) == point["line"]
        )
    )


def parse_closure_coverage(build_dir, suite, structural_points):
    records = (
        build_dir / "coverage.dat"
    ).read_bytes().decode("latin1").splitlines()
    page_names = {
        "line": "\x01page\x02v_line/",
        "branch": "\x01page\x02v_branch/",
        "toggle": "\x01page\x02v_toggle/",
    }
    metrics = {}
    applied = []
    for source in suite["sources"]:
        source_metrics = {}
        scope = suite["coverage_scopes"][source]
        for metric, marker in page_names.items():
            counts = []
            for record in records:
                if (
                    source not in record or
                    marker not in record or
                    coverage_field(record, "h") != scope
                ):
                    continue
                name = coverage_field(record, "o")
                if (
                    metric == "toggle" and
                    (
                        "cu_return_done" in name.lower() or
                        not CONTROL_TOGGLE_RE.search(name.lower())
                    )
                ):
                    continue
                count_match = re.search(r"'\s+(\d+)$", record)
                if not count_match:
                    fail(f"could not parse closure {metric} record for {source}")
                exclusions = [
                    point for point in structural_points
                    if structural_match(point, source, metric, record)
                ]
                if exclusions and int(count_match.group(1)) == 0:
                    for point in exclusions:
                        applied.append(
                            {
                                "rule_id": point["id"],
                                "source": source,
                                "metric": metric,
                                "line": int(coverage_field(record, "l") or 0),
                                "hierarchy": coverage_field(record, "h"),
                                "name": name,
                                "reason": point["reason"],
                            }
                        )
                    continue
                counts.append(int(count_match.group(1)))
            source_metrics[metric] = {
                "hit": sum(count > 0 for count in counts),
                "total": len(counts),
                "percent": (
                    100.0 if not counts
                    else 100.0 * sum(count > 0 for count in counts) / len(counts)
                ),
            }
        metrics[source] = source_metrics
    unique = {
        (
            point["rule_id"],
            point["source"],
            point["metric"],
            point["line"],
            point["hierarchy"],
            point["name"],
        ): point
        for point in applied
    }
    return metrics, [unique[key] for key in sorted(unique)]


def parse_baseline(name, suite, result, log_path):
    if result.returncode:
        fail(f"{name} baseline failed; see {log_path}")
    match = re.search(suite["pass_re"], result.stdout)
    if not match:
        fail(f"{name} baseline did not report exact evidence")
    values = list(map(int, match.groups()))
    hit, total, assertions = values[:3]
    if hit != total:
        fail(f"{name} functional bins {hit}/{total}")
    evidence = {
        "result": "pass",
        "functional_bins": {"hit": hit, "total": total, "percent": 100.0},
        "assertions_checked": assertions,
        "log": str(log_path.relative_to(REPO_ROOT)),
    }
    if name == "afu-control":
        evidence["tag_capacity_observed"] = values[3]
    return evidence


def run_probe(probe, executable, build_dir):
    result, log_path = execute(
        executable,
        build_dir,
        [probe["argument"]],
        f"probe-{probe['id']}.log",
    )
    output = result.stdout + result.stderr
    if "expected" in probe:
        if result.returncode or probe["expected"] not in output:
            fail(f"{probe['id']} did not pass; see {log_path}")
        status = "pass"
        diagnostic = None
    else:
        if result.returncode == 0:
            status = "pass"
            diagnostic = None
        elif probe["blocked_diagnostic"] in output:
            status = "blocked"
            diagnostic = probe["blocked_diagnostic"]
        else:
            fail(f"{probe['id']} failed unexpectedly; see {log_path}")
    return {
        "id": probe["id"],
        "suite": "afu-control",
        "result": status,
        "requirement": probe["requirement"],
        "production_location": probe.get("production_location"),
        "diagnostic": diagnostic,
        "log": str(log_path.relative_to(REPO_ROOT)),
    }


def run_source_mutation(
    verilator,
    mutation_id,
    suite_name,
    source_rel,
    anchor,
    replacement,
    arguments,
    diagnostic,
):
    suite = SUITES[suite_name]
    source_path = REPO_ROOT / source_rel
    text = source_path.read_text()
    if text.count(anchor) != 1:
        fail(f"{mutation_id} anchor changed")
    mutation_root = BUILD_ROOT / f"mutation-{mutation_id}"
    mutated_source = mutation_root / source_path.name
    mutated_source.parent.mkdir(parents=True, exist_ok=True)
    mutated_source.write_text(text.replace(anchor, replacement))
    manifest_lines = MANIFEST.read_text().splitlines()
    manifest_lines = [
        str(mutated_source) if line.strip() == source_rel else line
        for line in manifest_lines
    ]
    mutation_manifest = mutation_root / "manifest.f"
    mutation_manifest.write_text("\n".join(manifest_lines) + "\n")
    executable, build_dir = compile_suite(
        verilator,
        mutation_id,
        suite,
        manifest=mutation_manifest,
        coverage=False,
    )
    result, log_path = execute(
        executable,
        build_dir,
        arguments,
        "run.log",
    )
    output = result.stdout + result.stderr
    if result.returncode == 0 or diagnostic not in output:
        fail(f"{mutation_id} was not detected; see {log_path}")
    return {
        "id": mutation_id,
        "suite": suite_name,
        "result": "detected",
        "diagnostic": diagnostic,
        "log": str(log_path.relative_to(REPO_ROOT)),
    }


def run_family_mutations(verilator):
    return [
        run_source_mutation(
            verilator,
            "afu-drop-credit-reservation",
            "afu-control",
            SUITES["afu-control"]["sources"][0],
            "(credits.credits > (CREDIT_HEADROOM + credit_issue_reservations))",
            "(credits.credits > CREDIT_HEADROOM)",
            ["+PROBE_CREDIT_EXHAUSTION"],
            "credit exhaustion expected=2 actual=3",
        ),
        run_source_mutation(
            verilator,
            "cached-disable-job-enable",
            "cached-afu",
            SUITES["cached-afu"]["sources"][0],
            "enabled          <= job_out.running;",
            "enabled          <= 1'b0;",
            [],
            "command missing",
        ),
        run_source_mutation(
            verilator,
            "wrapper-zero-job-address",
            "afu-wrapper",
            SUITES["afu-wrapper"]["sources"][0],
            "{ha_jval, ha_jcom, ha_jcompar, ha_jea, ha_jeapar}",
            "{ha_jval, ha_jcom, ha_jcompar, 64'b0, ha_jeapar}",
            [],
            "wrapper command address",
        ),
    ]


def run_manifest_contexts(verilator, primary_results):
    contexts = {
        "memcpy": {
            family: {
                "result": "pass",
                "evidence": primary_results[suite_name]["log"],
            }
            for suite_name, family in (
                ("afu-control", "afu-control"),
                ("cached-afu", "cached-afu"),
                ("afu-wrapper", "afu-wrapper"),
            )
        }
    }
    for context in ("memcpy-tutorial", "mmtiled"):
        manifest = MANIFESTS[context]
        contexts[context] = {}

        afu_executable, afu_build = compile_suite(
            verilator,
            f"afu-control-{context}",
            SUITES["afu-control"],
            manifest=manifest,
            coverage=False,
        )
        afu_result, afu_log = execute(
            afu_executable,
            afu_build,
            [],
            "run.log",
        )
        afu_evidence = parse_baseline(
            f"afu-control-{context}",
            SUITES["afu-control"],
            afu_result,
            afu_log,
        )
        contexts[context]["afu-control"] = {
            "result": "pass",
            "functional_bins": afu_evidence["functional_bins"],
            "assertions_checked": afu_evidence["assertions_checked"],
            "evidence": afu_evidence["log"],
        }

        wrapper_executable, wrapper_build = compile_suite(
            verilator,
            f"afu-wrapper-{context}",
            SUITES["afu-wrapper"],
            manifest=manifest,
            coverage=False,
        )
        wrapper_result, wrapper_log = execute(
            wrapper_executable,
            wrapper_build,
            ["+CONTEXT_SMOKE", f"+CONTEXT={context}"],
            "run.log",
        )
        expected = f"PASS afu_wrapper_context context={context} commands=1"
        if wrapper_result.returncode or expected not in wrapper_result.stdout:
            fail(f"{context} wrapper context failed; see {wrapper_log}")
        context_evidence = {
            "result": "pass",
            "commands_observed": 1,
            "evidence": str(wrapper_log.relative_to(REPO_ROOT)),
        }
        contexts[context]["cached-afu"] = dict(context_evidence)
        contexts[context]["afu-wrapper"] = dict(context_evidence)
    return contexts


def find_coverage_gaps(suite_results):
    gaps = []
    for suite_name, suite in suite_results.items():
        for source, metrics in suite["code_coverage"].items():
            for metric, evidence in metrics.items():
                if evidence["total"] and evidence["hit"] < evidence["total"]:
                    gaps.append(
                        {
                            "id": f"coverage:{suite_name}:{Path(source).name}:{metric}",
                            "suite": suite_name,
                            "source": source,
                            "metric": metric,
                            "hit": evidence["hit"],
                            "total": evidence["total"],
                            "percent": evidence["percent"],
                            "target_percent": 100,
                        }
                    )
    return gaps


def build_family_results(
    suite_results,
    probes,
    mutations,
    coverage_gaps,
    manifest_contexts,
    baseline_only,
):
    results = {}
    for suite_name, suite in SUITES.items():
        family_probes = [probe for probe in probes if probe["suite"] == suite_name]
        family_mutations = [
            mutation for mutation in mutations
            if mutation["suite"] == suite_name
        ]
        family_gaps = [
            gap for gap in coverage_gaps if gap["suite"] == suite_name
        ]
        family_contexts = {
            context: evidence[suite["family"]]
            for context, evidence in manifest_contexts.items()
        }
        if baseline_only:
            result = "baseline-pass"
        elif (
            all(probe["result"] == "pass" for probe in family_probes) and
            family_mutations and
            all(
                mutation["result"] == "detected"
                for mutation in family_mutations
            ) and
            all(
                context["result"] == "pass"
                for context in family_contexts.values()
            ) and
            not family_gaps
        ):
            result = "pass"
        else:
            result = "blocked"
        results[suite["family"]] = {
            "result": result,
            "rtl_evidence": suite_results[suite_name],
            "requirement_probes": family_probes,
            "mutations": family_mutations,
            "coverage_gaps": family_gaps,
            "manifest_contexts": family_contexts,
        }
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--baseline-only",
        action="store_true",
        help="Run behavioral baselines without strict-elaboration and closure probes.",
    )
    args = parser.parse_args()

    verilator = os.environ.get("VERILATOR", "verilator")
    if not shutil.which(verilator):
        fail("Verilator is required")
    validate_inputs()
    coverage_spec = json.loads(COVERAGE_SPEC.read_text())
    if BUILD_ROOT.exists():
        shutil.rmtree(BUILD_ROOT)
    BUILD_ROOT.mkdir(parents=True)

    strict = None if args.baseline_only else strict_elaboration(verilator)
    executables = {}
    suite_results = {}
    for name, suite in SUITES.items():
        executable, build_dir = compile_suite(verilator, name, suite)
        result, log_path = execute(executable, build_dir, [], "run.log")
        evidence = parse_baseline(name, suite, result, log_path)
        evidence["raw_code_coverage"] = parse_coverage(
            build_dir,
            suite["sources"],
        )
        (
            evidence["code_coverage"],
            evidence["structural_points_applied"],
        ) = parse_closure_coverage(
            build_dir,
            suite,
            coverage_spec.get("structural_points", []),
        )
        suite_results[name] = evidence
        executables[name] = (executable, build_dir)

    manifest_contexts = run_manifest_contexts(verilator, suite_results)

    probes = []
    mutations = []
    if not args.baseline_only:
        executable, build_dir = executables["afu-control"]
        probes = [run_probe(probe, executable, build_dir) for probe in PROBES]
        mutations = run_family_mutations(verilator)

    coverage_gaps = find_coverage_gaps(suite_results)
    family_results = build_family_results(
        suite_results,
        probes,
        mutations,
        coverage_gaps,
        manifest_contexts,
        args.baseline_only,
    )
    blocked = [
        family for family in family_results.values()
        if family["result"] == "blocked"
    ]
    strict_blocked = strict and strict["result"] == "blocked"
    result_name = (
        "blocked" if blocked or strict_blocked
        else ("baseline-pass" if args.baseline_only else "pass")
    )
    summary = {
        "schema_version": 1,
        "suite": "capi-precis-integration",
        "result": result_name,
        "ordered_manifest": str(MANIFEST.relative_to(REPO_ROOT)),
        "strict_elaboration": strict,
        "rtl_suites": suite_results,
        "families": family_results,
        "manifest_contexts": manifest_contexts,
        "requirement_probes": probes,
        "mutations": mutations,
        "code_coverage_gaps": coverage_gaps,
        "blocked_requirements": (
            (["strict-elaboration"] if strict_blocked else []) +
            [
                gap["id"]
                for family in family_results.values()
                for gap in family["coverage_gaps"]
            ] +
            [
                probe["id"]
                for family in family_results.values()
                for probe in family["requirement_probes"]
                if probe["result"] == "blocked"
            ]
        ),
    }
    (BUILD_ROOT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")

    bins_hit = sum(item["functional_bins"]["hit"] for item in suite_results.values())
    bins_total = sum(item["functional_bins"]["total"] for item in suite_results.values())
    if blocked or strict_blocked:
        print(
            f"BLOCKED integration_suite bins={bins_hit}/{bins_total} "
            f"blockers={len(blocked)} coverage_gaps={len(coverage_gaps)}"
        )
        if strict and strict["result"] == "blocked":
            print(f"BLOCKED strict-elaboration: {strict['diagnostic']}")
        for probe in probes:
            if probe["result"] == "blocked":
                print(f"BLOCKED {probe['id']}: {probe['diagnostic']}")
        for family_name, family in family_results.items():
            print(
                f"{family['result'].upper()} {family_name} "
                f"coverage_gaps={len(family['coverage_gaps'])}"
            )
        raise SystemExit(1)
    if not args.baseline_only:
        print("OWNERS:afu-control,afu-wrapper,cached-afu")
    print(
        f"PASS integration_suite bins={bins_hit}/{bins_total} "
        f"mutations={len(mutations)}/{len(mutations)}"
    )


if __name__ == "__main__":
    try:
        main()
    except OSError as error:
        fail(f"OS error: {error}")
