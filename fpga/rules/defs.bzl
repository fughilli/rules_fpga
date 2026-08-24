"""Public API for rules_fpga. Load rules from here:

    load("@rules_fpga//fpga/rules:defs.bzl",
         "verilog_library", "verilog_top", "verilog_test",
         "synthesizable_bitstream", "fpga_flash", "fpga_board", "fpga_board_info")
"""

load(":bitstream.bzl", _synthesizable_bitstream = "synthesizable_bitstream")
load(":board.bzl", _fpga_board = "fpga_board", _fpga_board_info = "fpga_board_info")
load(":flash.bzl", _fpga_flash = "fpga_flash")
load(
    ":providers.bzl",
    _FpgaBitstreamInfo = "FpgaBitstreamInfo",
    _FpgaBoardInfo = "FpgaBoardInfo",
    _FpgaToolchainInfo = "FpgaToolchainInfo",
    _VerilogInfo = "VerilogInfo",
    _VerilogTopInfo = "VerilogTopInfo",
    _VerilogTraceInfo = "VerilogTraceInfo",
)
load(
    ":sim.bzl",
    _surfer = "surfer",
    _verilog_sim = "verilog_sim",
    _verilog_test = "verilog_test",
    _verilog_trace = "verilog_trace",
    _wavepeek = "wavepeek",
)
load(":verilog.bzl", _verilog_library = "verilog_library", _verilog_top = "verilog_top")

verilog_library = _verilog_library
verilog_top = _verilog_top
verilog_test = _verilog_test
verilog_trace = _verilog_trace
verilog_sim = _verilog_sim
surfer = _surfer
wavepeek = _wavepeek
synthesizable_bitstream = _synthesizable_bitstream
fpga_flash = _fpga_flash
fpga_board = _fpga_board
fpga_board_info = _fpga_board_info

# Providers, for anyone writing rules on top of this ruleset.
VerilogInfo = _VerilogInfo
VerilogTopInfo = _VerilogTopInfo
VerilogTraceInfo = _VerilogTraceInfo
FpgaBoardInfo = _FpgaBoardInfo
FpgaToolchainInfo = _FpgaToolchainInfo
FpgaBitstreamInfo = _FpgaBitstreamInfo
