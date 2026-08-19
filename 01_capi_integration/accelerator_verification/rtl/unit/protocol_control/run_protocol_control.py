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
UNIT_ROOT = SCRIPT.parent
REPO_ROOT = SCRIPT.parents[5]
RTL_ROOT = REPO_ROOT / "01_capi_integration/accelerator_rtl"
BUILD_ROOT = REPO_ROOT / "00_bench/obj/rtl_unit_protocol_control"
SCENARIOS = UNIT_ROOT / "scenarios.json"
COVERAGE_SPEC = UNIT_ROOT / "coverage.json"
TB_PACKAGE = UNIT_ROOT / "protocol_tb_pkg.sv"
AFU_PACKAGE = RTL_ROOT / "afu_pkgs/afu_pkg.sv"

PACKAGE_SOURCES = [
    RTL_ROOT / "afu_pkgs/globals_afu_pkg.sv",
    RTL_ROOT / "cu_control/cu_memcpy/memcpy/pkg/globals_cu_pkg.sv",
    RTL_ROOT / "afu_pkgs/capi_pkg.sv",
    RTL_ROOT / "cu_control/cu_memcpy/global_pkg/cu_pkg.sv",
    RTL_ROOT / "afu_pkgs/credit_pkg.sv",
    AFU_PACKAGE,
]

DUTS = {
    "credit_control": {
        "source": RTL_ROOT / "afu_control/credit_control.sv",
        "dependencies": [],
        "tb": UNIT_ROOT / "credit_control_tb.sv",
        "diagnostic": "credit ledger mismatch",
        "mutations": [
            {
                "name": "request-decrement",
                "source": RTL_ROOT / "afu_control/credit_control.sv",
                "original": "credits <= credits-8'h01;",
                "replacement": "credits <= credits+8'h01;",
            },
            {
                "name": "signed-simultaneous-issue",
                "source": RTL_ROOT / "afu_control/credit_control.sv",
                "original": (
                    "credits <= credits-"
                    "(~credit_in.response_credits[1:8]+8'h02);"
                ),
                "replacement": (
                    "credits <= credits-"
                    "(~credit_in.response_credits[1:8]);"
                ),
            },
        ],
    },
    "command_control": {
        "source": RTL_ROOT / "afu_control/command_control.sv",
        "dependencies": [RTL_ROOT / "afu_control/parity.sv"],
        "tb": UNIT_ROOT / "command_control_tb.sv",
        "diagnostic": "command encoder mismatch",
        "mutations": [
            {
                "name": "tag-encoder-source",
                "source": RTL_ROOT / "afu_control/command_control.sv",
                "original": (
                    "command_out_latch.tag            <= command_tag_in;"
                ),
                "replacement": (
                    "command_out_latch.tag            <= 8'h00;"
                ),
            },
            {
                "name": "mixed-output-driver",
                "source": RTL_ROOT / "afu_control/command_control.sv",
                "original": "logic                  address_parity_next;",
                "replacement": (
                    "logic                  address_parity_next;\n\n"
                    "  assign command_out_latch.context_handle = 16'h0000;"
                ),
                "expected_compile_diagnostic": "%Error-BLKANDNBLK",
            }
        ],
    },
    "response_control": {
        "source": RTL_ROOT / "afu_control/response_control.sv",
        "dependencies": [RTL_ROOT / "afu_control/parity.sv"],
        "tb": UNIT_ROOT / "response_control_tb.sv",
        "diagnostic": "response router mismatch",
        "mutations": [
            {
                "name": "read-route-select",
                "source": RTL_ROOT / "afu_control/response_control.sv",
                "original": (
                    "response_control_out_latched.read_response  <= 1'b1;"
                ),
                "replacement": (
                    "response_control_out_latched.read_response  <= 1'b0;"
                ),
            },
            {
                "name": "nlock-error-mask",
                "source": AFU_PACKAGE,
                "original": (
                    "NLOCK : begin\n"
                    "        cmd_response_error = 6'b100000;\n"
                    "      end"
                ),
                "replacement": (
                    "NLOCK : begin\n"
                    "        cmd_response_error = 6'b000000;\n"
                    "      end"
                ),
            },
        ],
    },
    "response_statistics_control": {
        "source": RTL_ROOT / "afu_control/response_statistics_control.sv",
        "dependencies": [],
        "tb": UNIT_ROOT / "response_statistics_control_tb.sv",
        "diagnostic": "statistics journal mismatch",
        "mutations": [
            {
                "name": "done-counter-increment",
                "source": (
                    RTL_ROOT /
                    "afu_control/response_statistics_control.sv"
                ),
                "original": (
                    "response_statistics_out_latched.DONE_count <= "
                    "response_statistics_out_latched.DONE_count + 1;"
                ),
                "replacement": (
                    "response_statistics_out_latched.DONE_count <= "
                    "response_statistics_out_latched.DONE_count + 2;"
                ),
            }
        ],
    },
    "tag_control": {
        "source": RTL_ROOT / "afu_control/tag_control.sv",
        "dependencies": [
            RTL_ROOT / "afu_control/ram.sv",
            RTL_ROOT / "afu_control/fifo.sv",
        ],
        "tb": UNIT_ROOT / "tag_control_tb.sv",
        "diagnostic": "tag allocator mismatch",
        "mutations": [
            {
                "name": "returned-tag-value",
                "source": RTL_ROOT / "afu_control/tag_control.sv",
                "original": "tag_fifo_input  = response_tag;",
                "replacement": "tag_fifo_input  = response_tag + 1'b1;",
            }
        ],
    },
    "restart_control": {
        "source": RTL_ROOT / "afu_control/restart_control.sv",
        "dependencies": [
            RTL_ROOT / "afu_control/ram.sv",
            RTL_ROOT / "afu_control/fifo.sv",
        ],
        "tb": UNIT_ROOT / "restart_control_tb.sv",
        "diagnostic": "restart replay mismatch",
        "mutations": [
            {
                "name": "restart-response-classification",
                "source": RTL_ROOT / "afu_control/restart_control.sv",
                "original": (
                    "(response.response == PAGED || "
                    "response.response == AERROR || "
                    "response.response == DERROR) && "
                    "(response_tag_id_in.abt == STRICT || "
                    "response_tag_id_in.abt == PAGE || "
                    "response_tag_id_in.abt == SPEC || "
                    "response_tag_id_in.abt == PREF)"
                ),
                "replacement": (
                    "(response.response == DONE) && "
                    "(response_tag_id_in.abt == STRICT || "
                    "response_tag_id_in.abt == PAGE || "
                    "response_tag_id_in.abt == SPEC || "
                    "response_tag_id_in.abt == PREF)"
                ),
            }
        ],
    },
}


