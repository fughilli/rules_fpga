"""A minimal `cc_toolchain_config` backed by the Nix-provided gcc/binutils.

Kept deliberately small: tool paths are relative to the cc_toolchain's package
(the Nix `cc_toolchain` repo root, where bin/ lives), and the Nix compiler
wrapper already knows its own sysroot + system headers, so we only have to let
the sandbox read them by listing /nix/store as a builtin include dir. The
compiler driver is g++ so C++ (incl. -std=c++20 coroutines for Verilator
--timing) compiles and links against libstdc++ with no extra wiring.
"""

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load(
    "@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl",
    "feature",
    "flag_group",
    "flag_set",
    "tool_path",
)

_COMPILE_ACTIONS = [
    ACTION_NAMES.c_compile,
    ACTION_NAMES.cpp_compile,
    ACTION_NAMES.cpp_header_parsing,
    ACTION_NAMES.cpp_module_compile,
    ACTION_NAMES.cpp_module_codegen,
    ACTION_NAMES.assemble,
    ACTION_NAMES.preprocess_assemble,
]

_LINK_ACTIONS = [
    ACTION_NAMES.cpp_link_executable,
    ACTION_NAMES.cpp_link_dynamic_library,
    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
]

def _impl(ctx):
    tool_paths = [
        tool_path(name = "gcc", path = ctx.attr.compiler),
        tool_path(name = "cpp", path = ctx.attr.cpp),
        tool_path(name = "ar", path = ctx.attr.ar),
        tool_path(name = "ld", path = ctx.attr.ld),
        tool_path(name = "nm", path = ctx.attr.nm),
        tool_path(name = "objdump", path = ctx.attr.objdump),
        tool_path(name = "objcopy", path = ctx.attr.objcopy),
        tool_path(name = "strip", path = ctx.attr.strip),
    ]

    compile_feature = feature(
        name = "default_compile_flags",
        enabled = True,
        flag_sets = [flag_set(
            actions = _COMPILE_ACTIONS,
            flag_groups = [flag_group(flags = ctx.attr.compile_flags)],
        )] if ctx.attr.compile_flags else [],
    )
    link_feature = feature(
        name = "default_link_flags",
        enabled = True,
        flag_sets = [flag_set(
            actions = _LINK_ACTIONS,
            flag_groups = [flag_group(flags = ctx.attr.link_flags)],
        )] if ctx.attr.link_flags else [],
    )

    # BFD ld lacks --start-lib/--end-lib (a gold/lld feature). Disabling this
    # stops Bazel wrapping objects in a lazy lib group -- which also otherwise
    # drops the object defining main(). Objects are linked directly instead.
    no_start_end_lib = feature(name = "supports_start_end_lib", enabled = False)

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        toolchain_identifier = "nix-gcc",
        host_system_name = "local",
        target_system_name = "local",
        target_cpu = ctx.attr.target_cpu,
        target_libc = "glibc",
        compiler = "gcc",
        abi_version = "local",
        abi_libc_version = "local",
        tool_paths = tool_paths,
        cxx_builtin_include_directories = ctx.attr.builtin_includes,
        features = [no_start_end_lib, compile_feature, link_feature],
    )

nix_cc_toolchain_config = rule(
    implementation = _impl,
    provides = [CcToolchainConfigInfo],
    attrs = {
        "compiler": attr.string(default = "bin/g++"),
        "cpp": attr.string(default = "bin/cpp"),
        "ar": attr.string(default = "bin/ar"),
        "ld": attr.string(default = "bin/ld"),
        "nm": attr.string(default = "bin/nm"),
        "objdump": attr.string(default = "bin/objdump"),
        "objcopy": attr.string(default = "bin/objcopy"),
        "strip": attr.string(default = "bin/strip"),
        "target_cpu": attr.string(default = "local"),
        "builtin_includes": attr.string_list(default = ["/nix/store"]),
        "compile_flags": attr.string_list(default = ["-std=gnu++20", "-fno-strict-aliasing"]),
        # gold (from the same binutils) supports the --start-lib/--end-lib object
        # grouping Bazel emits at link; BFD ld does not.
        "link_flags": attr.string_list(default = ["-fuse-ld=gold", "-pthread", "-lm", "-latomic"]),
    },
)
