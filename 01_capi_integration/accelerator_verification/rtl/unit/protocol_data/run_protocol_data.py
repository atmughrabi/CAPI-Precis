#!/usr/bin/env python3

"""Executable unit suite for the CAPI protocol data, register and lifecycle modules.

The suite elaborates read_data_control, write_data_control, wed_control, mmio,
job, done_control and error_control in every active CAPI variant, drives the
focused testbenches of this directory against independent models, enforces the
scenario and coverage manifests and finally proves diagnostic sensitivity with
one mutation per behaviour class.
"""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


SCRIPT = Path(__file__).resolve()
UNIT_ROOT = SCRIPT.parent
RTL_VERIFICATION_ROOT = SCRIPT.parents[2]
REPO_ROOT = SCRIPT.parents[5]
MANIFEST_ROOT = RTL_VERIFICATION_ROOT / "manifests"
RTL_ROOT = REPO_ROOT / "01_capi_integration/accelerator_rtl"
BUILD_ROOT = REPO_ROOT / "00_bench/obj/rtl_unit_protocol_data"
SCENARIOS = UNIT_ROOT / "scenarios.json"
COVERAGE_SPEC = UNIT_ROOT / "coverage.json"
MAIN = UNIT_ROOT / "protocol_data_main.cpp"
TOP_MODULE = "protocol_data_tb"

PACKAGE_SOURCE_COUNT = 7

DEPENDENCY_SOURCES = (
    "afu_control/parity.sv",
    "afu_control/ram.sv",
)

DUT_SOURCES = (
    "afu_control/read_data_control.sv",
    "afu_control/write_data_control.sv",
    "afu_control/wed_control.sv",
    "afu_control/mmio.sv",
    "afu_control/job.sv",
    "afu_control/done_control.sv",
    "afu_control/error_control.sv",
)

TESTBENCHES = (
    "read_data_control_tb.sv",
    "write_data_control_tb.sv",
    "wed_control_tb.sv",
    "mmio_tb.sv",
    "job_tb.sv",
    "completion_error_tb.sv",
    "protocol_data_tb.sv",
)

FAMILY_ORDER = (
    "read-data",
    "write-data",
    "wed",
    "mmio",
    "job",
    "completion-error",
)

WARNING_WAIVERS = (
    "-Wno-ASCRANGE",
    "-Wno-BLKSEQ",
    "-Wno-CASEINCOMPLETE",
    "-Wno-DECLFILENAME",
    "-Wno-EOFNEWLINE",
    "-Wno-GENUNNAMED",
    "-Wno-IMPORTSTAR",
    "-Wno-MULTIDRIVEN",
    "-Wno-SYNCASYNCNET",
    "-Wno-UNUSEDPARAM",
    "-Wno-UNUSEDSIGNAL",
    "-Wno-WIDTHEXPAND",
    "-Wno-WIDTHTRUNC",
)

METRICS = ("line", "branch", "toggle")

PAGE_METRIC = {
    "v_line": "line",
    "v_branch": "branch",
    "v_toggle": "toggle",
}

