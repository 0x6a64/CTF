# NixCTF library — public API
#
# Usage (inside a flake):
#
#   inputs.nixctf.url = "github:<your-org>/<your-nixctf-fork>";
#
#   outputs = { self, nixpkgs, microvm, nixctf }:
#     let lib = nixctf.lib;
#     in {
#       nixosConfigurations.my-vm = lib.mkChallengeVM {
#         inherit nixpkgs microvm;
#         challenge   = ./challenges/my-challenge.nix;
#         participant = { id = "player1"; port = 2201; };
#         secret      = builtins.readFile ./secrets/flag-key;
#       };
#     };
{ lib }:
{
  # mkChallengeVM
  #   Builds a NixOS system configuration (suitable for microvm/qemu) from a
  #   challenge module and participant descriptor.
  #
  # Arguments
  #   nixpkgs     — the nixpkgs flake input
  #   microvm     — the microvm.nix flake input
  #   challenge   — path to (or inline) NixOS module describing the challenge
  #   participant — { id : string; port : int }
  #                 id   is used for flag derivation and VM naming
  #                 port is the host-side SSH port forwarded into the VM
  #   secret      — an operator-controlled secret string used to derive flags
  #                 (never stored in the Nix store directly; only its hash is)
  mkChallengeVM = import ./mkChallengeVM.nix { inherit lib; };

  # mkFlag
  #   Deterministically derives a participant-unique flag from:
  #     secret + participantId + challengeName
  #   The result is always of the form CTF{<32 hex chars>}.
  #
  # Arguments
  #   secret        — operator secret (string)
  #   participantId — unique player identifier (string)
  #   challengeName — challenge identifier (string)
  mkFlag = import ./mkFlag.nix { inherit lib; };
}
