# BUILD file injected into the Nix `cc_toolchain` repo (gcc + binutils buildEnv).
#
# The cc_toolchain + toolchain() live here, next to the tools, so the config's
# tool_paths ("bin/g++", "bin/ar", ...) resolve relative to this package.
# @@// is a canonical reference to the main repo (bypasses repo mapping, which in
# this injected build_file doesn't carry an apparent name for rules_fpga).
load("@@//fpga/toolchains/cc:cc_toolchain_config.bzl", "nix_cc_toolchain_config")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all",
    srcs = glob(
        ["**"],
        allow_empty = True,
    ),
)

filegroup(
    name = "cxx",
    srcs = ["bin/g++"],
)

nix_cc_toolchain_config(name = "nix_cc_config")

cc_toolchain(
    name = "nix_cc",
    all_files = ":all",
    ar_files = ":all",
    as_files = ":all",
    compiler_files = ":all",
    dwp_files = ":all",
    linker_files = ":all",
    objcopy_files = ":all",
    strip_files = ":all",
    supports_param_files = 0,
    toolchain_config = ":nix_cc_config",
)

toolchain(
    name = "nix_cc_toolchain",
    toolchain = ":nix_cc",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
)
