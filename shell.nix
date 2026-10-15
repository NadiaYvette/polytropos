# shell.nix — Development shell for polytropos
{ pkgs ? import <nixpkgs> {}, compiler ? "ghc96" }:

let
  cLibraries = with pkgs; [
    zlib
    gmp
    ncurses
    libffi
  ];
in pkgs.mkShell {
  name = "polytropos-dev-shell";

  buildInputs = [
    pkgs.haskell.compiler.${compiler}
    pkgs.cabal-install
    pkgs.pkg-config
  ] ++ cLibraries;

  shellHook = ''
    export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath cLibraries}:$LD_LIBRARY_PATH"
  '';
}
