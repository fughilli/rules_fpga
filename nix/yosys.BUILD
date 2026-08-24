# BUILD file injected into the Nix-provided `yosys` repo.
#
# `all` is the full package tree; it is fed as action inputs so that yosys'
# relative data dir (share/yosys) materializes in the sandbox. yosys also has an
# absolute YOSYS_DATDIR baked in by nixpkgs, readable from /nix/store, so both
# resolution paths work.
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all",
    srcs = glob(
        ["**"],
        allow_empty = True,
    ),
)

filegroup(
    name = "yosys",
    srcs = ["bin/yosys"],
)
