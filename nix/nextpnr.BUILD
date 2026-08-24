# BUILD file injected into the Nix-provided `nextpnr` repo. nixpkgs builds
# nextpnr with all architectures, so this one repo provides both the ice40 and
# the himbaechel (gowin) place-and-route binaries.
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all",
    srcs = glob(
        ["**"],
        allow_empty = True,
    ),
)

filegroup(
    name = "nextpnr-ice40",
    srcs = ["bin/nextpnr-ice40"],
)

filegroup(
    name = "nextpnr-himbaechel",
    srcs = ["bin/nextpnr-himbaechel"],
)
