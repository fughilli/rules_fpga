# Evaluated by rules_nixpkgs (nix_pkg.file) against the pinned @nixpkgs.
#
# wavepeek (github.com/kleverhq/wavepeek) is a stateless CLI for querying VCD/FST
# waveforms -- built for LLM/agent-driven debugging. It isn't in nixpkgs, so we
# fetch the upstream prebuilt release binary for the host system and (on Linux)
# autoPatchelf it against glibc/zlib. Hashes are per-platform so a fresh
# `bazel build` works on any supported host without a network-nondeterministic
# cargo build.
let
  pkgs = import <nixpkgs> {
    config = { };
    overlays = [ ];
  };
  inherit (pkgs) lib stdenv;
  version = "3.0.0";
  base = "https://github.com/kleverhq/wavepeek/releases/download/v${version}";
  sources = {
    "aarch64-linux" = {
      triple = "aarch64-unknown-linux-gnu";
      sha256 = "02yhl13qlff81y0w9ilracijvjzq1wc49nzrxa84icw2cdgyml4a";
    };
    "x86_64-linux" = {
      triple = "x86_64-unknown-linux-gnu";
      sha256 = "16chymwqghdr4h5xs11dndimhli6nwgw1qcblql0cr8sbk1bwhx6";
    };
    "aarch64-darwin" = {
      triple = "aarch64-apple-darwin";
      sha256 = "1yhqv60ghw7fbc0j6ns9b9wv7d5wcfh13ghwpjsg1gnij9hd4b49";
    };
    "x86_64-darwin" = {
      triple = "x86_64-apple-darwin";
      sha256 = "1iblgyin5m4xw4ljrb8igp87f53vya9g7b6xlrkg3kr2qglpgnhn";
    };
  };
  sys = stdenv.hostPlatform.system;
  source = sources.${sys} or (throw "wavepeek: unsupported system ${sys}");
in
{
  wavepeek = stdenv.mkDerivation {
    pname = "wavepeek";
    inherit version;
    src = pkgs.fetchurl {
      url = "${base}/wavepeek-${source.triple}.tar.gz";
      sha256 = source.sha256;
    };
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    nativeBuildInputs = lib.optionals stdenv.isLinux [ pkgs.autoPatchelfHook ];
    buildInputs = lib.optionals stdenv.isLinux [
      stdenv.cc.cc.lib
      pkgs.zlib
    ];
    installPhase = ''
      runHook preInstall
      bin=$(find . -type f -name wavepeek | head -1)
      install -Dm755 "$bin" "$out/bin/wavepeek"
      runHook postInstall
    '';
    meta.mainProgram = "wavepeek";
  };
}