# One mutation per behaviour class. Each entry names the device source, a unique
# anchor, the replacement and the diagnostic the suite must produce.
MUTATIONS = (
    (
        "read-half-address-decode",
        "read-data",
        "half address decode",
        "afu_control/read_data_control.sv",
        "if(enabled && buffer_in_latched.write_valid && ~(|buffer_in_latched.write_address)) begin",
        "if(enabled && buffer_in_latched.write_valid && (|buffer_in_latched.write_address)) begin",
        "reason=half 0",
    ),
    (
        "read-tag-association",
        "read-data",
        "tag association",
        "afu_control/read_data_control.sv",
        "read_data_control_out_0_latched.line.payload.cmd.tag <= buffer_in_latched.write_tag;",
        "read_data_control_out_0_latched.line.payload.cmd.tag <= data_read_tag_id_in.tag;",
        "tag metadata association",
    ),
    (
        "read-destination-routing",
        "read-data",
        "destination routing",
        "afu_control/read_data_control.sv",
        "          CMD_READ : begin\n"
        "            read_data_control_out_0_latched.read_data <= 1'b1;\n"
        "            read_data_control_out_0_latched.wed_data  <= 1'b0;\n"
        "          end",
        "          CMD_READ : begin\n"
        "            read_data_control_out_0_latched.read_data <= 1'b1;\n"
        "            read_data_control_out_0_latched.wed_data  <= 1'b1;\n"
        "          end",
        "wed destination",
    ),
    (
        "read-parity-report",
        "read-data",
        "parity report",
        "afu_control/read_data_control.sv",
        "tag_parity_error  <= tag_parity_link ^ tag_parity;",
        "tag_parity_error  <= 1'b0;",
        "parity report",
    ),
    (
        "read-parity-beat-association",
        "read-data",
        "parity beat association",
        "afu_control/read_data_control.sv",
        "data_parity_error <= |(data_write_parity_link ^ data_write_parity_latched);",
        "data_parity_error <= |(data_write_parity_link ^ buffer_in.write_parity);",
        "parity report",
    ),
    (
        "read-enabled-window-payload-freeze",
        "read-data",
        "enabled window payload freeze",
        "afu_control/read_data_control.sv",
        "  always_ff @(posedge clock or negedge rstn) begin\n"
        "    if(~rstn) begin\n"
        "      buffer_in_latched.write_tag        <= 0;\n"
        "      buffer_in_latched.write_tag_parity <= 0;\n"
        "      buffer_in_latched.write_address    <= 0;\n"
        "      buffer_in_latched.write_data       <= 0;\n"
        "      buffer_in_latched.write_parity     <= 0;\n"
        "    end else if(enabled) begin\n"
        "      buffer_in_latched.write_tag        <= buffer_in.write_tag;\n"
        "      buffer_in_latched.write_tag_parity <= buffer_in.write_tag_parity;\n"
        "      buffer_in_latched.write_address    <= buffer_in.write_address;\n"
        "      buffer_in_latched.write_data       <= buffer_in.write_data;\n"
        "      buffer_in_latched.write_parity     <= buffer_in.write_parity;\n"
        "    end\n"
        "  end",
        "  always_ff @(posedge clock ) begin\n"
        "    buffer_in_latched.write_tag        <= buffer_in.write_tag;\n"
        "    buffer_in_latched.write_tag_parity <= buffer_in.write_tag_parity;\n"
        "    buffer_in_latched.write_address    <= buffer_in.write_address;\n"
        "    buffer_in_latched.write_data       <= buffer_in.write_data;\n"
        "    buffer_in_latched.write_parity     <= buffer_in.write_parity;\n"
        "  end",
        "parity report",
    ),
    (
        "read-response-qualification",
        "read-data",
        "response qualification",
        "afu_control/read_data_control.sv",
        "(response_latched_response_payload_response != NLOCK)",
        "(response_latched_response_payload_response == NLOCK)",
        "publication valid",
    ),
    (
        "write-half-selection",
        "write-data",
        "half selection",
        "afu_control/write_data_control.sv",
        "          6'h00 : begin\n"
        "            write_data <= write_data_0_out.payload.data;\n"
        "          end",
        "          6'h00 : begin\n"
        "            write_data <= write_data_1_out.payload.data;\n"
        "          end",
        "buffer read data",
    ),
    (
        "write-read-latency-contract",
        "write-data",
        "read latency contract",
        "afu_control/write_data_control.sv",
        "assign read_latency = 4'h3;",
        "assign read_latency = 4'h2;",
        "published read latency contract",
    ),
    (
        "write-lane-parity-publication",
        "write-data",
        "lane parity publication",
        "afu_control/write_data_control.sv",
        "buffer_out.read_parity  <= buffer_out_read_parity;",
        "buffer_out.read_parity  <= {buffer_out_read_parity[1:7], buffer_out_read_parity[0]};",
        "buffer read parity lanes",
    ),
    (
        "write-tag-parity-report",
        "write-data",
        "tag parity report",
        "afu_control/write_data_control.sv",
        "tag_parity_error <= tag_parity_link ^ tag_parity;",
        "tag_parity_error <= 1'b0;",
        "tag parity report",
    ),
    (
        "wed-descriptor-byte-order",
        "wed",
        "descriptor byte order",
        "afu_control/wed_control.sv",
        "wed_cacheline128[0:CACHELINE_SIZE_BITS_HF-1] <= wed_data_0_in.payload.data;",
        "wed_cacheline128[CACHELINE_SIZE_BITS_HF:CACHELINE_SIZE_BITS-1] <= wed_data_0_in.payload.data;",
        "descriptor byte decode",
    ),
    (
        "wed-fetch-once-guard",
        "wed",
        "fetch once guard",
        "afu_control/wed_control.sv",
        "if(enabled && ~wed_request_out.valid && ~command_buffer_status.alfull)",
        "if(enabled && ~command_buffer_status.alfull)",
        "descriptor command request",
    ),
    (
        "wed-command-size",
        "wed",
        "command size",
        "afu_control/wed_control.sv",
        "command_out.payload.size    <= 12'h080;",
        "command_out.payload.size    <= 12'h040;",
        "descriptor command size",
    ),
    (
        "wed-command-bus-transfer-behaviour",
        "wed",
        "command bus transfer behaviour",
        "afu_control/wed_control.sv",
        "command_out.payload.abt     <= STRICT;",
        "command_out.payload.abt     <= SPEC;",
        "descriptor command bus transfer behaviour",
    ),
    (
        "wed-command-tag-metadata",
        "wed",
        "command tag metadata",
        "afu_control/wed_control.sv",
        "command_out.payload.cmd.size             <= 12'h080;",
        "command_out.payload.cmd.size             <= 12'h040;",
        "descriptor command tag metadata",
    ),
    (
        "wed-response-identifier-filter",
        "wed",
        "response identifier filter",
        "afu_control/wed_control.sv",
        "wed_response_in.payload.cmd.cu_id_x == WED_ID",
        "wed_response_in.payload.cmd.cu_id_x != WED_ID",
        "descriptor publication",
    ),
    (
        "mmio-read-decode",
        "mmio",
        "read decode",
        "afu_control/mmio.sv",
        "          CU_STATUS : begin\n"
        "            data_out <= cu_status_latched;\n"
        "          end",
        "          CU_STATUS : begin\n"
        "            data_out <= afu_status_latched;\n"
        "          end",
        "mmio read data",
    ),
    (
        "mmio-descriptor-constant",
        "mmio",
        "descriptor constant",
        "afu_control/mmio.sv",
        "assign afu_desc.afu_cr_offset            = 64'h0000_0000_0000_0100;",
        "assign afu_desc.afu_cr_offset            = 64'h0000_0000_0000_0200;",
        "mmio read data",
    ),
    (
        "mmio-write-decode",
        "mmio",
        "write decode",
        "afu_control/mmio.sv",
        "          CU_CONFIGURE : begin\n"
        "            cu_configure.var1 <= data_in_latched;\n"
        "          end",
        "          CU_CONFIGURE : begin\n"
        "            cu_configure.var2 <= data_in_latched;\n"
        "          end",
        "compute unit configuration publication",
    ),
    (
        "mmio-acknowledge-publication",
        "mmio",
        "acknowledge publication",
        "afu_control/mmio.sv",
        "cu_return_done_ack   <= cu_return_done_ack_latched;",
        "cu_return_done_ack   <= 1'b0;",
        "compute unit return acknowledge",
    ),
    (
        "mmio-parity-report",
        "mmio",
        "parity report",
        "afu_control/mmio.sv",
        "mmio_address_error <= address_parity_link ^ address_parity;",
        "mmio_address_error <= 1'b0;",
        "mmio parity report",
    ),
    (
        "job-done-edge-detection",
        "job",
        "done edge detection",
        "afu_control/job.sv",
        "done_job  <= ~prev_rstn && next_rstn;",
        "done_job  <= prev_rstn && next_rstn;",
        "job done pulse",
    ),
    (
        "job-running-latch",
        "job",
        "running latch",
        "afu_control/job.sv",
        "if(start_job || job_running)",
        "if(job_running)",
        "job running",
    ),
    (
        "job-interface-constants",
        "job",
        "interface constants",
        "afu_control/job.sv",
        "assign job_out.cack    = 1'b0; // Dedicated mode AFU, LLCMD not supported",
        "assign job_out.cack    = 1'b1; // Dedicated mode AFU, LLCMD not supported",
        "dedicated mode constant outputs",
    ),
    (
        "job-reported-error-clear",
        "job",
        "reported error clear",
        "afu_control/job.sv",
        "reported_errors <= 64'b0;",
        "reported_errors <= report_errors;",
        "job error publication",
    ),
    (
        "job-parity-report",
        "job",
        "parity report",
        "afu_control/job.sv",
        "job_command_error <= command_parity_link ^ command_parity;",
        "job_command_error <= 1'b0;",
        "job parity report",
    ),
    (
        "completion-snapshot",
        "completion-error",
        "completion snapshot",
        "afu_control/done_control.sv",
        "cu_return_done_latched             <= cu_return;",
        "cu_return_done_latched             <= 0;",
        "completion publication",
    ),
    (
        "completion-acknowledge",
        "completion-error",
        "completion acknowledge",
        "afu_control/done_control.sv",
        "if(cu_return_done_ack)",
        "if(~cu_return_done_ack)",
        "completion publication",
    ),
    (
        "completion-reset-pulse",
        "completion-error",
        "completion reset pulse",
        "afu_control/done_control.sv",
        "reset_done <= 1'b0;",
        "reset_done <= 1'b1;",
        "completion reset request",
    ),
    (
        "error-snapshot",
        "completion-error",
        "error snapshot",
        "afu_control/error_control.sv",
        "report_errors <= external_errors;",
        "report_errors <= 64'b0;",
        "error publication",
    ),
    (
        "error-acknowledge",
        "completion-error",
        "error acknowledge",
        "afu_control/error_control.sv",
        "if(report_errors_ack)",
        "if(~report_errors_ack)",
        "error reset request",
    ),
)


