# Evaluated by rules_nixpkgs (nix_pkg.file) against the pinned @nixpkgs.
#
# A single bin/ tree with the host gcc/g++ (wrapped: it knows its own sysroot +
# include paths) plus binutils (ar/ld/nm/strip/objcopy), so a hand-written Bazel
# cc_toolchain can point at one directory. Used to compile the Verilator-
# generated C++ with Bazel's cc actions instead of Verilator's `make`.
let
  pkgs = import <nixpkgs> {
    config = { };
    overlays = [ ];
  };
in
{
  cc-toolchain = pkgs.buildEnv {
    name = "cc-toolchain-env";
    paths = [
      pkgs.gcc
      pkgs.binutils
    ];
    ignoreCollisions = true;
  };
}