def fail(message):
    print(f"FAIL protocol_control {message}", file=sys.stderr)
    raise SystemExit(1)


def run(command, **kwargs):
    return subprocess.run(command, check=False, text=True, **kwargs)


def verilator_version(verilator):
    result = run([verilator, "--version"], capture_output=True)
    if result.returncode:
        return 0
    match = re.search(r"Verilator\s+(\d+)", result.stdout)
    return int(match.group(1)) if match else 0


def source_list(name, source_overrides=None):
    config = DUTS[name]
    sources = [
        *PACKAGE_SOURCES,
        TB_PACKAGE,
        *config["dependencies"],
        config["source"],
        config["tb"],
    ]
    source_overrides = source_overrides or {}
    return [source_overrides.get(source, source) for source in sources]


def compile_test(
    verilator,
    name,
    build_dir,
    coverage,
    source_overrides=None,
    expected_compile_diagnostic=None,
):
    driver = build_dir / f"{name}_main.cpp"
    driver.write_text(
        f'#include "V{name}_tb.h"\n'
        '#include "verilated.h"\n'
        '#include "verilated_cov.h"\n\n'
        "int main(int argc, char **argv)\n"
        "{\n"
        "    VerilatedContext context;\n"
        f"    V{name}_tb top{{&context}};\n\n"
        "    context.commandArgs(argc, argv);\n"
        "    while(!context.gotFinish())\n"
        "    {\n"
        "        top.eval();\n"
        "        if(!top.eventsPending())\n"
        "            break;\n"
        "        context.time(top.nextTimeSlot());\n"
        "    }\n"
        "    top.final();\n"
        "#if VM_COVERAGE\n"
        '    context.coveragep()->write("coverage.dat");\n'
        "#endif\n"
        "    return context.gotFinish() ? 0 : 1;\n"
        "}\n"
    )
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
        "-Wno-CASEINCOMPLETE",
        "-Wno-DECLFILENAME",
        "-Wno-EOFNEWLINE",
        "-Wno-GENUNNAMED",
        "-Wno-IMPORTSTAR",
        "-Wno-LATCH",
        "-Wno-MULTIDRIVEN",
        "-Wno-PINCONNECTEMPTY",
        "-Wno-SYNCASYNCNET",
        "-Wno-TIMESCALEMOD",
        "-Wno-UNDRIVEN",
        "-Wno-UNOPTFLAT",
        "-Wno-UNUSEDSIGNAL",
        "-Wno-UNUSEDPARAM",
        "-Wno-WIDTHEXPAND",
        "-Wno-WIDTHTRUNC",
        "--top-module",
        f"{name}_tb",
        "--Mdir",
        str(build_dir),
        "-o",
        f"V{name}_tb",
    ]
    if coverage:
        command.extend(["--coverage-line", "--coverage-toggle"])
    command.extend(str(source) for source in source_list(name, source_overrides))
    command.append(str(driver))
    result = run(command, capture_output=True)
    if expected_compile_diagnostic:
        diagnostic = result.stdout + result.stderr
        if result.returncode == 0:
            fail(
                f"{name} compile mutation did not fail with "
                f"{expected_compile_diagnostic}"
            )
        if expected_compile_diagnostic not in diagnostic:
            fail(
                f"{name} compile mutation failed without "
                f"{expected_compile_diagnostic}\n{diagnostic}"
            )
        return False
    if result.returncode:
        fail(f"{name} compile failed\n{result.stdout}{result.stderr}")
    return True


