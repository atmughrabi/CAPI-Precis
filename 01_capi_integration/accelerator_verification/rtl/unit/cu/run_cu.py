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
REPO_ROOT = SCRIPT.parents[5]
BUILD_ROOT = REPO_ROOT / "00_bench/obj/rtl_unit_cu"
MANIFEST_ROOT = REPO_ROOT / "01_capi_integration/accelerator_verification/rtl/manifests"
SCENARIOS = SUITE_ROOT / "scenarios.json"
COVERAGE_SPEC = SUITE_ROOT / "coverage.json"

SUITES = {
    "memcpy": {
        "family": "memcpy-cu",
        "manifest": MANIFEST_ROOT / "memcpy.f",
        "tb": SUITE_ROOT / "memcpy_tb.sv",
        "top": "memcpy_tb",
        "pass_re": r"PASS memcpy_cu bins=(\d+)/(\d+) assertions=(\d+)",
        "sources": [
            "01_capi_integration/accelerator_rtl/cu_control/cu_memcpy/memcpy/cu/cu_data_read_engine_control.sv",
            "01_capi_integration/accelerator_rtl/cu_control/cu_memcpy/memcpy/cu/cu_data_write_engine_control.sv",
            "01_capi_integration/accelerator_rtl/cu_control/cu_memcpy/global_cu/cu_control.sv",
        ],
        "coverage_scopes": {
            "01_capi_integration/accelerator_rtl/cu_control/cu_memcpy/memcpy/cu/cu_data_read_engine_control.sv": "TOP.memcpy_tb.*t",
            "01_capi_integration/accelerator_rtl/cu_control/cu_memcpy/memcpy/cu/cu_data_write_engine_control.sv": "TOP.memcpy_tb.*t",
            "01_capi_integration/accelerator_rtl/cu_control/cu_memcpy/global_cu/cu_control.sv": "TOP.memcpy_tb.full_dut",
        },
    },
    "tutorial": {
        "family": "tutorial-cu",
        "manifest": MANIFEST_ROOT / "memcpy-tutorial.f",
        "tb": SUITE_ROOT / "tutorial_tb.sv",
        "top": "tutorial_tb",
        "pass_re": r"PASS tutorial_cu bins=(\d+)/(\d+) assertions=(\d+)",
        "sources": [
            "01_capi_integration/accelerator_rtl/cu_control/cu_memcpy-tutorial/memcpy-tutorial/cu/read_engine.sv",
            "01_capi_integration/accelerator_rtl/cu_control/cu_memcpy-tutorial/memcpy-tutorial/cu/write_engine.sv",
            "01_capi_integration/accelerator_rtl/cu_control/cu_memcpy-tutorial/global_cu/cu_control.sv",
        ],
        "coverage_scopes": {
            "01_capi_integration/accelerator_rtl/cu_control/cu_memcpy-tutorial/memcpy-tutorial/cu/read_engine.sv": "TOP.tutorial_tb.read_dut",
            "01_capi_integration/accelerator_rtl/cu_control/cu_memcpy-tutorial/memcpy-tutorial/cu/write_engine.sv": "TOP.tutorial_tb.write_dut",
            "01_capi_integration/accelerator_rtl/cu_control/cu_memcpy-tutorial/global_cu/cu_control.sv": "TOP.tutorial_tb.full_dut",
        },
    },
    "mmtiled": {
        "family": "mmtiled-cu",
        "manifest": MANIFEST_ROOT / "mmtiled.f",
        "tb": SUITE_ROOT / "mmtiled_tb.sv",
        "top": "mmtiled_tb",
        "pass_re": r"PASS mmtiled_cu bins=(\d+)/(\d+) assertions=(\d+)",
        "sources": [
            "01_capi_integration/accelerator_rtl/cu_control/cu_mmtiled/global_cu/cu_matrix_C_job_control.sv",
            "01_capi_integration/accelerator_rtl/cu_control/cu_mmtiled/mmtiled/cu/cu_matrix_multiply_control.sv",
            "01_capi_integration/accelerator_rtl/cu_control/cu_mmtiled/global_cu/cu_control.sv",
        ],
        "coverage_scopes": {
            "01_capi_integration/accelerator_rtl/cu_control/cu_mmtiled/global_cu/cu_matrix_C_job_control.sv": "TOP.mmtiled_tb.*t",
            "01_capi_integration/accelerator_rtl/cu_control/cu_mmtiled/mmtiled/cu/cu_matrix_multiply_control.sv": "TOP.mmtiled_tb.full_dut.matrix_engine_x[0].matrix_engine_y[0].matrix_multiply_control_instant",
            "01_capi_integration/accelerator_rtl/cu_control/cu_mmtiled/global_cu/cu_control.sv": "TOP.mmtiled_tb.full_dut",
        },
    },
}

