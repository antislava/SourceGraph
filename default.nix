{ pkgs ? import <nixpkgs> {} # nixpkgs-channels bf3360cdcfee144ce349457b248de3b93aee3c3d
# { pkgs ? import ./nix/nixpkgs.nix
# { pkgs ? import (import ./nix/nixpkgs-src) {}
, compiler ? "default"
, root ? ./.
, name ? "SourceGraph"
, source-overrides ? {}
, ...
}:
let
  haskellPackages =
    if compiler == "default"
      then pkgs.haskellPackages
      else pkgs.haskell.packages.${compiler};
in
haskellPackages.developPackage {
  root = root;
  name = name;
  source-overrides = {
    Graphalyze = ../hpacheco_Graphalyze;
    SourceGraph = ./.;
  } // source-overrides;

  # overrides = (import ./nix/haskell-overrides.nix pkgs).ghc;
  overrides = self: super: with pkgs.haskell.lib; {
    # Graphalyze = doJailbreak super.Graphalyze;
  };


  modifier = drv: pkgs.haskell.lib.overrideCabal drv (attrs: {
    buildTools = with haskellPackages; (attrs.buildTools or []) ++ [cabal-install ghcid] ;
    # shellHook = '' '';
  });
}

