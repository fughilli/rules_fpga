# rules_fpga

Bazel rules for building FPGA bitstreams from Verilog, using the open-source
toolchains. The tools are vendored hermetically with Nix via `rules_nixpkgs`, so
on any machine with Nix installed a bare `bazel build //...` realizes everything
— no `nix develop`, no host tools on `PATH`.

Two flows are supported today:

| Family | Synth | Place & route | Pack | Flash |
| ------ | ----- | ------------- | ---- | ----- |
| **Lattice iCE40** | `yosys synth_ice40` | `nextpnr-ice40` | `icepack` → `.bin` | `iceprog` |
| **Gowin** (Tang Nano 9K) | `yosys synth_gowin` | `nextpnr-himbaechel` | `gowin_pack` → `.fs` | `openFPGALoader` |

## Rules

Load everything from `//fpga/rules:defs.bzl`:

```starlark
load("@rules_fpga//fpga/rules:defs.bzl",
     "verilog_library", "verilog_top", "verilog_test",
     "synthesizable_bitstream", "fpga_flash")

verilog_library(name = "blinky", srcs = ["blinky.v"])

verilog_top(name = "blinky_top", top = "blinky", deps = [":blinky"])

# Verilator simulation; passes on $finish, fails on $fatal / assertion.
verilog_test(name = "blinky_test", top = "blinky_tb", tb = "blinky_tb.v", deps = [":blinky"])

# One design → two boards, chosen by platform.
synthesizable_bitstream(
    name = "blinky_tangnano9k",
    top = ":blinky_top",
    platform = "//fpga/platforms:tangnano9k",
    constraints = "tangnano9k.cst",
)

fpga_flash(name = "blinky_tangnano9k_flash", bitstream = ":blinky_tangnano9k")
```

- **`verilog_library`** — a collection of `.v`/`.sv` sources + headers + `deps`.
  Pure metadata (a `VerilogInfo` closure); runs no tools.
- **`verilog_top`** — names the top-level module for a library closure.
- **`verilog_test`** — Verilator simulation of a `(System)Verilog` testbench.
- **`synthesizable_bitstream`** — synth → P&R → pack for the `platform`'s board.
  The `platform` drives a transition that both selects the toolchain family and
  resolves the board's device parameters. `constraints` is the `.pcf`/`.cst`.
- **`fpga_flash`** — `bazel run` target that programs a bitstream onto hardware.

## How a board is targeted

Boards are Bazel `platform()`s. Each declares a `//fpga/constraints:family` value
(selecting the ice40 vs gowin `fpga_toolchain`) and a `//fpga/constraints:board`
value (selecting device parameters via the `//fpga/boards:current` select).
`synthesizable_bitstream` carries an incoming transition on its `platform`
attribute, so one rule instantiation retargets synthesis, toolchain resolution,
and any `select()` in the design all at once.

Shipped platforms: `//fpga/platforms:icebreaker`, `//fpga/platforms:tangnano9k`.

### Adding a board

1. Add a `constraint_value` under `//fpga/constraints` (setting `board`).
2. Add a `platform()` under `//fpga/platforms` (or use the `fpga_board` macro in
   `//fpga/rules:board.bzl`).
3. Add an `fpga_board_info` + a `select()` case in `//fpga/boards:BUILD.bazel`.

## Layout

```
fpga/
  rules/        verilog_library/top/test, synthesizable_bitstream, fpga_flash, providers, board
  toolchains/   fpga_toolchain rule + ice40/gowin toolchain() defs
  constraints/  family {ice40,gowin} + per-board constraint values
  platforms/    board platform() targets
  boards/       per-board device params + the platform→params select
nix/            per-tool BUILD files + the verilator_env buildEnv expression
examples/blinky one design → sim + iCEBreaker .bin + Tang Nano 9K .fs
```

## Building

Requires [Nix](https://nixos.org/download) installed (multi-user or single-user).
Nothing else — Bazel pulls the FPGA tools through `rules_nixpkgs`.

```sh
bazel test  //examples/blinky:blinky_test          # Verilator sim
bazel build //examples/blinky:blinky_icebreaker    # → blinky_icebreaker.bin
bazel build //examples/blinky:blinky_tangnano9k    # → blinky_tangnano9k.fs
bazel run   //examples/blinky:blinky_tangnano9k_flash   # program a connected board
```

Intermediate artifacts are exposed as output groups:
`bazel build //examples/blinky:blinky_tangnano9k --output_groups=netlist,pnr`.