PROBES = [
    {
        "id": "tutorial-write-backpressure",
        "suite": "tutorial",
        "argument": "+PROBE_WRITE_BACKPRESSURE",
        "diagnostic": "write command escaped write_command_buffer_status.alfull",
        "source": (
            "01_capi_integration/accelerator_rtl/cu_control/"
            "cu_memcpy-tutorial/memcpy-tutorial/cu/write_engine.sv:177-185"
        ),
        "requirement": (
            "write engine must preserve at least three ordered command/data "
            "tuples across multi-cycle write backpressure"
        ),
    },
    {
        "id": "memcpy-write-only",
        "suite": "memcpy",
        "argument": "+PROBE_WRITE_ONLY",
        "diagnostic": "write-only mode neither issued a write nor completed",
        "source": (
            "01_capi_integration/accelerator_rtl/cu_control/"
            "cu_memcpy/global_cu/cu_control.sv:277-280"
        ),
        "requirement": "write-only configuration must make forward progress",
    },
    {
        "id": "memcpy-tlb-limit-resume",
        "suite": "memcpy",
        "argument": "+PROBE_TLB_LIMIT",
        "diagnostic": "TLB limit next burst command missing",
        "source": (
            "01_capi_integration/accelerator_rtl/cu_control/cu_memcpy/"
            "memcpy/cu/cu_data_read_engine_control.sv:239-341"
        ),
        "requirement": (
            "after the max-TLB-request burst drains, remaining cachelines "
            "must start a new burst"
        ),
    },
    {
        "id": "mmtiled-first-address",
        "suite": "mmtiled",
        "argument": "+PROBE_MATRIX_ADDRESS",
        "diagnostic": "expected=0000000066000000 actual=0000000066000004",
        "source": (
            "01_capi_integration/accelerator_rtl/cu_control/cu_mmtiled/"
            "global_cu/cu_matrix_C_job_control.sv:335,405"
        ),
        "requirement": "the first tile read must start at Matrix_C + (ii*n+jj)*4",
    },
    {
        "id": "mmtiled-matrix-product",
        "suite": "mmtiled",
        "argument": "+PROBE_MATRIX_PRODUCT",
        "diagnostic": "1x1 matrix product produced no Matrix-C write command",
        "source": (
            "01_capi_integration/accelerator_rtl/cu_control/cu_mmtiled/"
            "mmtiled/cu/cu_matrix_multiply_control.sv"
        ),
        "requirement": (
            "a clipped tile must accumulate transposed-B products into C "
            "and publish exact write/term counters"
        ),
    },
    {
        "id": "mmtiled-word-offsets",
        "suite": "mmtiled",
        "argument": "+PROBE_MATRIX_WORD_OFFSETS",
        "diagnostic": "matrix write golden mismatch",
        "source": (
            "01_capi_integration/accelerator_rtl/cu_control/cu_mmtiled/"
            "mmtiled/cu/cu_matrix_multiply_control.sv"
        ),
        "requirement": (
            "cacheline word offsets 15, 16, and 31 must use half-local "
            "indices and preserve distinct nonzero read/write values"
        ),
    },
]

