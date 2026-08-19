#!/usr/bin/env bash
set -euo pipefail

VERILATOR=${VERILATOR:-verilator}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
RTL_ROOT="$REPO_ROOT/01_capi_integration/accelerator_rtl"

WARNINGS=(
  -Wall
  -Wno-fatal
  -Wno-ASCRANGE
  -Wno-BLKANDNBLK
  -Wno-BLKSEQ
  -Wno-CASEINCOMPLETE
  -Wno-CMPCONST
  -Wno-DECLFILENAME
  -Wno-EOFNEWLINE
  -Wno-GENUNNAMED
  -Wno-IMPORTSTAR
  -Wno-MULTIDRIVEN
  -Wno-PINCONNECTEMPTY
  -Wno-SYNCASYNCNET
  -Wno-TIMESCALEMOD
  -Wno-UNDRIVEN
  -Wno-UNOPTFLAT
  -Wno-UNUSEDSIGNAL
  -Wno-UNUSEDPARAM
  -Wno-WIDTHEXPAND
  -Wno-WIDTHTRUNC
)

PREFIX_SOURCES=(
  "$RTL_ROOT/afu_pkgs/globals_afu_pkg.sv"
  "$RTL_ROOT/afu_pkgs/capi_pkg.sv"
)

SUFFIX_SOURCES=(
  "$RTL_ROOT/afu_pkgs/credit_pkg.sv"
  "$RTL_ROOT/afu_pkgs/afu_pkg.sv"
  "$RTL_ROOT/afu_control/parity.sv"
  "$RTL_ROOT/afu_control/reset_filter.sv"
  "$RTL_ROOT/afu_control/reset_control.sv"
  "$RTL_ROOT/afu_control/error_control.sv"
  "$RTL_ROOT/afu_control/done_control.sv"
  "$RTL_ROOT/afu_control/ram.sv"
  "$RTL_ROOT/afu_control/fifo.sv"
  "$RTL_ROOT/afu_control/priority_arbiters.sv"
  "$RTL_ROOT/afu_control/round_robin_priority_arbiter.sv"
  "$RTL_ROOT/afu_control/fixed_priority_arbiter.sv"
  "$RTL_ROOT/afu_control/credit_control.sv"
  "$RTL_ROOT/afu_control/response_statistics_control.sv"
  "$RTL_ROOT/afu_control/response_control.sv"
  "$RTL_ROOT/afu_control/restart_control.sv"
  "$RTL_ROOT/afu_control/command_control.sv"
  "$RTL_ROOT/afu_control/tag_control.sv"
  "$RTL_ROOT/afu_control/read_data_control.sv"
  "$RTL_ROOT/afu_control/write_data_control.sv"
  "$RTL_ROOT/afu_control/afu_control.sv"
  "$RTL_ROOT/afu_control/job.sv"
  "$RTL_ROOT/afu_control/mmio.sv"
  "$RTL_ROOT/afu_control/wed_control.sv"
  "$SCRIPT_DIR/cached_afu_bind_cu_stub.sv"
  "$RTL_ROOT/afu_control/cached_afu.sv"
  "$SCRIPT_DIR/accelerator_verification.sv"
  "$SCRIPT_DIR/accelerator_verification_bind.sv"
)

lint_variant() {
  local name=$1
  local globals_cu=$2
  local wed_pkg=$3
  local cu_pkg=$4
  shift 4

  "$VERILATOR" --lint-only --timing "${WARNINGS[@]}" "$@" \
    --top-module cached_afu \
    "${PREFIX_SOURCES[@]}" \
    "$RTL_ROOT/$globals_cu" \
    "$RTL_ROOT/$wed_pkg" \
    "$RTL_ROOT/$cu_pkg" \
    "${SUFFIX_SOURCES[@]}"

  printf 'PASS cached_afu bind %s\n' "$name"
}

lint_variant \
  memcpy \
  cu_control/cu_memcpy/memcpy/pkg/globals_cu_pkg.sv \
  cu_control/cu_memcpy/global_pkg/wed_pkg.sv \
  cu_control/cu_memcpy/global_pkg/cu_pkg.sv

lint_variant \
  memcpy-tutorial \
  cu_control/cu_memcpy-tutorial/memcpy-tutorial/pkg/globals_cu_pkg.sv \
  cu_control/cu_memcpy-tutorial/global_pkg/wed_pkg.sv \
  cu_control/cu_memcpy-tutorial/global_pkg/cu_pkg.sv

lint_variant \
  mmtiled \
  cu_control/cu_mmtiled/mmtiled/pkg/globals_cu_pkg.sv \
  cu_control/cu_mmtiled/global_pkg/wed_pkg.sv \
  cu_control/cu_mmtiled/global_pkg/cu_pkg.sv \
  -DCAPI_PRECIS_VERIFY_ALL_CONFIG_WORDS
