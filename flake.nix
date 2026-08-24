{
  description = "rules_fpga: open FPGA toolchains (iCE40 + Gowin) for Bazel";

  # Kept in lock-step with the nixpkgs pin in MODULE.bazel. rules_nixpkgs pins
  # the same commit independently; this input is for the human devShell only.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/b6018f87da91d19d0ab4cf979885689b469cdd41";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in {
      # NOTE: this devShell is a human convenience for poking at the tools by
      # hand (running iceprog/openFPGALoader, inspecting a bitstream). It is NOT
      # required by any Bazel build or test -- Bazel pulls every tool through
      # rules_nixpkgs (MODULE.bazel), so a fresh `bazel build //...` works with
      # no `nix develop` and nothing on PATH.
      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          name = "rules_fpga";
          packages = with pkgs; [
            yosys
            nextpnr
            icestorm
            apicula
            openfpgaloader
            verilator
            bazelisk
          ];
        };
      });
    };
}
