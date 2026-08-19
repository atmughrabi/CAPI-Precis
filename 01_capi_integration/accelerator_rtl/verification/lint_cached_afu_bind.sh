#!/usr/bin/env bash
set -euo pipefail

VERILATOR=${VERILATOR:-verilator}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
MANIFEST_ROOT="$REPO_ROOT/verification/rtl/manifests"

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
  -Werror-IMPLICIT
  -Werror-MODDUP
  -Werror-PINMISSING
  -Werror-PINNOTFOUND
  -Werror-PKGNODECL
)

lint_variant() {
  local name=$1
  shift
  local manifest="$MANIFEST_ROOT/$name.f"
  local source
  local -a sources=()

  while IFS= read -r source || [[ -n "$source" ]]; do
    [[ -z "$source" || "$source" == \#* ]] && continue
    sources+=("$REPO_ROOT/$source")
  done <"$manifest"

  while IFS= read -r source || [[ -n "$source" ]]; do
    [[ -z "$source" || "$source" == \#* ]] && continue
    sources+=("$REPO_ROOT/$source")
  done <"$MANIFEST_ROOT/monitor.f"
  while IFS= read -r source || [[ -n "$source" ]]; do
    [[ -z "$source" || "$source" == \#* ]] && continue
    sources+=("$REPO_ROOT/$source")
  done <"$MANIFEST_ROOT/monitor-capi-bind.f"

  "$VERILATOR" --lint-only --timing "${WARNINGS[@]}" "$@" \
    --top-module cached_afu \
    "${sources[@]}"

  printf 'PASS cached_afu real bind %s\n' "$name"
}

lint_variant memcpy
lint_variant memcpy-tutorial
lint_variant mmtiled -DCAPI_PRECIS_VERIFY_ALL_CONFIG_WORDS
