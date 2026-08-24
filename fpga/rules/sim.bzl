"""Verilator simulation via Bazel's cc toolchain (no `make`).

The design is Verilated with `verilator --cc --main` (C++ output + a generated
main), then the generated tree plus the Verilator runtime sources are compiled
and linked by Bazel's cc actions against the hand-written Nix cc_toolchain
(//fpga/toolchains/cc). That gives per-object caching, Bazel parallelism, and
remote-execution compatibility -- none of which Verilator's internal `make` had.

  verilog_test   -- build the sim exe (no trace) and run it as a Bazel test.
  verilog_trace  -- build the sim exe with tracing, run it, capture .vcd/.fst.
  surfer/wavepeek -- view / query a trace.
  verilog_sim    -- macro wiring .test/.trace/.surfer/.wavepeek for one tb.

A traceable testbench opts in with a TRACE-guarded dump block, so the same tb is
trace-free (and cheaper to build) under verilog_test and dumps under
verilog_trace (which verilates with --trace + `+define+TRACE`):

    `ifdef TRACE
      initial begin
        $dumpfile("dump");        // fixed name; verilog_trace collects ./dump
        $dumpvars(0, my_tb);
      end
    `endif
"""

load(":providers.bzl", "VerilogInfo", "VerilogTraceInfo")

# Dedicated cc toolchain type (not @bazel_tools//tools/cpp) so this ruleset's Nix
# cc toolchain never hijacks a consumer repo's host C++ resolution.
_CC_TOOLCHAIN_TYPE = "//fpga/toolchains/cc:toolchain_type"

def _find_cc_toolchain(ctx):
    tc = ctx.toolchains[_CC_TOOLCHAIN_TYPE]
    return tc.cc if hasattr(tc, "cc") else tc

# ---------------------------------------------------------------------------
# Verilate (--cc --main) -> compile+link with Bazel's cc toolchain.
# ---------------------------------------------------------------------------

_PREFIX = "Vsim"

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

def _verilate(ctx, trace_mode):
    """Run `verilator --cc --main`, returning the generated-sources tree artifact."""
    srcs, incs, defs = _sources(ctx)
    gen = ctx.actions.declare_directory(ctx.label.name + ".verilated")

    args = ctx.actions.args()
    args.add_all(["--cc", "--main", "--timing", "-Wno-fatal"])
    args.add("-Mdir", gen.path)
    args.add("--prefix", _PREFIX)
    args.add("--top-module", ctx.attr.top)
    if trace_mode == "vcd":
        args.add_all(["--trace", "+define+TRACE"])
    elif trace_mode == "fst":
        args.add_all(["--trace-fst", "+define+TRACE"])
    for d in defs.to_list():
        args.add("+define+" + d)
    for i in incs.to_list():
        args.add("+incdir+" + i)
    args.add_all(srcs)

    ctx.actions.run(
        executable = ctx.file._verilator,
        arguments = [args],
        inputs = depset(transitive = [srcs, ctx.attr._verilator_env.files]),
        outputs = [gen],
        mnemonic = "Verilate",
        progress_message = "Verilating %s" % ctx.label,
    )
    return gen

# VM_* defines matching how the model was verilated (see verilated.mk).
_BASE_DEFINES = ["VM_COVERAGE=0", "VM_SC=0", "VM_TIMING=1", "VM_TRACE_SAIF=0", "VL_TIME_CONTEXT"]
_TRACE_DEFINES = {
    "none": ["VM_TRACE=0", "VM_TRACE_VCD=0", "VM_TRACE_FST=0"],
    "vcd": ["VM_TRACE=1", "VM_TRACE_VCD=1", "VM_TRACE_FST=0"],
    "fst": ["VM_TRACE=1", "VM_TRACE_VCD=0", "VM_TRACE_FST=1"],
}

def _dir_of(files, basename):
    for f in files:
        if f.basename == basename:
            return f.dirname
    fail("%s not found" % basename)

def _split_sources(ctx, gen):
    """Split the verilated tree into a .cpp-only srcs dir and a .h-only hdrs dir.

    The compile action globs `*.cpp` from the srcs dir, so the generated
    .h/.mk/.d are kept out of it; the .cpp reach their headers via -I<hdrs>.
    """
    gen_srcs = ctx.actions.declare_directory(ctx.label.name + ".srcs")
    gen_hdrs = ctx.actions.declare_directory(ctx.label.name + ".hdrs")
    ctx.actions.run_shell(
        inputs = [gen],
        outputs = [gen_srcs, gen_hdrs],
        command = 'set -e; mkdir -p "{s}" "{h}"; cp "{g}"/*.cpp "{s}"/; cp "{g}"/*.h "{h}"/'.format(
            g = gen.path,
            s = gen_srcs.path,
            h = gen_hdrs.path,
        ),
        mnemonic = "VerilateSplit",
        progress_message = "Splitting verilated sources for %s" % ctx.label,
    )
    return gen_srcs, gen_hdrs

