{
  description = "polytropos — row-polymorphic / open ADT engine for Haskell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };

        ghcTcpluginApiSrc = pkgs.fetchzip {
          url = "https://hackage.haskell.org/package/ghc-tcplugin-api-0.20.1.0/ghc-tcplugin-api-0.20.1.0.tar.gz";
          sha256 = "sha256-bCPBZJM0GhebZcish5jTbp7EoLxjS753vvASvpGchx4=";
        };

        mkPolytroposPackages = hp: hp.override {
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

        hp96 = mkPolytroposPackages pkgs.haskell.packages.ghc96;
        hp98 = mkPolytroposPackages pkgs.haskell.packages.ghc98;
        hp910 = mkPolytroposPackages pkgs.haskell.packages.ghc910;

        cLibraries = with pkgs; [
          zlib
          gmp
          ncurses
          libffi
        ];

        mkDevShell = compilerPkg: pkgs.mkShell {
          buildInputs = [
            compilerPkg
            pkgs.cabal-install
            pkgs.pkg-config
          ] ++ cLibraries;

          shellHook = ''
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath cLibraries}:$LD_LIBRARY_PATH"
          '';
        };
      in {
        packages = {
          default = hp96.polytropos-core;

          ghc96-polytropos-core = hp96.polytropos-core;
          ghc96-polytropos-plugin = hp96.polytropos-plugin;

          ghc98-polytropos-core = hp98.polytropos-core;
          ghc98-polytropos-plugin = hp98.polytropos-plugin;

          ghc910-polytropos-core = hp910.polytropos-core;
          ghc910-polytropos-plugin = hp910.polytropos-plugin;
        };

        devShells = {
          default = mkDevShell pkgs.haskell.compiler.ghc910;
          ghc96 = mkDevShell pkgs.haskell.compiler.ghc96;
          ghc98 = mkDevShell pkgs.haskell.compiler.ghc98;
          ghc910 = mkDevShell pkgs.haskell.compiler.ghc910;
        };
      }
    );
}