def fail(message):
    print(f"FAIL protocol_data {message}", file=sys.stderr)
    raise SystemExit(1)


def run(command, **kwargs):
    return subprocess.run(command, check=False, text=True, **kwargs)


def verilator_version(verilator):
    result = run([verilator, "--version"], capture_output=True)
    if result.returncode:
        return 0
    match = re.search(r"Verilator\s+(\d+)", result.stdout)
    return int(match.group(1)) if match else 0


def package_sources(variant):
    manifest = MANIFEST_ROOT / f"{variant}.f"
    sources = []
    for raw_line in manifest.read_text().splitlines():
        source = raw_line.strip()
        if not source or source.startswith("#"):
            continue
        sources.append(REPO_ROOT / source)
        if len(sources) == PACKAGE_SOURCE_COUNT:
            break
    if len(sources) != PACKAGE_SOURCE_COUNT:
        fail(f"{variant} package source list changed")
    for source in sources:
        if not source.is_file():
            fail(f"{variant} package source is missing: {source}")
    return sources


def design_sources(variant, replacements=None):
    replacements = replacements or {}
    sources = package_sources(variant)
    for relative in DEPENDENCY_SOURCES + DUT_SOURCES:
        sources.append(replacements.get(relative, RTL_ROOT / relative))
    return sources


