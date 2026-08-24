"""Waveform tooling: `verilog_trace` + `surfer`/`wavepeek` runnables + the
`verilog_sim` convenience macro.

`verilog_trace` runs the Verilated design as a build action and captures a
waveform artifact (.vcd/.fst). The testbench opts in with a TRACE-guarded dump
block so the same tb stays fast under `verilog_test` (no trace) and dumps under
`verilog_trace` (compiled with --trace + `+define+TRACE`):

    `ifdef TRACE
      initial begin
        $dumpfile("dump");        // fixed name; verilog_trace collects ./dump
        $dumpvars(0, my_tb);
      end
    `endif

`surfer` opens a trace in the Surfer GUI (or `surver` headless server); `wavepeek`
runs the agent-oriented query CLI over it (`bazel run :x_wavepeek -- value ...`).
`verilog_sim` wires a test + trace + both viewers for one testbench in one call.
"""

load(":providers.bzl", "VerilogInfo", "VerilogTraceInfo")
load(":verilog_test.bzl", "verilog_test")

def _sources(ctx):
    """(srcs, includes, defines) depsets for the tb + deps."""
    srcs = depset(
        direct = ctx.files.srcs + ctx.files.tb,
        transitive = [d[VerilogInfo].transitive_srcs for d in ctx.attr.deps],
    )
    incs = depset(transitive = [d[VerilogInfo].transitive_includes for d in ctx.attr.deps])
    defs = depset(
        direct = ctx.attr.defines,
        transitive = [d[VerilogInfo].defines for d in ctx.attr.deps],
    )
    return srcs, incs, defs

def _verilog_trace_impl(ctx):
    srcs, incs, defs = _sources(ctx)
    ext = "vcd" if ctx.attr.format == "vcd" else "fst"
    trace = ctx.actions.declare_file(ctx.label.name + "." + ext)
    verilator = ctx.file._verilator
    trace_flag = "--trace" if ctx.attr.format == "vcd" else "--trace-fst"

    parts = [
        '"$VERILATOR"',
        "--binary",
        trace_flag,
        "--timing",
        "-j",
        "0",
        "-Wno-fatal",
        "+define+TRACE",
        "--top-module",
        ctx.attr.top,
        "--Mdir",
        '"$OBJ"',
        "-o",
        "sim",
    ]
    for d in defs.to_list():
        parts.append("+define+" + d)
    for i in incs.to_list():
        parts.append("+incdir+" + i)
    for s in srcs.to_list():
        parts.append('"%s"' % s.path)

    script = """#!/usr/bin/env bash
set -euo pipefail
VERILATOR="{verilator}"
# Bundled gcc/make/perl live next to verilator; put them on PATH for --binary.
export PATH="$(dirname "$VERILATOR"):$PATH"
OBJ="$(mktemp -d)"
RUN="$(mktemp -d)"
trap 'rm -rf "$OBJ" "$RUN"' EXIT
{cmd}
# The testbench's $dumpfile("dump") writes into the sim's CWD.
( cd "$RUN" && "$OBJ/sim" )
cp "$RUN/dump" "{out}"
""".format(
        verilator = verilator.path,
        cmd = " ".join(parts),
        out = trace.path,
    )

    runner = ctx.actions.declare_file(ctx.label.name + "_gen_trace.sh")
    ctx.actions.write(output = runner, is_executable = True, content = script)

    ctx.actions.run(
        executable = runner,
        inputs = depset(transitive = [srcs, ctx.attr._verilator_env.files]),
        outputs = [trace],
        mnemonic = "VerilogTrace",
        progress_message = "Tracing %s (%s)" % (ctx.label, ext),
    )

    return [
        DefaultInfo(files = depset([trace])),
        VerilogTraceInfo(trace = trace, format = ctx.attr.format),
    ]

verilog_trace = rule(
    implementation = _verilog_trace_impl,
    doc = "Runs a Verilator sim and captures a waveform trace (.vcd/.fst).",
    attrs = {
        "tb": attr.label(
            mandatory = True,
            allow_single_file = [".v", ".sv"],
            doc = "Testbench with a TRACE-guarded $dumpfile(\"dump\")/$dumpvars block.",
        ),
        "top": attr.string(mandatory = True, doc = "Testbench top module name."),
        "deps": attr.label_list(providers = [VerilogInfo]),
        "srcs": attr.label_list(allow_files = [".v", ".sv"]),
        "defines": attr.string_list(),
        "format": attr.string(
            default = "vcd",
            values = ["vcd", "fst"],
            doc = "Waveform format.",
        ),
        "_verilator": attr.label(
            default = "@verilator_env//:verilator",
            allow_single_file = True,
            cfg = "exec",
        ),
        "_verilator_env": attr.label(default = "@verilator_env//:all", cfg = "exec"),
    },
)

