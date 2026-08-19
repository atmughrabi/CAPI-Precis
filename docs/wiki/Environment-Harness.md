# Environment harness

`tools/capi-env` configures CAPI-Precis for one command or a temporary shell.
It derives repository paths at runtime and does not require `.bashrc` changes.

## Actions

| Action | Purpose |
| --- | --- |
| `check` | Validate paths and mode-specific tools/files |
| `print` | Emit shell-escaped `export` commands |
| `shell` | Start a temporary configured interactive shell |
| `run` or `--` | Execute one command with the scoped environment |

## Modes

| Mode | Checks and use |
| --- | --- |
| `host` | GCC, Make, Python, and initialized PSLSE headers; host tests and verification |
| `sim` | ModelSim, PSLSE checkout, server parameter/data files |
| `synth` | Quartus installation and command-line tools |
| `fpga` | Read/write access to the CAPI device and hardware host execution |

## Common commands

```console
./tools/capi-env --mode host check
./tools/capi-env --mode sim check
./tools/capi-env --mode sim -- make run-vsim
./tools/capi-env --mode sim -- make run-pslse
./tools/capi-env --mode sim -- make run-capi-sim-verbose2
./tools/capi-env --mode synth -- make run-synth
./tools/capi-env --mode fpga -- make run-capi-fpga-verbose2
```

Use a non-default Intel FPGA installation:

```console
./tools/capi-env \
  --mode sim \
  --intel-fpga /opt/intelFPGA/18.1 \
  -- make run-vsim
```

Start a temporary interactive environment:

```console
./tools/capi-env --mode sim shell
```

The temporary shell does not read profile or rc files, so stale exports cannot
override the selected repository or tool installation.

Print exports for the current shell when needed:

```console
eval "$(./tools/capi-env --mode sim print)"
```

## Variables

The harness exports:

- repository roots: `CAPI_PROJECT_ROOT`, `CAPI_ROOT`, `CAPI_SIM_ROOT`;
- tool roots: `ALTERAPATH`, `QUARTUS_INSTALL_DIR`, `QSYS_ROOTDIR`,
  `MODELSIM_ROOT`;
- license path: `LM_LICENSE_FILE` when not already set;
- CAPI/PSLSE: `PSLSE_INSTALL_DIR`, `VPI_USER_H_DIR`, `PSLVER`, `BIT32`;
- server files: `PSLSE_SERVER_DIR`, `PSLSE_SERVER_DAT`, `SHIM_HOST_DAT`,
  `PSLSE_PARMS`, `DEBUG_LOG_PATH`;
- hardware: `CAPI_DEVICE`;
- scoped `PATH` and `LD_LIBRARY_PATH` additions.

Existing values such as `LM_LICENSE_FILE`, `PSLVER`, `BIT32`, and `CAPI_DEVICE`
remain overrideable.

Tool paths are mode-specific. Simulation adds only ModelSim and PSLSE
libraries, synthesis adds only Quartus/Nios tools, and host/FPGA modes do not
inject simulator libraries. CAPI applications honor `CAPI_DEVICE`, falling
back to `/dev/cxl/afu0.0d`.

When changing `PSLVER` or `BIT32`, run `make clean-pslse` before rebuilding.
The ModelSim DPI library remains a 32-bit build as required by the existing
ModelSim flow; `BIT32` selects the PSLSE/libcxl build width.

## Consumer repositories

The options `--project-root`, `--capi-root`, and `--sim-root` allow a consumer
such as AccelGraph to reuse this harness while keeping its own simulation
sources and the pinned CAPI-Precis checkout.

The same roots may be supplied through `CAPI_ENV_PROJECT_ROOT`,
`CAPI_ENV_CAPI_ROOT`, and `CAPI_ENV_SIM_ROOT`; `CAPI_ENV_INTEL_FPGA` selects
the Intel installation and `CAPI_ENV_MODE` selects the mode.

## Verification

```console
./tools/tests/test-capi-env.sh
make verify
```

The harness test checks resolved paths, printed exports, scoped command
execution, host-mode validation, and invalid arguments.