def compile_suite(verilator, sources, build_dir, coverage, defines=()):
    jobs = min(8, os.cpu_count() or 1)
    command = [
        verilator,
        "--cc",
        "--exe",
        "--build",
        "-j",
        str(jobs),
        "--timing",
        "--assert",
        "-Wall",
        *WARNING_WAIVERS,
        "--top-module",
        TOP_MODULE,
        "--Mdir",
        str(build_dir),
    ]
    if coverage:
        command.extend(["--coverage-line", "--coverage-toggle"])
    command.extend(defines)
    command.extend(str(source) for source in sources)
    command.extend(str(UNIT_ROOT / name) for name in TESTBENCHES)
    command.append(str(MAIN))
    result = run(command, capture_output=True)
    if result.returncode:
        fail("compile failed\n" + result.stdout + result.stderr)


def run_suite(build_dir):
    return run([str(build_dir / f"V{TOP_MODULE}")], cwd=build_dir, capture_output=True)


def coverage_points(path):
    totals = {}
    misses = {}
    for line in path.read_bytes().decode("latin1").splitlines():
        file_match = re.search(r"\x01f\x02([^\x01]+)", line)
        page_match = re.search(r"\x01page\x02([^\x01/]+)/", line)
        line_match = re.search(r"\x01l\x02(\d+)", line)
        item_match = re.search(r"\x01o\x02([^\x01]+)", line)
        count_match = re.search(r"'\s+(\d+)$", line)
        if not (file_match and page_match and count_match):
            continue
        name = Path(file_match.group(1)).name
        metric = PAGE_METRIC.get(page_match.group(1))
        if metric is None:
            fail(f"unknown coverage page: {page_match.group(1)}")
        key = (name, metric)
        hit, total = totals.get(key, (0, 0))
        count = int(count_match.group(1))
        totals[key] = (hit + (1 if count else 0), total + 1)
        if count:
            continue
        if not line_match or not item_match:
            fail("coverage record lacks a source location")
        item = re.sub(r"\[\d+\]$", "", item_match.group(1))
        miss_key = (name, metric, int(line_match.group(1)), item)
        misses[miss_key] = misses.get(miss_key, 0) + 1
    return totals, misses


