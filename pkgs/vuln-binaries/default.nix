# pkgs/vuln-binaries/default.nix
#
# Exports all intentionally-vulnerable binaries as a flat attribute set so
# that `flake.nix` can splice them into `packages.<system>`.
{ pkgs }:
{
  suid-shell = pkgs.callPackage ./suid-shell { };
  bof-server = pkgs.callPackage ./bof-server { };
}
