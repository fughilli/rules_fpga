# Evaluated by rules_nixpkgs (nix_pkg.file) against the pinned @nixpkgs.
#
# Verilator's `--binary` mode shells out to make + a C++ compiler. We bundle
# verilator with gcc, gnumake and perl into a single buildEnv so a test action
# only has to put one bin/ directory on PATH to get the whole flow.
let
  pkgs = import <nixpkgs> { };
in
{
  verilator-env = pkgs.buildEnv {
    name = "verilator-env";
    paths = with pkgs; [
      verilator
      gcc
      gnumake
      perl
    ];
  };
}