def enforce_coverage(variant, coverage_data, coverage_spec):
    totals, misses = coverage_points(coverage_data)
    expected = coverage_spec["duts"]
    summary = {}

    for name, metrics in expected.items():
        for metric in METRICS:
            key = (name, metric)
            if key not in totals:
                fail(f"{variant} produced no {metric} coverage for {name}")
            hit, total = totals[key]
            if total != metrics[metric]:
                fail(
                    f"{variant} raw {metric} denominator for {name} is {total}, "
                    f"the manifest declares {metrics[metric]}"
                )
            summary.setdefault(name, {})[metric] = {"hit": hit, "total": total}

    declared = {}
    for entry in coverage_spec["structurally_unreachable"]:
        key = (entry["file"], entry["metric"], entry["line"], entry["item"])
        if key in declared:
            fail(f"duplicate unreachable declaration: {key}")
        declared[key] = entry["points"]

    for key, points in declared.items():
        observed = misses.get(key, 0)
        if observed != points:
            fail(
                f"{variant} unreachable declaration {key} covers {points} points "
                f"but {observed} points are uncovered"
            )

    for key, points in misses.items():
        if key[0] not in expected:
            continue
        if key not in declared:
            fail(
                f"{variant} has {points} uncovered {key[1]} point(s) in {key[0]} "
                f"line {key[2]} item {key[3]} without an unreachable declaration"
            )

    for name, metrics in summary.items():
        for metric, values in metrics.items():
            unreachable = sum(
                points
                for key, points in declared.items()
                if key[0] == name and key[1] == metric
            )
            reachable = values["total"] - unreachable
            values["unreachable"] = unreachable
            values["reachable"] = reachable
            if reachable <= 0:
                fail(f"{variant} has no reachable {metric} points in {name}")
            if values["hit"] != reachable:
                fail(
                    f"{variant} reachable {metric} coverage for {name} is "
                    f"{values['hit']}/{reachable}"
                )
            values["percent"] = 100.0
    return summary


def parse_evidence(output, scenarios):
    families = {}
    for match in re.finditer(
        r"EVIDENCE family=(\S+)\s+checks=(\d+) bins=(\d+) stalls=(\d+)",
        output,
    ):
        families[match.group(1)] = {
            "checks": int(match.group(2)),
            "bins": int(match.group(3)),
            "stalls": int(match.group(4)),
        }
    if sorted(families) != sorted(FAMILY_ORDER):
        fail(f"evidence families changed: {sorted(families)}")

    for name in FAMILY_ORDER:
        declared = scenarios["families"][name]
        observed = families[name]
        if observed["checks"] != declared["required_checks"]:
            fail(
                f"{name} performed {observed['checks']} checks, "
                f"the manifest declares {declared['required_checks']}"
            )
        if observed["bins"] != declared["required_bins"]:
            fail(
                f"{name} hit {observed['bins']} bins, "
                f"the manifest declares {declared['required_bins']}"
            )
        if observed["stalls"] != len(declared["stall_profiles"]):
            fail(
                f"{name} exercised {observed['stalls']} stall profiles, "
                f"the manifest declares {len(declared['stall_profiles'])}"
            )

    totals = re.search(
        r"PASS protocol_data families=(\d+) checks=(\d+) bins=(\d+) stalls=(\d+)",
        output,
    )
    if not totals:
        fail("the suite did not report a total evidence line")
    if int(totals.group(1)) != len(FAMILY_ORDER):
        fail(f"family denominator changed: {totals.group(1)}")
    expected_totals = scenarios["totals"]
    if int(totals.group(2)) != expected_totals["checks"]:
        fail(f"total checks {totals.group(2)} != {expected_totals['checks']}")
    if int(totals.group(3)) != expected_totals["bins"]:
        fail(f"total bins {totals.group(3)} != {expected_totals['bins']}")
    if int(totals.group(4)) != expected_totals["stall_profiles"]:
        fail(f"total stall profiles {totals.group(4)} != {expected_totals['stall_profiles']}")
    return families