def run_test(name, build_dir, coverage):
    command = [str(build_dir / f"V{name}_tb")]
    return run(command, cwd=build_dir, capture_output=True)


def parse_coverage_points(path, dut_source):
    points = []
    markers = {
        "line": "\x01page\x02v_line/",
        "branch": "\x01page\x02v_branch/",
        "toggle": "\x01page\x02v_toggle/",
    }
    for record in path.read_bytes().decode("latin1").splitlines():
        if str(dut_source) not in record:
            continue
        metric = next(
            (name for name, marker in markers.items() if marker in record),
            None,
        )
        if metric is None:
            continue
        count_match = re.search(r"'\s+(\d+)$", record)
        if not count_match:
            fail(f"cannot parse {dut_source.name} coverage count")
        fields = {}
        for encoded_field in record.split("\x01")[1:]:
            if "\x02" not in encoded_field:
                continue
            key, value = encoded_field.split("\x02", 1)
            fields[key] = value.split("' ")[0]
        required_fields = ("l", "n", "o", "h")
        if any(field not in fields for field in required_fields):
            fail(f"{dut_source.name} coverage record lacks exact identity")
        points.append(
            {
                "metric": metric,
                "line": int(fields["l"]),
                "column": int(fields["n"]),
                "operation": fields["o"],
                "span": fields.get("S", ""),
                "scope": fields["h"],
                "count": int(count_match.group(1)),
            }
        )
    return points


def point_key(point):
    return (
        point["metric"],
        point["line"],
        point["column"],
        point["operation"],
        point["span"],
        point["scope"],
    )


def format_point(key):
    metric, line, column, operation, span, scope = key
    return (
        f"{metric}:{line}:{column} operation={operation!r} "
        f"span={span!r} scope={scope!r}"
    )