def _build_exe(ctx, gen, trace_mode):
    """Compile the model + Verilator runtime per file, then link an executable.

    The fixed runtime .cpp compile individually (cached across every sim). The
    dynamic model .cpp go through cc_common.compile as a tree artifact, which
    Bazel compiles with a CppCompileActionTemplate -- one spawn per generated
    file, each content-cached -- so a small Verilog edit only recompiles the few
    generated files that actually changed. cc_common.link links it all (with the
    toolchain handling crt/libstdc++/rpath).
    """
    gen_srcs, gen_hdrs = _split_sources(ctx, gen)
    cc_toolchain = _find_cc_toolchain(ctx)
    feature_config = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    # Runtime sources + FST-only zlib wiring, keyed on trace mode.
    runtime = list(ctx.files._runtime_base)
    private_hdrs = list(ctx.files._verilator_headers)
    system_includes = []
    link_flags = []
    link_inputs = []
    if trace_mode == "vcd":
        runtime += ctx.files._runtime_vcd
    elif trace_mode == "fst":
        runtime += ctx.files._runtime_fst
        private_hdrs += ctx.files._zlib_headers
        system_includes.append(_dir_of(ctx.files._zlib_headers, "zlib.h"))

        # Statically link libz.a (positional), so the sim exe needs no runtime .so.
        link_flags.append(ctx.files._zlib_lib[0].path)
        link_inputs = ctx.files._zlib_lib

    inc = _dir_of(ctx.files._runtime_base, "verilated.cpp")
    _, compilation_outputs = cc_common.compile(
        actions = ctx.actions,
        feature_configuration = feature_config,
        cc_toolchain = cc_toolchain,
        name = ctx.label.name,
        srcs = [gen_srcs] + runtime,
        private_hdrs = private_hdrs,
        additional_inputs = ctx.files._verilator_aux + [gen_hdrs],
        includes = [gen_hdrs.path, inc, inc + "/vltstd"],
        system_includes = system_includes,
        defines = _BASE_DEFINES + _TRACE_DEFINES[trace_mode],
        user_compile_flags = ["-std=gnu++20", "-fcoroutines", "-Os", "-Wno-attributes"],
    )

    # Link with the toolchain's g++ driver directly, passing objects explicitly.
    # We avoid cc_common.link because it wraps the object tree in
    # -Wl,--start-lib/--end-lib, which only gold/lld accept -- macOS ld64 and BFD
    # ld reject it. An explicit object list works with every system linker, and
    # the g++ driver still supplies crt/libstdc++/rpath.
    objects = compilation_outputs.objects or compilation_outputs.pic_objects
    obj_args = [
        '"%s"/*.o' % o.path if o.is_directory else '"%s"' % o.path
        for o in objects
    ]
    exe = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.run_shell(
        inputs = depset(direct = objects + link_inputs, transitive = [cc_toolchain.all_files]),
        outputs = [exe],
        command = 'set -e; "{cxx}" -o "{exe}" {objs} {flags}'.format(
            cxx = cc_toolchain.compiler_executable,
            exe = exe.path,
            objs = " ".join(obj_args),
            flags = " ".join(["-pthread", "-lm"] + link_flags),
        ),
        mnemonic = "VerilogLink",
        progress_message = "Linking %s" % ctx.label,
    )
    return exe

# Attributes + rule bits shared by verilog_test and verilog_trace.
_SIM_ATTRS = {
    "tb": attr.label(
        mandatory = True,
        allow_single_file = [".v", ".sv"],
        doc = "Testbench source containing the top module (ends in $finish).",
    ),
    "top": attr.string(mandatory = True, doc = "Testbench top module name."),
    "deps": attr.label_list(providers = [VerilogInfo], doc = "verilog_library targets under test."),
    "srcs": attr.label_list(allow_files = [".v", ".sv"], doc = "Extra sources compiled into the sim."),
    "defines": attr.string_list(),
    "_verilator": attr.label(default = "@verilator_env//:verilator", allow_single_file = True, cfg = "exec"),
    "_verilator_env": attr.label(default = "@verilator_env//:all", cfg = "exec"),
    "_runtime_base": attr.label(default = "@verilator_env//:runtime_base", allow_files = True),
    "_runtime_vcd": attr.label(default = "@verilator_env//:runtime_vcd", allow_files = True),
    "_runtime_fst": attr.label(default = "@verilator_env//:runtime_fst", allow_files = True),
    "_verilator_headers": attr.label(default = "@verilator_env//:headers", allow_files = True),
    "_verilator_aux": attr.label(default = "@verilator_env//:aux_srcs", allow_files = True),
    "_zlib_headers": attr.label(default = "@verilator_env//:zlib_headers", allow_files = True),
    "_zlib_lib": attr.label(default = "@verilator_env//:zlib_lib", allow_files = True),
}

def _verilog_test_impl(ctx):
    exe = _build_exe(ctx, _verilate(ctx, "none"), "none")
    return [DefaultInfo(executable = exe)]

verilog_test = rule(
    implementation = _verilog_test_impl,
    test = True,
    doc = "Verilator simulation of a (System)Verilog testbench, built with Bazel's cc toolchain.",
    attrs = _SIM_ATTRS,
    toolchains = [_CC_TOOLCHAIN_TYPE],
    fragments = ["cpp"],
)

def _verilog_trace_impl(ctx):
    exe = _build_exe(ctx, _verilate(ctx, ctx.attr.format), ctx.attr.format)
    ext = "vcd" if ctx.attr.format == "vcd" else "fst"
    trace = ctx.actions.declare_file(ctx.label.name + "." + ext)

    # The exe's $dumpfile("dump") writes into the action's cwd (execroot); move it.
    ctx.actions.run_shell(
        inputs = [exe],
        outputs = [trace],
        command = 'set -e; "%s"; cp dump "%s"' % (exe.path, trace.path),
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
    attrs = dict(_SIM_ATTRS, format = attr.string(
        default = "vcd",
        values = ["vcd", "fst"],
        doc = "Waveform format.",
    )),
    toolchains = [_CC_TOOLCHAIN_TYPE],
    fragments = ["cpp"],
)

# ---------------------------------------------------------------------------
# Runnable viewers / queries.
# ---------------------------------------------------------------------------

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
    # append --waves so `bazel run :x.wavepeek -- value --at 10ns --signals ...`
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

# ---------------------------------------------------------------------------
# Convenience macro.
# ---------------------------------------------------------------------------

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