def validate_manifests(scenarios, coverage_spec):
    if tuple(scenarios["variants"]) != ("memcpy", "memcpy-tutorial", "mmtiled"):
        fail("variant denominator changed")
    if sorted(scenarios["families"]) != sorted(FAMILY_ORDER):
        fail("family denominator changed")

    checks = 0
    bins = 0
    stalls = 0
    for name, family in scenarios["families"].items():
        group_total = sum(family["bin_groups"].values())
        if group_total != family["required_bins"]:
            fail(
                f"{name} bin groups total {group_total} but the family declares "
                f"{family['required_bins']}"
            )
        if not family["scenarios"]:
            fail(f"{name} declares no scenarios")
        if not family["stall_profiles"]:
            fail(f"{name} declares no stall profiles")
        for dut in family["duts"]:
            if not (REPO_ROOT / dut).is_file():
                fail(f"{name} names a device source that does not exist: {dut}")
            if (REPO_ROOT / dut).name not in coverage_spec["duts"]:
                fail(f"{name} device {dut} has no coverage denominator")
        if not (UNIT_ROOT / family["testbench"]).is_file():
            fail(f"{name} names a testbench that does not exist")
        checks += family["required_checks"]
        bins += family["required_bins"]
        stalls += len(family["stall_profiles"])

    totals = scenarios["totals"]
    if (checks, bins, stalls) != (
        totals["checks"],
        totals["bins"],
        totals["stall_profiles"],
    ):
        fail("scenario totals are inconsistent with the family denominators")

    declared_classes = scenarios["mutations"]["behaviour_classes"]
    if sorted(declared_classes) != sorted(FAMILY_ORDER):
        fail("mutation families changed")
    declared_total = sum(len(items) for items in declared_classes.values())
    if declared_total != scenarios["mutations"]["total"]:
        fail("mutation totals are inconsistent")
    if declared_total != len(MUTATIONS):
        fail(
            f"the runner implements {len(MUTATIONS)} mutations but the manifest "
            f"declares {declared_total}"
        )
    implemented = {}
    for _, family, behaviour, *_rest in MUTATIONS:
        implemented.setdefault(family, []).append(behaviour)
    for family, behaviours in declared_classes.items():
        if sorted(behaviours) != sorted(implemented.get(family, [])):
            fail(f"mutation behaviour classes for {family} do not match the runner")

    covered = {Path(source).name for source in DUT_SOURCES}
    if covered != set(coverage_spec["duts"]):
        fail("the coverage manifest does not describe exactly the device sources")


DESCRIPTOR_BITS = 1024


def wed_word_groups(variant):
    """Number of leading four byte fields in the variant descriptor layout."""
    package = None
    for source in package_sources(variant):
        if source.name == "wed_pkg.sv":
            package = source
    if package is None:
        fail(f"{variant} manifest has no work element descriptor package")
    body = re.search(
        r"function WED_request map_DataArrays_to_WED.*?endfunction",
        package.read_text(),
        re.S,
    )
    if not body:
        fail(f"{variant} descriptor mapping function was not found")
    groups = re.findall(r"swap_endianness_(word|double_word)\(", body.group(0))
    if not groups:
        fail(f"{variant} descriptor mapping function has no field groups")
    bits = sum(32 if group == "word" else 64 for group in groups)
    if bits != DESCRIPTOR_BITS:
        fail(f"{variant} descriptor field groups cover {bits} bits")
    words = 0
    for group in groups:
        if group != "word":
            break
        words += 1
    if any(group == "word" for group in groups[words:]):
        fail(f"{variant} descriptor layout interleaves four and eight byte fields")
    return words


def variant_defines(variant):
    return (f"-DWED_WORD_GROUP_COUNT={wed_word_groups(variant)}",)


