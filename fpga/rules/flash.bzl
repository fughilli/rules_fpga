"""`fpga_flash`: `bazel run` a bitstream onto a connected board.

Reads the flash tool + board info straight out of the bitstream's
FpgaBitstreamInfo (captured under the board configuration), so this rule needs
no platform transition and no toolchain resolution of its own. iceprog is used
for ice40; openFPGALoader (with the board's flash_args, e.g. `-b tangnano9k`)
for gowin.
"""

load(":providers.bzl", "FpgaBitstreamInfo")

def _runfiles_path(ctx, f):
    """Path of `f` under a run target's $0.runfiles root."""
    if f.short_path.startswith("../"):
        return f.short_path[3:]  # ../<repo>/path -> <repo>/path
    return ctx.workspace_name + "/" + f.short_path

def _fpga_flash_impl(ctx):
    info = ctx.attr.bitstream[FpgaBitstreamInfo]
    tool = info.flash_tool
    bit = info.bitstream
    flags = " ".join([_shquote(a) for a in info.board.flash_args])

    launcher = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = launcher,
        is_executable = True,
        content = """#!/usr/bin/env bash
set -euo pipefail
# Locate this script's runfiles tree (works under `bazel run` and standalone).
R="${{BASH_SOURCE[0]}}.runfiles"
if [[ ! -d "$R" && -n "${{RUNFILES_DIR:-}}" ]]; then
  R="$RUNFILES_DIR"
fi
TOOL="$R/{tool}"
BIT="$R/{bit}"
echo "Flashing $BIT with $(basename "$TOOL") {flags}" >&2
exec "$TOOL" {flags} "$BIT"
""".format(
            tool = _runfiles_path(ctx, tool),
            bit = _runfiles_path(ctx, bit),
            flags = flags,
        ),
    )

    runfiles = ctx.runfiles(files = [tool, bit], transitive_files = info.flash_files)
    return [DefaultInfo(executable = launcher, runfiles = runfiles)]

def _shquote(s):
    # Board flash_args are simple tokens (e.g. "-b", "tangnano9k"); quote defensively.
    if s == "" or " " in s or "'" in s:
        return "'" + s.replace("'", "'\\''") + "'"
    return s

fpga_flash = rule(
    implementation = _fpga_flash_impl,
    executable = True,
    doc = "Runnable target that programs a synthesizable_bitstream onto hardware.",
    attrs = {
        "bitstream": attr.label(
            mandatory = True,
            providers = [FpgaBitstreamInfo],
            doc = "The synthesizable_bitstream to flash.",
        ),
    },
)