# --- Runnable viewers/queries ----------------------------------------------

def _runfiles_path(ctx, f):
    """Path of `f` under a run target's $0.runfiles root."""
    if f.short_path.startswith("../"):
        return f.short_path[3:]
    return ctx.workspace_name + "/" + f.short_path

def _trace_file(ctx):
    t = ctx.attr.trace
    if VerilogTraceInfo in t:
        return t[VerilogTraceInfo].trace
    return ctx.file.trace

def _launcher(ctx, tool, tool_files, trace, argv_tail):
    launcher = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = launcher,
        is_executable = True,
        content = """#!/usr/bin/env bash
set -euo pipefail
R="${{BASH_SOURCE[0]}}.runfiles"
if [[ ! -d "$R" && -n "${{RUNFILES_DIR:-}}" ]]; then
  R="$RUNFILES_DIR"
fi
TOOL="$R/{tool}"
TRACE="$R/{trace}"
exec "$TOOL" {tail}
""".format(
            tool = _runfiles_path(ctx, tool),
            trace = _runfiles_path(ctx, trace),
            tail = argv_tail,
        ),
    )
    runfiles = ctx.runfiles(files = [tool, trace], transitive_files = tool_files)
    return [DefaultInfo(executable = launcher, runfiles = runfiles)]

def _surfer_impl(ctx):
    trace = _trace_file(ctx)
    tool = ctx.file._surver if ctx.attr.server else ctx.file._surfer

    # surfer <trace> [args]  |  surver <trace> [args]  ("$@" forwards extra flags)
    return _launcher(ctx, tool, ctx.attr._surfer_files.files, trace, '"$TRACE" "$@"')

surfer = rule(
    implementation = _surfer_impl,
    executable = True,
    doc = "Open a waveform trace in Surfer (GUI) or serve it headless (server = True).",
    attrs = {
        "trace": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "A verilog_trace target (or a raw .vcd/.fst file).",
        ),
        "server": attr.bool(
            default = False,
            doc = "Use the headless `surver` server instead of the `surfer` GUI.",
        ),
        "_surfer": attr.label(default = "@surfer//:surfer", allow_single_file = True, cfg = "exec"),
        "_surver": attr.label(default = "@surfer//:surver", allow_single_file = True, cfg = "exec"),
        "_surfer_files": attr.label(default = "@surfer//:all", cfg = "exec"),
    },
)

def _wavepeek_impl(ctx):
    trace = _trace_file(ctx)

    # wavepeek <subcommand> [flags] --waves <trace>. Forward the user's args and
    # append --waves so `bazel run :x_wavepeek -- value --at 10ns --signals ...`
    # just works.
    return _launcher(ctx, ctx.file._wavepeek, ctx.attr._wavepeek_files.files, trace, '"$@" --waves "$TRACE"')

wavepeek = rule(
    implementation = _wavepeek_impl,
    executable = True,
    doc = "Query a waveform trace with wavepeek (agent-oriented CLI). " +
          "Args after `--` are passed through; --waves is filled in automatically.",
    attrs = {
        "trace": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "A verilog_trace target (or a raw .vcd/.fst file).",
        ),
        "_wavepeek": attr.label(default = "@wavepeek//:wavepeek", allow_single_file = True, cfg = "exec"),
        "_wavepeek_files": attr.label(default = "@wavepeek//:all", cfg = "exec"),
    },
)

# --- Convenience macro ------------------------------------------------------

def verilog_sim(name, top, tb, deps = [], srcs = [], defines = [], format = "vcd", size = "small", **kwargs):
    """test + trace + surfer + wavepeek for one testbench.

    Emits:
      <name>.test     -- verilog_test (validation)
      <name>.trace    -- verilog_trace (waveform artifact)
      <name>.surfer   -- open the trace in Surfer
      <name>.wavepeek -- query the trace with wavepeek

    Args:
      name: base name for the generated targets.
      top: testbench top module name.
      tb: testbench source file.
      deps: verilog_library targets under test.
      srcs: extra sources compiled into the sim.
      defines: preprocessor defines.
      format: waveform format for the trace ("vcd" or "fst").
      size: test size for the generated verilog_test.
      **kwargs: forwarded to the surfer target (e.g. server = True).
    """
    common = dict(top = top, tb = tb, deps = deps, srcs = srcs, defines = defines)

    verilog_test(name = name + ".test", size = size, **common)
    verilog_trace(name = name + ".trace", format = format, **common)
    surfer(name = name + ".surfer", trace = ":" + name + ".trace", **kwargs)
    wavepeek(name = name + ".wavepeek", trace = ":" + name + ".trace")
