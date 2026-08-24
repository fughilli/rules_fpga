"""`verilog_library` and `verilog_top`: aggregate Verilog sources into a closure.

Neither rule runs a tool -- they only build up a `VerilogInfo` depset that the
downstream `verilog_test` and `synthesizable_bitstream` rules consume. This is
the same "library is just metadata, the leaf rule runs the flow" shape used by
cc_library/cc_binary.
"""

load(":providers.bzl", "VerilogInfo", "VerilogTopInfo")

# Recognized Verilog source / header extensions.
_SRC_EXTS = [".v", ".sv"]
_HDR_EXTS = [".vh", ".svh", ".v", ".sv"]

def _merge(srcs, includes, defines, deps):
    """Combine direct srcs/includes/defines with those from deps into VerilogInfo."""
    return VerilogInfo(
        transitive_srcs = depset(
            direct = srcs,
            transitive = [d[VerilogInfo].transitive_srcs for d in deps],
        ),
        transitive_includes = depset(
            direct = includes,
            transitive = [d[VerilogInfo].transitive_includes for d in deps],
        ),
        defines = depset(
            direct = defines,
            transitive = [d[VerilogInfo].defines for d in deps],
        ),
    )

def _include_dirs(ctx):
    """Include dirs = the dir of every header, plus explicit package-relative dirs."""
    dirs = {}
    for h in ctx.files.hdrs:
        dirs[h.dirname] = True
    for inc in ctx.attr.includes:
        # Interpret `includes` relative to the declaring package.
        if inc == "" or inc == ".":
            dirs[ctx.label.package] = True
        else:
            dirs[ctx.label.package + "/" + inc] = True
    return dirs.keys()

def _verilog_library_impl(ctx):
    info = _merge(
        srcs = ctx.files.srcs + ctx.files.hdrs,
        includes = _include_dirs(ctx),
        defines = ctx.attr.defines,
        deps = ctx.attr.deps,
    )
    return [
        DefaultInfo(files = depset(ctx.files.srcs + ctx.files.hdrs)),
        info,
    ]

verilog_library = rule(
    implementation = _verilog_library_impl,
    doc = "A collection of Verilog/SystemVerilog sources and their dependencies.",
    attrs = {
        "srcs": attr.label_list(
            allow_files = _SRC_EXTS,
            doc = "Verilog/SystemVerilog source files compiled into the design.",
        ),
        "hdrs": attr.label_list(
            allow_files = _HDR_EXTS,
            doc = "Headers made available via `include (their dirs become -I paths).",
        ),
        "deps": attr.label_list(
            providers = [VerilogInfo],
            doc = "Other verilog_library targets this one depends on.",
        ),
        "includes": attr.string_list(
            doc = "Additional include directories, relative to this package.",
        ),
        "defines": attr.string_list(
            doc = "Preprocessor defines (`NAME` or `NAME=value`).",
        ),
    },
)

def _verilog_top_impl(ctx):
    info = _merge(
        srcs = ctx.files.srcs,
        includes = _include_dirs(ctx),
        defines = ctx.attr.defines,
        deps = ctx.attr.deps,
    )
    return [
        DefaultInfo(files = info.transitive_srcs),
        info,
        VerilogTopInfo(top_module = ctx.attr.top, verilog = info),
    ]

verilog_top = rule(
    implementation = _verilog_top_impl,
    doc = "Designates a top-level module plus the Verilog closure that implements it. " +
          "Consumed by synthesizable_bitstream.",
    attrs = {
        "top": attr.string(
            mandatory = True,
            doc = "Name of the top-level module to synthesize.",
        ),
        "deps": attr.label_list(
            providers = [VerilogInfo],
            doc = "verilog_library targets that make up the design.",
        ),
        "srcs": attr.label_list(
            allow_files = _SRC_EXTS,
            doc = "Optional top-level sources declared inline instead of via a library.",
        ),
        "hdrs": attr.label_list(allow_files = _HDR_EXTS),
        "includes": attr.string_list(),
        "defines": attr.string_list(),
    },
)