def unreachable_point_keys(name, coverage_spec, dut_source):
    source_lines = dut_source.read_text().splitlines()
    keys = set()
    for item in coverage_spec["structurally_unreachable"]:
        if item["dut"] != name:
            continue
        line = item["line"]
        if not 0 < line <= len(source_lines):
            fail(f"{name} unreachable point line is out of range: {line}")
        actual_source_line = source_lines[line - 1].strip()
        if actual_source_line != item["source_line"]:
            fail(
                f"{name} unreachable source line changed at {line}: "
                f"{actual_source_line!r} != {item['source_line']!r}"
            )
        if not item.get("reason"):
            fail(f"{name} unreachable point lacks a reason at line {line}")

        if "bits" in item and "bit_range" in item:
            fail(f"{name} unreachable point has two bit selectors at line {line}")
        if "bit_range" in item:
            first, last = item["bit_range"]
            if first > last:
                fail(f"{name} unreachable bit range is reversed at line {line}")
            bits = range(first, last + 1)
        else:
            bits = item.get("bits")

        if bits is not None:
            if item["metric"] != "toggle" or "signal" not in item:
                fail(f"{name} indexed unreachable point is not a signal toggle")
            operations = [f"{item['signal']}[{bit}]" for bit in bits]
        elif "signal" in item:
            if item["metric"] != "toggle":
                fail(f"{name} scalar unreachable signal is not a toggle")
            operations = [item["signal"]]
        else:
            operations = [item["operation"]]

        for operation in operations:
            key = (
                item["metric"],
                line,
                item["column"],
                operation,
                item.get("span", ""),
                item["scope"],
            )
            if key in keys:
                fail(f"{name} duplicate unreachable point: {format_point(key)}")
            keys.add(key)
    return keys


def enforce_coverage_contract(name, path, dut_source, coverage_spec):
    points = parse_coverage_points(path, dut_source)
    point_map = {}
    for point in points:
        key = point_key(point)
        if key in point_map:
            fail(f"{name} duplicate raw coverage point: {format_point(key)}")
        point_map[key] = point

    allowed_zero_keys = unreachable_point_keys(name, coverage_spec, dut_source)
    observed_zero_keys = {
        key for key, point in point_map.items() if point["count"] == 0
    }
    unlisted = observed_zero_keys - allowed_zero_keys
    if unlisted:
        fail(
            f"{name} has unlisted zero raw point: "
            f"{format_point(sorted(unlisted)[0])}"
        )
    no_longer_zero = allowed_zero_keys - observed_zero_keys
    if no_longer_zero:
        fail(
            f"{name} unreachable zero set changed: "
            f"{format_point(sorted(no_longer_zero)[0])}"
        )

    expected = coverage_spec["raw_dut_coverage"]["expected_denominators"][name]
    summaries = {}
    for metric in ("line", "branch", "toggle"):
        metric_points = [
            point for point in points if point["metric"] == metric
        ]
        excluded = sum(
            1 for key in allowed_zero_keys if key[0] == metric
        )
        instrumented = len(metric_points)
        reachable = instrumented - excluded
        hit = sum(
            point["count"] > 0
            for point in metric_points
            if point_key(point) not in allowed_zero_keys
        )
        actual_denominator = {
            "instrumented": instrumented,
            "excluded": excluded,
            "reachable": reachable,
        }
        if actual_denominator != expected[metric]:
            fail(
                f"{name} raw {metric} denominator changed: "
                f"{actual_denominator} != {expected[metric]}"
            )
        if hit != reachable:
            fail(f"{name} raw {metric} reachable coverage {hit}/{reachable}")
        target = coverage_spec["raw_dut_coverage"]["minimum_percent"][name][
            metric
        ]
        achieved = percent(hit, reachable)
        if target != 100.0 or achieved != 100.0:
            fail(
                f"{name} raw {metric} coverage contract "
                f"{hit}/{reachable}={achieved:.2f}% target={target:.2f}%"
            )
        summaries[metric] = {
            "hit": hit,
            "total": reachable,
            "percent": achieved,
            "instrumented": instrumented,
            "excluded": excluded,
            "minimum_percent": target,
        }
    return summaries


def percent(hit, total):
    return 0.0 if total == 0 else 100.0 * hit / total


