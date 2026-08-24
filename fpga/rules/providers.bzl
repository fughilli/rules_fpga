"""Providers shared across the FPGA rules."""

VerilogInfo = provider(
    doc = "Transitive Verilog/SystemVerilog sources and include context.",
    fields = {
        "transitive_srcs": "depset[File] of .v/.sv/.vh sources in the closure.",
        "transitive_includes": "depset[str] of include directories (yosys -I / verilator +incdir).",
        "defines": "depset[str] of `NAME` or `NAME=value` preprocessor defines.",
    },
)

VerilogTopInfo = provider(
    doc = "A designated top-level module together with its Verilog closure.",
    fields = {
        "top_module": "str, name of the top-level module.",
        "verilog": "VerilogInfo for the closure rooted at this top.",
    },
)

FpgaBoardInfo = provider(
    doc = "Target-part parameters for place-and-route, packing and flashing. " +
          "Pin constraints are NOT here -- they live on synthesizable_bitstream, " +
          "since they depend on the design's port names as well as the board.",
    fields = {
        "family": "str, tool family: 'ice40' or 'gowin'.",
        "part": "str, device passed to nextpnr ('up5k', or 'GW1NR-LV9QN88PC6/I5').",
        "package": "str, chip package for nextpnr-ice40 (e.g. 'sg48'); '' if unused.",
        "packer_device": "str, device for gowin_pack -d (e.g. 'GW1N-9C'); '' if unused.",
        "freq_mhz": "str, target clock in MHz for the P&R timing estimate; '' to skip.",
        "flash_args": "list[str], extra flash-tool args (e.g. ['-b', 'tangnano9k']).",
    },
)

FpgaToolchainInfo = provider(
    doc = "Resolved open-source FPGA toolchain: binaries + invocation metadata.",
    fields = {
        "yosys": "File, the yosys executable.",
        "yosys_files": "depset[File], full yosys package tree (data + libs).",
        "synth_command": "str, yosys synth pass ('synth_ice40' or 'synth_gowin').",
        "nextpnr": "File, the nextpnr executable for this family.",
        "nextpnr_files": "depset[File], full nextpnr package tree.",
        "packer": "File, the bitstream packer (icepack or gowin_pack).",
        "packer_files": "depset[File], full packer package tree.",
        "flash_tool": "File, the flashing tool (iceprog or openFPGALoader).",
        "flash_files": "depset[File], full flash-tool package tree.",
    },
)

FpgaBitstreamInfo = provider(
    doc = "A built bitstream plus everything fpga_flash needs to program it. " +
          "Carries the flash tool captured under the board's configuration so " +
          "fpga_flash needs neither a platform transition nor toolchain resolution.",
    fields = {
        "bitstream": "File, the .bin (ice40) or .fs (gowin) bitstream.",
        "board": "FpgaBoardInfo for the target board.",
        "flash_tool": "File, the flashing tool.",
        "flash_files": "depset[File], full flash-tool package tree.",
    },
)
