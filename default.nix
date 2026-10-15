# default.nix — Native Nixpkgs derivation for polytropos
{ pkgs ? import <nixpkgs> {}, compiler ? "ghc96" }:

let
  ghcTcpluginApiSrc = pkgs.fetchzip {
    url = "https://hackage.haskell.org/package/ghc-tcplugin-api-0.20.1.0/ghc-tcplugin-api-0.20.1.0.tar.gz";
    sha256 = "sha256-bCPBZJM0GhebZcish5jTbp7EoLxjS753vvASvpGchx4=";
  };

  hp = pkgs.haskell.packages.${compiler}.override {
    overrides = hfinal: hprev: {
      ghc-tcplugin-api = hprev.callCabal2nix "ghc-tcplugin-api" ghcTcpluginApiSrc {};
      polytropos-core = hprev.callCabal2nix "polytropos-core" ./packages/polytropos-core {
        primitive = hprev.primitive_0_9_0_0 or hprev.primitive;
      };
      polytropos-plugin = (hprev.callCabal2nix "polytropos-plugin" ./packages/polytropos-plugin {
        ghc-tcplugin-api = hfinal.ghc-tcplugin-api;
        polytropos-core = hfinal.polytropos-core;
        primitive = hprev.primitive_0_9_0_0 or hprev.primitive;
      }).overrideAttrs (old: {
        preCheck = ''
          pkgDb=$(echo /build/tmp.*/package.conf.d)
          export POLYTROPOS_TEST_GHC_FLAGS="-package-db=$pkgDb -package-db=$PWD/dist/package.conf.inplace"
        '';
      });
    };
  };
in {
  core = hp.polytropos-core;
  plugin = hp.polytropos-plugin;
}