def validate_specs(scenarios, coverage_spec):
    if scenarios.get("family") != "protocol-control":
        fail("scenario family changed")
    if set(scenarios.get("duts", {})) != set(DUTS):
        fail("scenario DUT denominator changed")
    if set(scenarios.get("mutations", {})) != set(DUTS):
        fail("mutation denominator changed")
    for name, config in DUTS.items():
        declared_mutations = scenarios["mutations"][name]
        implemented_mutations = [
            mutation["name"] for mutation in config["mutations"]
        ]
        if declared_mutations != implemented_mutations:
            fail(f"{name} mutation list changed")
    targets = coverage_spec.get("raw_dut_coverage", {}).get(
        "minimum_percent", {}
    )
    if set(targets) != set(DUTS):
        fail("raw coverage target denominator changed")
    if any(
        metric_target != 100.0
        for dut_targets in targets.values()
        for metric_target in dut_targets.values()
    ):
        fail("every raw DUT coverage target must be 100 percent")
    denominators = coverage_spec.get("raw_dut_coverage", {}).get(
        "expected_denominators", {}
    )
    if set(denominators) != set(DUTS):
        fail("raw coverage denominator DUT set changed")
    for name in DUTS:
        if set(targets[name]) != {"line", "branch", "toggle"}:
            fail(f"{name} raw coverage metric set changed")
        if set(denominators[name]) != {"line", "branch", "toggle"}:
            fail(f"{name} raw denominator metric set changed")
        for metric, denominator in denominators[name].items():
            if set(denominator) != {"instrumented", "excluded", "reachable"}:
                fail(f"{name} {metric} denominator shape changed")
            if (
                denominator["instrumented"] - denominator["excluded"] !=
                denominator["reachable"]
            ):
                fail(f"{name} {metric} denominator arithmetic is inconsistent")


def mutated_source(name, mutation):
    source = mutation["source"]
    original = mutation["original"]
    replacement = mutation["replacement"]
    source_text = source.read_text()
    if source_text.count(original) != 1:
        fail(f"{name}:{mutation['name']} mutation anchor changed")
    mutation_dir = (
        BUILD_ROOT / "mutated_sources" / f"{name}-{mutation['name']}"
    )
    mutation_dir.mkdir(parents=True)
    output = mutation_dir / source.name
    output.write_text(source_text.replace(original, replacement).rstrip() + "\n")
    return source, output


