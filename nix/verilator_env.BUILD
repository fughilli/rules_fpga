# BUILD file injected into the `verilator_env` buildEnv repo. `all` carries the
# merged bin/ (verilator, g++, make, perl) plus verilator's share/include tree.
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all",
    srcs = glob(
        ["**"],
        allow_empty = True,
    ),
)

filegroup(
    name = "verilator",
    srcs = ["bin/verilator"],
)

# Verilator runtime sources compiled alongside the generated model (see the mk's
# VM_GLOBAL_FAST list), split by trace mode so VCD/no-trace builds don't drag in
# the FST (gtkwave/zlib) runtime.
filegroup(
    name = "runtime_base",
    srcs = [
        "share/verilator/include/verilated.cpp",
        "share/verilator/include/verilated_threads.cpp",
        "share/verilator/include/verilated_timing.cpp",
    ],
)

filegroup(
    name = "runtime_vcd",
    srcs = ["share/verilator/include/verilated_vcd_c.cpp"],
)

filegroup(
    name = "runtime_fst",
    srcs = ["share/verilator/include/verilated_fst_c.cpp"],
)

# zlib (from the buildEnv) for the FST runtime, which #includes gtkwave/fstapi.c.
filegroup(
    name = "zlib_headers",
    srcs = [
        "include/zconf.h",
        "include/zlib.h",
    ],
)

filegroup(
    name = "zlib_lib",
    srcs = ["lib/libz.a"],
)

# Verilator runtime headers (verilated.h, vltstd/*, ...) -> cc private_hdrs.
filegroup(
    name = "headers",
    srcs = glob(
        ["share/verilator/include/**/*.h"],
        allow_empty = True,
    ),
)

# Non-header sources #included directly by the runtime (gtkwave/fastlz.c, lz4.c,
# ...). Passed as additional_inputs (staged but not separately compiled).
filegroup(
    name = "aux_srcs",
    srcs = glob(
        ["share/verilator/include/**/*.c"],
        allow_empty = True,
    ),
)
