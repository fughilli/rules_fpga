# BUILD file injected into the Nix-provided `icestorm` repo: icepack turns the
# nextpnr .asc into a .bin bitstream; iceprog flashes it.
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all",
    srcs = glob(
        ["**"],
        allow_empty = True,
    ),
)

filegroup(
    name = "icepack",
    srcs = ["bin/icepack"],
)

filegroup(
    name = "iceprog",
    srcs = ["bin/iceprog"],
)