def main():
    parser = argparse.ArgumentParser(
        description="Run executable RTL unit coverage for protocol-control DUTs"
    )
    parser.add_argument(
        "--dut",
        choices=tuple(DUTS),
        action="append",
        help="run only the selected DUT; may be repeated",
    )
    parser.add_argument(
        "--skip-mutations",
        action="store_true",
        help="development aid: skip diagnostic mutation executions",
    )
    args = parser.parse_args()

    verilator = os.environ.get("VERILATOR", "verilator")
    required = os.environ.get("RTL_VERIFICATION_REQUIRED") == "1"
    verilator_path = shutil.which(verilator)
    if not verilator_path or verilator_version(verilator) < 5:
        if required:
            fail("Verilator 5 or newer is required")
        print(
            "SKIP protocol_control: install Verilator 5 or "
            "set RTL_VERIFICATION_REQUIRED=1"
        )
        return
    coverage_tool = os.environ.get(
        "VERILATOR_COVERAGE",
        str(Path(verilator_path).with_name("verilator_coverage")),
    )
    if not Path(coverage_tool).is_file():
        fail("verilator_coverage is required")

    try:
        scenarios = json.loads(SCENARIOS.read_text())
        coverage_spec = json.loads(COVERAGE_SPEC.read_text())
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read suite specifications: {error}")
    validate_specs(scenarios, coverage_spec)

    selected = args.dut or list(DUTS)
    shutil.rmtree(BUILD_ROOT, ignore_errors=True)
    BUILD_ROOT.mkdir(parents=True)

    summaries = {}
    for name in selected:
        config = DUTS[name]
        build_dir = BUILD_ROOT / name / "production"
        build_dir.mkdir(parents=True)
        compile_test(verilator, name, build_dir, coverage=True)
        result = run_test(name, build_dir, coverage=True)
        if result.returncode:
            fail(f"{name} failed\n{result.stdout}{result.stderr}")
        match = re.search(
            rf"PASS protocol_control dut={name} checks=(\d+) "
            r"bins=(\d+)/(\d+)",
            result.stdout,
        )
        if not match:
            fail(f"{name} did not report executable evidence")
        checks, bins_hit, bins_total = map(int, match.groups())
        expected_bins = scenarios["duts"][name]["required_bins"]
        if bins_hit != expected_bins or bins_total != expected_bins:
            fail(
                f"{name} functional bins {bins_hit}/{bins_total} != "
                f"{expected_bins}/{expected_bins}"
            )

        coverage_data = build_dir / "coverage.dat"
        coverage_info = build_dir / "coverage.info"
        if not coverage_data.is_file():
            fail(f"{name} did not produce raw DUT coverage")
        conversion = run(
            [
                coverage_tool,
                "--write-info",
                str(coverage_info),
                str(coverage_data),
            ],
            capture_output=True,
        )
        if conversion.returncode or not coverage_info.is_file():
            fail(f"{name} coverage conversion failed")
        coverage_summary = enforce_coverage_contract(
            name,
            coverage_data,
            config["source"],
            coverage_spec,
        )

        summaries[name] = {
            "checks": checks,
            "functional_bins": {
                "hit": bins_hit,
                "total": bins_total,
                "percent": 100.0,
            },
            "raw_dut_coverage": coverage_summary,
        }

    detected_mutations = []
    if not args.skip_mutations:
        for name in selected:
            detected_for_dut = []
            for mutation in DUTS[name]["mutations"]:
                production_source, source = mutated_source(name, mutation)
                build_dir = (
                    BUILD_ROOT / name / f"mutation-{mutation['name']}"
                )
                build_dir.mkdir()
                compiled = compile_test(
                    verilator,
                    name,
                    build_dir,
                    coverage=False,
                    source_overrides={production_source: source},
                    expected_compile_diagnostic=mutation.get(
                        "expected_compile_diagnostic"
                    ),
                )
                mutation_id = f"{name}:{mutation['name']}"
                if not compiled:
                    detected_mutations.append(mutation_id)
                    detected_for_dut.append(mutation["name"])
                    continue
                result = run_test(name, build_dir, coverage=False)
                diagnostic = result.stdout + result.stderr
                if result.returncode == 0:
                    fail(f"{mutation_id} mutation was not detected")
                fatal_pattern = (
                    r"%Fatal:[^\n]*Assertion failed[^\n]*" +
                    re.escape(DUTS[name]["diagnostic"])
                )
                if not re.search(fatal_pattern, diagnostic):
                    fail(f"{mutation_id} failed with the wrong diagnostic")
                if f"PASS protocol_control dut={name}" in diagnostic:
                    fail(f"{mutation_id} reported PASS before failing")
                detected_mutations.append(mutation_id)
                detected_for_dut.append(mutation["name"])
            summaries[name]["diagnostic_mutations"] = detected_for_dut

    summary = {
        "schema_version": 1,
        "family": "protocol-control",
        "result": "pass",
        "integration_status": (
            "blocked"
            if coverage_spec.get("production_blockers")
            else "ready"
        ),
        "selected_duts": selected,
        "duts": summaries,
        "diagnostic_mutations": {
            "hit": len(detected_mutations),
            "total": (
                0
                if args.skip_mutations
                else sum(len(DUTS[name]["mutations"]) for name in selected)
            ),
            "detected": detected_mutations,
        },
        "structurally_unreachable": coverage_spec["structurally_unreachable"],
        "production_blockers": coverage_spec.get("production_blockers", []),
        "not_applicable": coverage_spec["not_applicable"],
        "artifact_root": str(BUILD_ROOT.relative_to(REPO_ROOT)),
        "reproduction": " ".join(
            [
                str(SCRIPT.relative_to(REPO_ROOT)),
                *[
                    argument
                    for name in selected
                    for argument in ("--dut", name)
                ],
                *(["--skip-mutations"] if args.skip_mutations else []),
            ]
        ),
    }
    (BUILD_ROOT / "summary.json").write_text(
        json.dumps(summary, indent=2) + "\n"
    )
    total_bins = sum(
        summary["functional_bins"]["total"] for summary in summaries.values()
    )
    print("OWNERS:command,credit,response,response-statistics,restart,tag")
    print(
        f"PASS protocol_control duts={len(selected)} "
        f"bins={total_bins}/{total_bins} "
        f"mutations={len(detected_mutations)}/"
        f"{summary['diagnostic_mutations']['total']}"
    )


if __name__ == "__main__":
    main()
