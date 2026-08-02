# Entry point for non-flake users: `nix-build -A mzmine`
{
  pkgs ? import <nixpkgs> { config.allowUnfree = true; },
}:
{
  mzmine = pkgs.callPackage ./pkgs/mzmine/package.nix { };
}
