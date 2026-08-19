#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd "$script_dir/../.." && pwd -P)
harness="$repo_root/tools/capi-env"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

test -x "$harness"

project_root="$tmpdir/consumer project"
capi_root="$tmpdir/capi root"
sim_root="$project_root/custom simulation"
intel_root="$tmpdir/intel fpga"
device="$tmpdir/afu.device"

mkdir -p \
    "$project_root" \
    "$capi_root/01_capi_integration/pslse/libcxl" \
    "$capi_root/01_capi_integration/pslse/afu_driver/src" \
    "$sim_root/server" \
    "$sim_root/sim" \
    "$intel_root/modelsim_ase/bin" \
    "$intel_root/modelsim_ase/include" \
    "$intel_root/quartus/bin64" \
    "$intel_root/nios2eds/bin"
touch \
    "$capi_root/01_capi_integration/pslse/libcxl/libcxl.h" \
    "$sim_root/server/pslse_server.dat" \
    "$sim_root/server/shim_host.dat" \
    "$sim_root/server/pslse.parms" \
    "$device"
printf '#!/usr/bin/env bash\nexit 0\n' >"$intel_root/modelsim_ase/bin/vsim"
printf '#!/usr/bin/env bash\nexit 0\n' >"$intel_root/quartus/bin64/quartus_sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$intel_root/quartus/bin64/quartus_map"
chmod +x \
    "$intel_root/modelsim_ase/bin/vsim" \
    "$intel_root/quartus/bin64/quartus_sh" \
    "$intel_root/quartus/bin64/quartus_map"

assert_default_print() (
    unset ALTERAPATH BIT32 CAPI_DEVICE HOME LD_LIBRARY_PATH LM_LICENSE_FILE PSLVER
    eval "$("$harness" \
        --mode host \
        --project-root "$project_root" \
        --capi-root "$capi_root" \
        print)"
    test "$CAPI_PROJECT_ROOT" = "$project_root"
    test "$CAPI_ROOT" = "$capi_root"
    test "$CAPI_SIM_ROOT" = "$project_root/01_capi_integration/accelerator_sim"
    test "$PSLVER" = 8
    test "$BIT32" = n
)
assert_default_print

mkdir -p "$capi_root/01_capi_integration/accelerator_sim"
(
    eval "$("$harness" \
        --mode host \
        --project-root "$project_root" \
        --capi-root "$capi_root" \
        print)"
    test "$CAPI_SIM_ROOT" = "$capi_root/01_capi_integration/accelerator_sim"
)

env -u HOME -u ALTERAPATH -u PSLVER -u BIT32 \
    "$harness" \
    --mode host \
    --project-root "$project_root" \
    --capi-root "$capi_root" \
    -- bash -c '
        test "$PSLSE_INSTALL_DIR" = "$CAPI_ROOT/01_capi_integration/pslse"
        test -z "$ALTERAPATH"
    '

env -u PATH \
    "$harness" \
    --mode host \
    --project-root "$project_root" \
    --capi-root "$capi_root" \
    -- bash -c 'command -v make >/dev/null'

PSLVER=9 \
BIT32=y \
LM_LICENSE_FILE="$tmpdir/license.dat" \
CAPI_DEVICE="$device" \
    "$harness" \
    --mode host \
    --project-root "$project_root" \
    --capi-root "$capi_root" \
    run bash -c '
        test "$PSLVER" = 9
        test "$BIT32" = y
        test "$LM_LICENSE_FILE" = "'"$tmpdir/license.dat"'"
        test "$CAPI_DEVICE" = "'"$device"'"
    '

env -u PSLVER -u BIT32 \
    "$harness" \
    --mode host \
    --project-root "$project_root" \
    --capi-root "$capi_root" \
    check >/dev/null

PATH="$intel_root/modelsim_ase/bin:/usr/bin:$intel_root/modelsim_ase/bin" \
LD_LIBRARY_PATH= \
    "$harness" \
    --mode sim \
    --project-root "$project_root" \
    --capi-root "$capi_root" \
    --sim-root "$sim_root" \
    --intel-fpga "$intel_root" \
    run bash -c '
        test "${PATH%%:*}" = "'"$intel_root/modelsim_ase/bin"'"
        test "$(grep -oF "'"$intel_root/modelsim_ase/bin"'" <<<"$PATH" | wc -l)" -eq 1
        test "${LD_LIBRARY_PATH%%:*}" = \
            "'"$capi_root/01_capi_integration/pslse/libcxl"'"
    '

PATH=/usr/bin \
LD_LIBRARY_PATH= \
ALTERAPATH="$intel_root" \
CAPI_DEVICE="$device" \
    "$harness" \
    --mode fpga \
    --project-root "$project_root" \
    --capi-root "$capi_root" \
    run bash -c '
        test "$PATH" = /usr/bin
        test -z "$LD_LIBRARY_PATH"
    '

"$harness" \
    --mode sim \
    --project-root "$project_root" \
    --capi-root "$capi_root" \
    --sim-root "$sim_root" \
    --intel-fpga "$intel_root" \
    check >/dev/null
"$harness" \
    --mode synth \
    --project-root "$project_root" \
    --capi-root "$capi_root" \
    --intel-fpga "$intel_root" \
    check >/dev/null
CAPI_DEVICE="$device" \
    "$harness" \
    --mode fpga \
    --project-root "$project_root" \
    --capi-root "$capi_root" \
    check >/dev/null

mkdir -p "$tmpdir/home"
printf 'export CAPI_ROOT=/wrong/from/bashrc\n' >"$tmpdir/home/.bashrc"
printf 'test "$CAPI_ROOT" = "%s"\nexit\n' "$capi_root" |
    HOME="$tmpdir/home" \
    "$harness" \
    --mode host \
    --project-root "$project_root" \
    --capi-root "$capi_root" \
    shell >/dev/null 2>&1

if "$harness" --mode invalid check >/dev/null 2>&1; then
    echo "invalid mode was accepted" >&2
    exit 1
fi

if "$harness" --mode host run >/dev/null 2>&1; then
    echo "empty run command was accepted" >&2
    exit 1
fi

if "$harness" --pslver 7 check >/dev/null 2>&1; then
    echo "invalid PSL version was accepted" >&2
    exit 1
fi

if "$harness" --bit32 maybe check >/dev/null 2>&1; then
    echo "invalid BIT32 value was accepted" >&2
    exit 1
fi

if "$harness" --mode >/dev/null 2>&1; then
    echo "missing option value was accepted" >&2
    exit 1
fi

echo "PASS capi_env_harness"
