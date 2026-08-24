"""The `fpga_toolchain` rule: wraps the Nix-provided binaries into a toolchain.

One instance per family (ice40, gowin). Each binary is taken as a single-file
label plus a `*_files` filegroup of the whole Nix package tree; the package tree
is threaded into every action as inputs so tools find their relative data dirs
(the absolute /nix/store references work too, since the sandbox exposes the host
store read-only). All tool labels are cfg="exec" -- yosys/nextpnr/etc. run on
the build host regardless of which board we target.
"""

load("//fpga/rules:providers.bzl", "FpgaToolchainInfo")

def _fpga_toolchain_impl(ctx):
    return [platform_common.ToolchainInfo(
        fpga = FpgaToolchainInfo(
            yosys = ctx.file.yosys,
            yosys_files = depset(ctx.files.yosys_files),
            synth_command = ctx.attr.synth_command,
            nextpnr = ctx.file.nextpnr,
            nextpnr_files = depset(ctx.files.nextpnr_files),
            packer = ctx.file.packer,
            packer_files = depset(ctx.files.packer_files),
            flash_tool = ctx.file.flash_tool,
            flash_files = depset(ctx.files.flash_files),
        ),
    )]

fpga_toolchain = rule(
    implementation = _fpga_toolchain_impl,
    doc = "Bundles the synth/pnr/pack/flash binaries for one FPGA family.",
    attrs = {
        "synth_command": attr.string(
            mandatory = True,
            doc = "yosys synth pass: 'synth_ice40' or 'synth_gowin'.",
        ),
        "yosys": attr.label(allow_single_file = True, cfg = "exec", mandatory = True),
        "yosys_files": attr.label(cfg = "exec", mandatory = True),
        "nextpnr": attr.label(allow_single_file = True, cfg = "exec", mandatory = True),
        "nextpnr_files": attr.label(cfg = "exec", mandatory = True),
        "packer": attr.label(allow_single_file = True, cfg = "exec", mandatory = True),
        "packer_files": attr.label(cfg = "exec", mandatory = True),
        "flash_tool": attr.label(allow_single_file = True, cfg = "exec", mandatory = True),
        "flash_files": attr.label(cfg = "exec", mandatory = True),
    },
)
