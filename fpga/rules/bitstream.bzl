"""`synthesizable_bitstream`: a verilog_top closure -> an FPGA bitstream.

The rule carries a Bazel *incoming* transition keyed on its `platform` attribute
(the same idea as embedded_binary's board transition). Retargeting `--platforms`
to the board platform does three things at once:

  1. Toolchain resolution picks the ice40 or gowin `fpga_toolchain` (each is
     `target_compatible_with` its `//fpga/constraints:family` value).
  2. The `//fpga/boards:current` select (an implicit dep) resolves to the right
     `FpgaBoardInfo` for device flags.
  3. Any `select()` in the design's own sources sees the board platform.

The flow is the classic open one, branched by family:

  ice40: yosys synth_ice40 -json -> nextpnr-ice40 --asc -> icepack -> .bin
  gowin: yosys synth_gowin -json -> nextpnr-himbaechel --write -> gowin_pack -> .fs
"""

load(
    ":providers.bzl",
    "FpgaBitstreamInfo",
    "FpgaBoardInfo",
    "VerilogTopInfo",
)

_TOOLCHAIN_TYPE = "//fpga/toolchains:toolchain_type"

def _board_transition_impl(_settings, attr):
    # Retarget the whole subtree to the board platform named on the rule.
    return {"//command_line_option:platforms": [str(attr.platform)]}

_board_transition = transition(
    implementation = _board_transition_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _yosys_synth(ctx, tc, top_info):
    """Run yosys, producing a JSON netlist. Returns the netlist File."""
    vinfo = top_info.verilog
    srcs = vinfo.transitive_srcs.to_list()
    netlist = ctx.actions.declare_file(ctx.label.name + ".json")

    read = ["read_verilog", "-sv"]
    for d in vinfo.defines.to_list():
        read.append("-D" + d)
    for inc in vinfo.transitive_includes.to_list():
        read.append("-I" + inc)
    for s in srcs:
        read.append(s.path)

    script = "{read}; {synth} -top {top} -json {out}".format(
        read = " ".join(read),
        synth = tc.synth_command,
        top = top_info.top_module,
        out = netlist.path,
    )

    ctx.actions.run(
        executable = tc.yosys,
        arguments = ["-q", "-p", script],
        inputs = depset(direct = srcs, transitive = [tc.yosys_files]),
        outputs = [netlist],
        mnemonic = "YosysSynth",
        progress_message = "Synthesizing %s with yosys (%s)" % (ctx.label, tc.synth_command),
    )
    return netlist

def _nextpnr(ctx, tc, board, netlist, constraints):
    """Place & route. Returns the family-specific P&R output File."""
    if board.family == "ice40":
        out = ctx.actions.declare_file(ctx.label.name + ".asc")
        args = [
            "--" + board.part,
            "--json",
            netlist.path,
            "--pcf",
            constraints.path,
            "--asc",
            out.path,
        ]
        if board.package:
            args += ["--package", board.package]
        if board.freq_mhz:
            args += ["--freq", board.freq_mhz]
    elif board.family == "gowin":
        out = ctx.actions.declare_file(ctx.label.name + "_pnr.json")
        args = [
            "--device",
            board.part,
            "--vopt",
            "cst=" + constraints.path,
            "--json",
            netlist.path,
            "--write",
            out.path,
        ]
        if board.freq_mhz:
            args += ["--freq", board.freq_mhz]
    else:
        fail("unsupported FPGA family: %s" % board.family)

    ctx.actions.run(
        executable = tc.nextpnr,
        arguments = args,
        inputs = depset(direct = [netlist, constraints], transitive = [tc.nextpnr_files]),
        outputs = [out],
        mnemonic = "NextpnrPlaceRoute",
        progress_message = "Place & route %s (%s)" % (ctx.label, board.part),
    )
    return out

def _pack(ctx, tc, board, pnr_out):
    """Pack the P&R result into a bitstream. Returns the bitstream File."""
    if board.family == "ice40":
        bit = ctx.actions.declare_file(ctx.label.name + ".bin")
        args = [pnr_out.path, bit.path]
    elif board.family == "gowin":
        bit = ctx.actions.declare_file(ctx.label.name + ".fs")
        args = ["-d", board.packer_device, "-o", bit.path, pnr_out.path]
    else:
        fail("unsupported FPGA family: %s" % board.family)

    ctx.actions.run(
        executable = tc.packer,
        arguments = args,
        inputs = depset(direct = [pnr_out], transitive = [tc.packer_files]),
        outputs = [bit],
        mnemonic = "FpgaPack",
        progress_message = "Packing bitstream %s" % ctx.label,
    )
    return bit

def _synthesizable_bitstream_impl(ctx):
    tc = ctx.toolchains[_TOOLCHAIN_TYPE].fpga
    board = ctx.attr._board[FpgaBoardInfo]
    top_info = ctx.attr.top[VerilogTopInfo]

    netlist = _yosys_synth(ctx, tc, top_info)
    pnr_out = _nextpnr(ctx, tc, board, netlist, ctx.file.constraints)
    bitstream = _pack(ctx, tc, board, pnr_out)

    return [
        DefaultInfo(files = depset([bitstream])),
        FpgaBitstreamInfo(
            bitstream = bitstream,
            board = board,
            flash_tool = tc.flash_tool,
            flash_files = tc.flash_files,
        ),
        # Intermediate artifacts for debugging: bazel build --output_groups=netlist,pnr
        OutputGroupInfo(netlist = depset([netlist]), pnr = depset([pnr_out])),
    ]

synthesizable_bitstream = rule(
    implementation = _synthesizable_bitstream_impl,
    cfg = _board_transition,
    doc = "Builds an FPGA bitstream from a verilog_top for the given board platform.",
    attrs = {
        "top": attr.label(
            mandatory = True,
            providers = [VerilogTopInfo],
            doc = "The verilog_top to synthesize.",
        ),
        "platform": attr.label(
            mandatory = True,
            doc = "Board platform to build for (e.g. //fpga/platforms:tangnano9k). " +
                  "Selects the toolchain family and device via a transition.",
        ),
        "constraints": attr.label(
            mandatory = True,
            allow_single_file = [".pcf", ".cst"],
            doc = "Pin-constraint file: .pcf for ice40, .cst for gowin.",
        ),
        "_board": attr.label(
            default = "//fpga/boards:current",
            providers = [FpgaBoardInfo],
            doc = "Resolved (post-transition) FpgaBoardInfo for the target board.",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    toolchains = [_TOOLCHAIN_TYPE],
)
