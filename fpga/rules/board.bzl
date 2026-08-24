"""`fpga_board_info` provides FpgaBoardInfo; `fpga_board` is a convenience macro.

An FPGA board is described by two pieces:
  * a `platform()` carrying the family + board constraint_values (drives
    toolchain resolution and the //fpga/boards:current select), and
  * an `fpga_board_info` target carrying the device strings for the tools.

The `fpga_board` macro emits both. You still (a) declare the board's
constraint_value under //fpga/constraints and (b) add a case to the
//fpga/boards:current select -- those are the two spots a new board is wired in.
"""

load(":providers.bzl", "FpgaBoardInfo")

def _fpga_board_info_impl(ctx):
    return [FpgaBoardInfo(
        family = ctx.attr.family,
        part = ctx.attr.part,
        package = ctx.attr.package,
        packer_device = ctx.attr.packer_device,
        freq_mhz = ctx.attr.freq_mhz,
        flash_args = ctx.attr.flash_args,
    )]

fpga_board_info = rule(
    implementation = _fpga_board_info_impl,
    doc = "Device/part parameters for an FPGA board (see FpgaBoardInfo).",
    attrs = {
        "family": attr.string(mandatory = True, values = ["ice40", "gowin"]),
        "part": attr.string(mandatory = True, doc = "nextpnr device string."),
        "package": attr.string(default = "", doc = "nextpnr-ice40 --package value."),
        "packer_device": attr.string(default = "", doc = "gowin_pack -d value."),
        "freq_mhz": attr.string(default = "", doc = "Target clock (MHz) for P&R timing."),
        "flash_args": attr.string_list(doc = "Extra args for the flash tool."),
    },
)

def fpga_board(
        name,
        family,
        board_constraint,
        part,
        package = "",
        packer_device = "",
        freq_mhz = "",
        flash_args = None,
        visibility = None):
    """Emit `<name>` (a platform) and `<name>_info` (an fpga_board_info).

    Args:
      name: platform target name (e.g. "tangnano9k").
      family: "ice40" or "gowin".
      board_constraint: label of this board's constraint_value under //fpga/constraints.
      part: nextpnr device string.
      package: nextpnr-ice40 package (ice40 only).
      packer_device: gowin_pack device (gowin only).
      freq_mhz: target clock for the P&R timing estimate.
      flash_args: extra flash-tool args.
      visibility: target visibility.
    """
    native.platform(
        name = name,
        constraint_values = ["//fpga/constraints:" + family, board_constraint],
        visibility = visibility,
    )
    fpga_board_info(
        name = name + "_info",
        family = family,
        part = part,
        package = package,
        packer_device = packer_device,
        freq_mhz = freq_mhz,
        flash_args = flash_args or [],
        visibility = visibility,
    )
