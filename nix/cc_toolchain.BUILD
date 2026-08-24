# BUILD injected into the Nix `cc_toolchain` repo (gcc + binutils buildEnv).
#
# The cc_toolchain + its config live here, next to the tools, so tool_paths
# ("bin/g++", ...) are normalized package-relative paths. We use Bazel's built-in
# unix_cc_toolchain_config (from @bazel_tools, which IS visible from this
# generated repo) rather than a rule from @rules_fpga (which is NOT visible from
# an isolated nix_pkg repo). The toolchain() that binds this under the dedicated
# type lives in //fpga/toolchains/cc (that package can see @cc_toolchain).
load("@bazel_tools//tools/cpp:unix_cc_toolchain_config.bzl", "cc_toolchain_config")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all",
    srcs = glob(
        ["**"],
        allow_empty = True,
    ),
)

cc_toolchain_config(
    name = "nix_cc_config",
    abi_libc_version = "local",
    abi_version = "local",
    compile_flags = ["-fno-strict-aliasing"],
    compiler = "gcc",
    cpu = "local",
    # The sandbox exposes the host /nix/store read-only, so the Nix gcc wrapper's
    # absolute sysroot/header paths resolve.
    cxx_builtin_include_directories = ["/nix/store"],
    cxx_flags = ["-std=gnu++20"],
    host_system_name = "local",
    link_flags = [
        "-pthread",
        "-lm",
    ],
    # BFD ld lacks --start-lib/--end-lib (a gold/lld feature); linking objects
    # directly also avoids dropping the object that defines main().
    supports_start_end_lib = False,
    target_libc = "local",
    target_system_name = "local",
    tool_paths = {
        "gcc": "bin/g++",
        "cpp": "bin/cpp",
        "ar": "bin/ar",
        "ld": "bin/ld",
        "nm": "bin/nm",
        "objdump": "bin/objdump",
        "objcopy": "bin/objcopy",
        "strip": "bin/strip",
        # Coverage tools are unused by the sim rules; point them at gcov so the
        # config's mandatory lookups succeed.
        "gcov": "bin/gcov",
        "llvm-cov": "bin/gcov",
    },
    toolchain_identifier = "nix-gcc",
)

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