def mutate_source(name, relative, anchor, replacement):
    original = (RTL_ROOT / relative).read_text()
    if original.count(anchor) != 1:
        fail(f"mutation anchor is not unique: {name}")
    mutation_dir = BUILD_ROOT / "mutations" / name
    mutation_dir.mkdir(parents=True, exist_ok=True)
    mutated = mutation_dir / Path(relative).name
    mutated.write_text(original.replace(anchor, replacement))
    return mutated


def main():
    verilator = os.environ.get("VERILATOR", "verilator")
    required = os.environ.get("RTL_VERIFICATION_REQUIRED") == "1"
    if not shutil.which(verilator) or verilator_version(verilator) < 5:
        if required:
            fail("Verilator 5 or newer is required")
        print(
            "SKIP protocol_data: install Verilator 5 or set "
            "RTL_VERIFICATION_REQUIRED=1"
        )
        return

    scenarios = json.loads(SCENARIOS.read_text())
    coverage_spec = json.loads(COVERAGE_SPEC.read_text())
    validate_manifests(scenarios, coverage_spec)

    shutil.rmtree(BUILD_ROOT, ignore_errors=True)
    BUILD_ROOT.mkdir(parents=True)

    variants = {}
    for variant in scenarios["variants"]:
        build_dir = BUILD_ROOT / variant
        build_dir.mkdir()
        compile_suite(
            verilator,
            design_sources(variant),
            build_dir,
            coverage=True,
            defines=variant_defines(variant),
        )
        result = run_suite(build_dir)
        if result.returncode:
            fail(f"{variant} failed\n" + result.stdout + result.stderr)
        families = parse_evidence(result.stdout, scenarios)
        coverage_data = build_dir / "coverage.dat"
        if not coverage_data.is_file():
            fail(f"{variant} did not produce coverage")
        variants[variant] = {
            "families": families,
            "code_coverage": enforce_coverage(variant, coverage_data, coverage_spec),
        }

    mutations = {}
    reference_variant = scenarios["variants"][0]
    for name, family, behaviour, relative, anchor, replacement, diagnostic in MUTATIONS:
        mutated = mutate_source(name, relative, anchor, replacement)
        build_dir = BUILD_ROOT / "mutations" / name / "build"
        build_dir.mkdir(parents=True)
        compile_suite(
            verilator,
            design_sources(reference_variant, {relative: mutated}),
            build_dir,
            coverage=False,
            defines=variant_defines(reference_variant),
        )
        result = run_suite(build_dir)
        output = result.stdout + result.stderr
        if result.returncode == 0:
            fail(f"mutation was not detected: {name}")
        if diagnostic not in output:
            fail(
                f"mutation failed for the wrong reason: {name}\n"
                f"expected diagnostic: {diagnostic}\n" + output
            )
        mutations[name] = {
            "family": family,
            "behaviour_class": behaviour,
            "diagnostic": diagnostic,
            "result": "detected",
        }
        # the mutated build is only evidence of sensitivity, drop the objects
        shutil.rmtree(BUILD_ROOT / "mutations" / name, ignore_errors=True)

    summary = {
        "schema_version": 1,
        "suite": "protocol-data",
        "result": "pass",
        "families": list(FAMILY_ORDER),
        "variants": variants,
        "functional_bins": {
            "hit": scenarios["totals"]["bins"],
            "total": scenarios["totals"]["bins"],
            "percent": 100.0,
        },
        "checks": scenarios["totals"]["checks"],
        "mutations": mutations,
        "unreachable_states": coverage_spec["unreachable_states"],
        "reproduction": (
            "01_capi_integration/accelerator_verification/rtl/unit/protocol_data/"
            "run_protocol_data.py"
        ),
    }
    (BUILD_ROOT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")

    print("OWNERS:completion-error,job,mmio,read-data,wed,write-data")
    print(
        f"PASS protocol_data variants={len(variants)} families={len(FAMILY_ORDER)} "
        f"checks={scenarios['totals']['checks']} "
        f"bins={scenarios['totals']['bins']}/{scenarios['totals']['bins']} "
        f"line=100.00% branch=100.00% toggle=100.00% "
        f"mutations={len(mutations)}/{len(MUTATIONS)}"
    )


if __name__ == "__main__":
    main()
