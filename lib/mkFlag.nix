# lib/mkFlag.nix
#
# Deterministic, participant-unique flag derivation.
#
# The flag is the first 32 hex characters of SHA-256( secret:participantId:challengeName ).
# This means:
#   • Every participant gets a different flag for the same challenge.
#   • The same inputs always produce the same flag (reproducible).
#   • Flags can be verified server-side without storing them anywhere.
{ lib }:

{ secret, participantId, challengeName }:
let
  # Combine all inputs into a single string that feeds the hash.
  input = "${secret}:${participantId}:${challengeName}";
  # builtins.hashString is a pure Nix builtin — no IFD, no derivation.
  hash  = builtins.hashString "sha256" input;
in
  "CTF{${builtins.substring 0 32 hash}}"