VERILATOR_FLAGS = [
    "--timing",
    "--assert",
    "--coverage-line",
    "--coverage-toggle",
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
    print(f"FAIL cu_suite {message}", file=sys.stderr)
    raise SystemExit(1)


def run(command, **kwargs):
    return subprocess.run(command, check=False, text=True, **kwargs)


def validate_manifests():
    scenarios = json.loads(SCENARIOS.read_text())
    coverage = json.loads(COVERAGE_SPEC.read_text())
    if scenarios.get("suite") != "capi-precis-cu":
        fail("scenario manifest suite id changed")
    if coverage.get("suite") != "capi-precis-cu":
        fail("coverage manifest suite id changed")
    for suite_name, suite in SUITES.items():
        lines = [
            line.strip()
            for line in suite["manifest"].read_text().splitlines()
            if line.strip() and not line.startswith("#")
        ]
        positions = []
        manifest_sources = [
            source
            for source in suite["sources"]
            if source not in suite.get("extra_sources", [])
        ]
        for source in manifest_sources:
            if source not in lines:
                fail(f"{suite_name} ordered manifest omits {source}")
            positions.append(lines.index(source))
        if positions != sorted(positions):
            fail(f"{suite_name} DUT source order changed")


def compile_suite(verilator, name, suite, build_dir, manifest=None, coverage=True):
    build_dir.mkdir(parents=True, exist_ok=True)
    compile_log = build_dir / "compile.log"
    main_source = build_dir / "coverage_main.cpp"
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
        *[
            flag
            for flag in VERILATOR_FLAGS
            if coverage or flag not in ("--coverage-line", "--coverage-toggle")
        ],
        "--top-module",
        suite["top"],
        "--Mdir",
        str(build_dir),
        "-f",
        str(manifest or suite["manifest"]),
        *[
            str(REPO_ROOT / source)
            for source in suite.get("extra_sources", [])
        ],
        str(suite["tb"]),
        str(main_source),
    ]
    result = run(command, cwd=REPO_ROOT, capture_output=True)
    compile_log.write_text(result.stdout + result.stderr)
    if result.returncode:
        fail(f"{name} compile failed; see {compile_log}")
    executable = build_dir / f"V{suite['top']}"
    if not executable.is_file():
        fail(f"{name} executable was not produced")
    return executable


def execute(executable, build_dir, arguments, log_name):
    result = run(
        [str(executable), *arguments],
        cwd=build_dir,
        capture_output=True,
    )
    log_path = build_dir / log_name
    log_path.write_text(result.stdout + result.stderr)
    return result, log_path


def parse_baseline(name, suite, result, log_path):
    if result.returncode:
        fail(f"{name} baseline failed; see {log_path}")
    match = re.search(suite["pass_re"], result.stdout)
    if not match:
        fail(f"{name} baseline did not report exact evidence")
    hit, total, assertions = map(int, match.groups())
    if hit != total:
        fail(f"{name} functional bins {hit}/{total}")
    return {
        "result": "pass",
        "functional_bins": {"hit": hit, "total": total, "percent": 100.0},
        "assertions_checked": assertions,
        "log": str(log_path.relative_to(REPO_ROOT)),
    }


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
                    fail(f"could not parse {metric} coverage record for {source}")
                counts.append(int(match.group(1)))
            source_metrics[metric] = {
                "hit": sum(count > 0 for count in counts),
                "total": len(counts),
                "percent": 0.0 if not counts else 100.0 * sum(count > 0 for count in counts) / len(counts),
            }
        metrics[source] = source_metrics
    return metrics


