# BUILD file injected into the Nix-provided `apicula` repo: gowin_pack turns the
# nextpnr-himbaechel output into a Gowin .fs bitstream.
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all",
    srcs = glob(
        ["**"],
        allow_empty = True,
    ),
)

filegroup(
    name = "gowin_pack",
    srcs = ["bin/gowin_pack"],
)
