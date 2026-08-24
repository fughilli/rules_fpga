"""`verilog_test`: simulate a design with Verilator and pass/fail on the result.

The testbench is plain (System)Verilog with an `initial` block that ends in
`$finish` (pass) and uses `$error`/`$fatal`/assertions on failure -- no
hand-written C++ harness. Verilator's `--binary` mode generates the sim main and
compiles it (via the gcc/make/perl bundled in the `verilator_env` repo); the
test runner builds then executes it, so a non-zero exit (from `$fatal`/failed
assertion) fails the test. `--timing` is passed so `#`-delay testbenches work.
"""

load(":providers.bzl", "VerilogInfo")

def _rf(f):
    """Path of File `f` under $RUNFILES_DIR for a test (main-repo files need $TEST_WORKSPACE)."""
    if f.short_path.startswith("../"):
        return "$RUNFILES_DIR/" + f.short_path[3:]
    return "$RUNFILES_DIR/$TEST_WORKSPACE/" + f.short_path

def _verilog_test_impl(ctx):
    # Collect the full source closure: deps + inline srcs + the testbench.
    dep_srcs = [d[VerilogInfo].transitive_srcs for d in ctx.attr.deps]
    dep_incs = [d[VerilogInfo].transitive_includes for d in ctx.attr.deps]
    dep_defs = [d[VerilogInfo].defines for d in ctx.attr.deps]

    srcs = depset(direct = ctx.files.srcs + ctx.files.tb, transitive = dep_srcs)
    incs = depset(direct = [], transitive = dep_incs)
    defs = depset(direct = ctx.attr.defines, transitive = dep_defs)

    verilator = ctx.file._verilator

    # Build the verilator command line out of runfiles-relative paths.
    parts = ['"$VERILATOR"', "--binary", "--timing", "-j", "0", "-Wno-fatal"]
    parts += ["--top-module", ctx.attr.top, "--Mdir", '"$WORK"', "-o", "sim"]
    for d in defs.to_list():
        parts.append("+define+" + d)
    for i in incs.to_list():
        parts.append("+incdir+" + i)
    for s in srcs.to_list():
        parts.append('"%s"' % _rf(s))

    script = """#!/usr/bin/env bash
set -euo pipefail
VERILATOR="{verilator}"
# Bundled gcc/make/perl live next to verilator; put them on PATH for --binary.
export PATH="$(dirname "$VERILATOR"):$PATH"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
{cmd}
exec "$WORK/sim"
""".format(
        verilator = _rf(verilator),
        cmd = " ".join(parts),
    )

    launcher = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(output = launcher, is_executable = True, content = script)

    runfiles = ctx.runfiles(
        files = ctx.files.srcs + ctx.files.tb,
        transitive_files = depset(transitive = [srcs, ctx.attr._verilator_env.files]),
    )
    return [DefaultInfo(executable = launcher, runfiles = runfiles)]

verilog_test = rule(
    implementation = _verilog_test_impl,
    test = True,
    doc = "Runs a Verilator simulation of a (System)Verilog testbench as a Bazel test.",
    attrs = {
        "tb": attr.label(
            mandatory = True,
            allow_single_file = [".v", ".sv"],
            doc = "Testbench source containing the top module (ends in $finish).",
        ),
        "top": attr.string(
            mandatory = True,
            doc = "Name of the testbench's top module.",
        ),
        "deps": attr.label_list(
            providers = [VerilogInfo],
            doc = "verilog_library targets under test.",
        ),
        "srcs": attr.label_list(
            allow_files = [".v", ".sv"],
            doc = "Extra sources compiled into the simulation.",
        ),
        "defines": attr.string_list(),
        "_verilator": attr.label(
            default = "@verilator_env//:verilator",
            allow_single_file = True,
            cfg = "exec",
        ),
        "_verilator_env": attr.label(
            default = "@verilator_env//:all",
            cfg = "exec",
        ),
    },
)
