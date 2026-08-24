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