CONTROL_TOGGLE_RE = re.compile(
    r"(^|\.)(rstn|reset|enabled|configured|valid|full|alfull|empty|"
    r"state|current_state|next_state|send_|leave_|done|pending|ready|"
    r"request|grant|push|pop|setup_|generate_|clear_|start_shift|"
    r"switch_shift|zero_pass|cmd_setup|command|cmd_type|array_struct|"
    r"abt|size|real_size|real_size_bytes|cacheline_offset|cu_id)"
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
    coverage_path = build_dir / "coverage.dat"
    records = coverage_path.read_bytes().decode("latin1").splitlines()
    page_names = {
        "line": "\x01page\x02v_line/",
        "branch": "\x01page\x02v_branch/",
        "toggle": "\x01page\x02v_toggle/",
    }
    metrics = {}
    applied = []
    for source in suite["sources"]:
        source_metrics = {}
        expected_scope = suite["coverage_scopes"][source]
        for metric, marker in page_names.items():
            counts = []
            for record in records:
                if (
                    source not in record or
                    marker not in record or
                    coverage_field(record, "h") != expected_scope
                ):
                    continue
                name = coverage_field(record, "o")
                if metric == "toggle" and not CONTROL_TOGGLE_RE.search(name.lower()):
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
    unique_applied = {
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
    return metrics, [
        unique_applied[key] for key in sorted(unique_applied)
    ]


def run_probe(probe, executables):
    suite = probe["suite"]
    executable, build_dir = executables[suite]
    result, log_path = execute(
        executable,
        build_dir,
        [probe["argument"]],
        f"probe-{probe['id']}.log",
    )
    output = result.stdout + result.stderr
    if result.returncode == 0:
        status = "pass"
    elif probe["diagnostic"] in output:
        status = "blocked"
    else:
        fail(f"{probe['id']} failed without its exact diagnostic; see {log_path}")
    return {
        "id": probe["id"],
        "suite": suite,
        "result": status,
        "requirement": probe["requirement"],
        "production_source": probe["source"],
        "diagnostic": None if status == "pass" else probe["diagnostic"],
        "log": str(log_path.relative_to(REPO_ROOT)),
    }


def run_tutorial_mutation(verilator):
    suite = SUITES["tutorial"]
    source_rel = suite["sources"][0]
    source_path = REPO_ROOT / source_rel
    anchor = (
        "read_command_out_latched.payload.address <= "
        "wed_request_in_driver.payload.wed.array_send + next_offset;"
    )
    replacement = (
        "read_command_out_latched.payload.address <= "
        "wed_request_in_driver.payload.wed.array_send + next_offset + 8;"
    )
    text = source_path.read_text()
    if text.count(anchor) != 1:
        fail("tutorial mutation anchor changed")
    mutation_root = BUILD_ROOT / "mutation-tutorial-read-address"
    mutated_source = mutation_root / "read_engine.sv"
    mutated_source.parent.mkdir(parents=True, exist_ok=True)
    mutated_source.write_text(text.replace(anchor, replacement))
    manifest_lines = suite["manifest"].read_text().splitlines()
    manifest_lines = [
        str(mutated_source) if line.strip() == source_rel else line
        for line in manifest_lines
    ]
    mutation_manifest = mutation_root / "manifest.f"
    mutation_manifest.write_text("\n".join(manifest_lines) + "\n")
    executable = compile_suite(
        verilator,
        "tutorial mutation",
        suite,
        mutation_root / "obj",
        mutation_manifest,
        coverage=False,
    )
    result, log_path = execute(
        executable,
        mutation_root / "obj",
        [],
        "run.log",
    )
    output = result.stdout + result.stderr
    if result.returncode == 0 or "read address" not in output:
        fail(f"tutorial read-address mutation was not detected; see {log_path}")
    return {
        "id": "tutorial-read-address-plus-eight",
        "suite": "tutorial",
        "result": "detected",
        "diagnostic": "read address",
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
    expected_anchors=1,
):
    suite = SUITES[suite_name]
    source_path = REPO_ROOT / source_rel
    text = source_path.read_text()
    if text.count(anchor) != expected_anchors:
        fail(f"{mutation_id} anchor changed")
    mutation_root = BUILD_ROOT / f"mutation-{mutation_id}"
    mutated_source = mutation_root / source_path.name
    mutated_source.parent.mkdir(parents=True, exist_ok=True)
    mutated_source.write_text(text.replace(anchor, replacement))
    manifest_lines = suite["manifest"].read_text().splitlines()
    manifest_lines = [
        str(mutated_source) if line.strip() == source_rel else line
        for line in manifest_lines
    ]
    mutation_manifest = mutation_root / "manifest.f"
    mutation_manifest.write_text("\n".join(manifest_lines) + "\n")
    mutation_suite = dict(suite)
    mutation_suite["extra_sources"] = [
        str(mutated_source) if source == source_rel else source
        for source in suite.get("extra_sources", [])
    ]
    executable = compile_suite(
        verilator,
        mutation_id,
        mutation_suite,
        mutation_root / "obj",
        mutation_manifest,
        coverage=False,
    )
    result, log_path = execute(
        executable,
        mutation_root / "obj",
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


def run_repair_mutations(verilator):
    tutorial_write = SUITES["tutorial"]["sources"][1]
    memcpy_control = SUITES["memcpy"]["sources"][2]
    memcpy_read = SUITES["memcpy"]["sources"][0]
    memcpy_write = SUITES["memcpy"]["sources"][1]
    mmtiled_job = SUITES["mmtiled"]["sources"][0]
    mmtiled_engine = SUITES["mmtiled"]["sources"][1]
    mutations = [
        run_source_mutation(
            verilator,
            "tutorial-drop-write-backpressure",
            "tutorial",
            tutorial_write,
            "~write_command_buffer_status_latched.alfull;",
            "1'b1;",
            ["+PROBE_WRITE_BACKPRESSURE"],
            "write command escaped write_command_buffer_status.alfull",
        ),
        run_source_mutation(
            verilator,
            "tutorial-overwrite-pending-write",
            "tutorial",
            tutorial_write,
            (
                "write_tuple_queue[tuple_write_pointer] <= "
                "incoming_write_tuple;"
            ),
            (
                "write_tuple_queue[tuple_read_pointer] <= "
                "incoming_write_tuple;"
            ),
            ["+PROBE_WRITE_BACKPRESSURE"],
            "queued write address order",
        ),
        run_source_mutation(
            verilator,
            "tutorial-upper-half-sample-stage",
            "tutorial",
            tutorial_write,
            "read_data_1_in_latched.payload.data;",
            "read_data_1_in.payload.data;",
            ["+PROBE_WRITE_BACKPRESSURE"],
            "queued upper write data order",
        ),
        run_source_mutation(
            verilator,
            "memcpy-disable-write-only-source",
            "memcpy",
            memcpy_control,
            (
                "assign independent_write_mode = cu_configure_latched[21] && "
                "~cu_configure_latched[22];"
            ),
            "assign independent_write_mode = 1'b0;",
            ["+PROBE_WRITE_ONLY"],
            "write-only mode issued no write",
        ),
        run_source_mutation(
            verilator,
            "memcpy-read-tlb-oversubscribe",
            "memcpy",
            memcpy_read,
            "(read_job_send_done_latched < max_tlb_cl_requests_latched)",
            "1'b1",
            ["+PROBE_TLB_LIMIT"],
            "TLB limit did not hold while response was absent",
        ),
        run_source_mutation(
            verilator,
            "memcpy-write-tlb-oversubscribe",
            "memcpy",
            memcpy_write,
            "(write_job_send_done_latched < max_tlb_cl_requests_latched)",
            "1'b1",
            ["+PROBE_TLB_LIMIT"],
            "write TLB next burst command missing",
            expected_anchors=2,
        ),
        run_source_mutation(
            verilator,
            "mmtiled-live-counter-address",
            "mmtiled",
            mmtiled_job,
            (
                "wed_request_in_latched.payload.wed.Matrix_C + "
                "(((read_command_matrix_C_job_latched.payload.cmd.address_offset * "
                "wed_request_in_latched.payload.wed.size_n) + "
                "read_command_matrix_C_job_latched.payload.cmd.aux_data) << "
                "$clog2(DATA_SIZE_READ))"
            ),
            (
                "wed_request_in_latched.payload.wed.Matrix_C + "
                "(((matrix_C_num_counter_ii_inc * "
                "wed_request_in_latched.payload.wed.size_n) + "
                "matrix_C_num_counter_jj_inc) << $clog2(DATA_SIZE_READ))"
            ),
            ["+PROBE_MATRIX_ADDRESS"],
            "Matrix-C address expected=",
        ),
        run_source_mutation(
            verilator,
            "mmtiled-hold-row-count",
            "mmtiled",
            mmtiled_job,
            (
                "matrix_C_num_counter_ii_dec <= "
                "matrix_C_num_counter_ii_dec - 1;"
            ),
            (
                "matrix_C_num_counter_ii_dec <= "
                "matrix_C_num_counter_ii_dec;"
            ),
            ["+PROBE_MATRIX_ADDRESS"],
            "single: Matrix-C command count",
        ),
        run_source_mutation(
            verilator,
            "mmtiled-nontransposed-b-address",
            "mmtiled",
            mmtiled_engine,
            "element_address(matrix_b_address, current_j, current_k, matrix_n)",
            "element_address(matrix_b_address, current_k, current_j, matrix_n)",
            ["+PROBE_MATRIX_PRODUCT"],
            "matrix write golden mismatch",
            expected_anchors=2,
        ),
        run_source_mutation(
            verilator,
            "mmtiled-drop-c-accumulation",
            "mmtiled",
            mmtiled_engine,
            "accumulator <= accumulator +",
            "accumulator <=",
            ["+PROBE_MATRIX_PRODUCT"],
            "matrix write golden mismatch",
        ),
        run_source_mutation(
            verilator,
            "mmtiled-disable-edge-clipping",
            "mmtiled",
            mmtiled_engine,
            "return (candidate < limit) ? candidate : limit;",
            "return candidate;",
            ["+PROBE_MATRIX_PRODUCT"],
            "matrix write golden mismatch",
        ),
        run_source_mutation(
            verilator,
            "mmtiled-global-write-half-index",
            "mmtiled",
            mmtiled_engine,
            "{1'b0, word_offset[4:7]}",
            "word_offset[3:7]",
            ["+PROBE_MATRIX_WORD_OFFSETS"],
            "matrix write golden mismatch",
        ),
        run_source_mutation(
            verilator,
            "mmtiled-global-read-half-index",
            "mmtiled",
            mmtiled_engine,
            "{1'b0, incoming_word_offset[4:7]}",
            "incoming_word_offset[3:7]",
            ["+PROBE_MATRIX_WORD_OFFSETS"],
            "matrix completion missing",
        ),
        run_source_mutation(
            verilator,
            "mmtiled-early-read-retire",
            "mmtiled",
            SUITES["mmtiled"]["sources"][2],
            "if(matrix_read_ready_latched) begin",
            "if(enabled_cmd && ~read_buffer_status_latched.alfull) begin",
            ["+PROBE_MATRIX_PRODUCT"],
            "matrix completion missing",
        ),
        run_source_mutation(
            verilator,
            "mmtiled-write-dispatch-ungated",
            "mmtiled",
            SUITES["mmtiled"]["sources"][2],
            "write_command_out_matrix_A_B.valid = matrix_engine_write_dispatch;",
            "write_command_out_matrix_A_B.valid = matrix_engine_write_pending.valid;",
            [],
            "write command escaped multi-cycle alfull",
        ),
        run_source_mutation(
            verilator,
            "mmtiled-write-data-not-cleared",
            "mmtiled",
            SUITES["mmtiled"]["sources"][2],
            (
                "matrix_engine_write_data_0_pending.valid <= 0;\n"
                "                    matrix_engine_write_data_1_pending.valid <= 0;"
            ),
            (
                "matrix_engine_write_data_0_pending.valid <= "
                "matrix_engine_write_data_0_pending.valid;\n"
                "                    matrix_engine_write_data_1_pending.valid <= "
                "matrix_engine_write_data_1_pending.valid;"
            ),
            [],
            "pending write command/data valids did not clear together",
        ),
    ]
    return mutations


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


def build_family_results(suite_results, probes, mutations, coverage_gaps, baseline_only):
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
        if baseline_only:
            result = "baseline-pass"
        elif (
            all(probe["result"] == "pass" for probe in family_probes) and
            family_mutations and
            all(
                mutation["result"] == "detected"
                for mutation in family_mutations
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
        }
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--baseline-only",
        action="store_true",
        help="Run passing/partial baselines without closure probes or mutation.",
    )
    args = parser.parse_args()

    verilator = os.environ.get("VERILATOR", "verilator")
    if not shutil.which(verilator):
        fail("Verilator is required")
    validate_manifests()
    coverage_spec = json.loads(COVERAGE_SPEC.read_text())

    if BUILD_ROOT.exists():
        shutil.rmtree(BUILD_ROOT)
    BUILD_ROOT.mkdir(parents=True)

    golden_result = run(
        [sys.executable, str(SUITE_ROOT / "golden_models.py")],
        cwd=REPO_ROOT,
        capture_output=True,
    )
    (BUILD_ROOT / "goldens.log").write_text(golden_result.stdout + golden_result.stderr)
    if golden_result.returncode or "PASS cu_goldens bins=14/14" not in golden_result.stdout:
        fail("independent workload goldens failed")

    executables = {}
    suite_results = {}
    for name, suite in SUITES.items():
        build_dir = BUILD_ROOT / name
        executable = compile_suite(verilator, name, suite, build_dir)
        result, log_path = execute(executable, build_dir, [], "run.log")
        suite_result = parse_baseline(name, suite, result, log_path)
        suite_result["raw_code_coverage"] = parse_coverage(
            build_dir,
            suite["sources"],
        )
        (
            suite_result["code_coverage"],
            suite_result["structural_points_applied"],
        ) = parse_closure_coverage(
            build_dir,
            suite,
            coverage_spec.get("structural_points", []),
        )
        suite_results[name] = suite_result
        executables[name] = (executable, build_dir)

    probes = []
    mutations = []
    if not args.baseline_only:
        probes = [run_probe(probe, executables) for probe in PROBES]
        mutations.append(run_tutorial_mutation(verilator))
        mutations.extend(run_repair_mutations(verilator))

    coverage_gaps = find_coverage_gaps(suite_results)
    family_results = build_family_results(
        suite_results,
        probes,
        mutations,
        coverage_gaps,
        args.baseline_only,
    )
    blocked = [
        family for family in family_results.values()
        if family["result"] == "blocked"
    ]
    result_name = (
        "blocked" if blocked
        else ("baseline-pass" if args.baseline_only else "pass")
    )
    summary = {
        "schema_version": 1,
        "suite": "capi-precis-cu",
        "result": result_name,
        "goldens": {
            "result": "pass",
            "functional_bins": {"hit": 14, "total": 14, "percent": 100.0},
            "log": str((BUILD_ROOT / "goldens.log").relative_to(REPO_ROOT)),
        },
        "rtl_suites": suite_results,
        "families": family_results,
        "requirement_probes": probes,
        "mutations": mutations,
        "code_coverage_gaps": coverage_gaps,
        "blocked_requirements": [
            gap["id"]
            for family in family_results.values()
            for gap in family["coverage_gaps"]
        ] + [
            probe["id"]
            for family in family_results.values()
            for probe in family["requirement_probes"]
            if probe["result"] == "blocked"
        ],
    }
    (BUILD_ROOT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")

    baseline_bins = sum(
        suite["functional_bins"]["hit"] for suite in suite_results.values()
    )
    baseline_total = sum(
        suite["functional_bins"]["total"] for suite in suite_results.values()
    )
    if blocked:
        print(
            f"BLOCKED cu_suite rtl_bins={baseline_bins}/{baseline_total} "
            f"golden_bins=14/14 blockers={len(blocked)} "
            f"coverage_gaps={len(coverage_gaps)} "
            f"mutations={len(mutations)}/{len(mutations)}"
        )
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
        print("OWNERS:memcpy-cu,mmtiled-cu,tutorial-cu")
    print(
        f"PASS cu_suite rtl_bins={baseline_bins}/{baseline_total} "
        f"golden_bins=14/14 mutations={len(mutations)}/{len(mutations)}"
    )


if __name__ == "__main__":
    try:
        main()
    except OSError as error:
        fail(f"OS error: {error}")
