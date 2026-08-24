# BUILD file injected into the Nix-provided `surfer` repo. Provides the GUI
# viewer `surfer` and the headless server `surver` (serve a trace from a
# machine without a display; connect the desktop app to it).
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all",
    srcs = glob(
        ["**"],
        allow_empty = True,
    ),
)

filegroup(
    name = "surfer",
    srcs = ["bin/surfer"],
)

filegroup(
    name = "surver",
    srcs = ["bin/surver"],
)
