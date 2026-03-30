# lib/mkChallengeVM.nix
#
# Core NixCTF abstraction — turns a challenge NixOS module + participant
# descriptor into a fully configured NixOS system that runs as a microvm.
#
# Returned value: the result of nixpkgs.lib.nixosSystem { … }, i.e. the same
# type as a nixosConfigurations entry in a flake.  Callers can therefore use
# it directly:
#
#   nixosConfigurations.player1-suid = lib.mkChallengeVM { … };
#
# or build it:
#
#   nix build .#nixosConfigurations.player1-suid.config.microvm.declaredRunner
{ lib }:

{ nixpkgs
, microvm
, challenge
  # { id : string; port : int }
, participant
, secret
  # Optional: override the NixOS system architecture (default: x86_64-linux)
, system ? "x86_64-linux"
}:

let
  mkFlag = import ./mkFlag.nix { inherit lib; };

  # Extract the challenge name from the `nixctf.challengeName` option declared
  # in challenge-base.nix and set by each challenge module.
  # We evaluate a lightweight nixosSystem only to read this single attribute;
  # Nix's lazy evaluation means the heavy service/package options are not
  # forced unless actually accessed.
  #
  # `_module.check = false` suppresses NixOS module-type checking for this
  # meta evaluation so that partially-configured modules (e.g. ones that set
  # services.* but have no fileSystems or boot config) don't throw errors when
  # we only need to read `config.nixctf.challengeName`.
  metaSystem = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      ../modules/challenge-base.nix
      challenge
      { _module.check = false; }
    ];
  };

  challengeName = metaSystem.config.nixctf.challengeName;

  flag = mkFlag {
    inherit secret;
    participantId = participant.id;
    inherit challengeName;
  };
in
nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    # Wire in the microvm NixOS module so the config is bootable.
    microvm.nixosModules.microvm

    # Base configuration shared by every challenge VM.
    ../modules/challenge-base.nix

    # The actual challenge — intentionally vulnerable NixOS config.
    challenge

    # Per-participant overlay: inject flag, set hostname and SSH port.
    ({ pkgs, ... }: {
      networking.hostName = "ctf-${challengeName}-${participant.id}";

      # Inject the derived flag as a root-readable file inside the VM.
      # Challenge modules should restrict its permissions as needed.
      environment.etc."flag" = {
        text  = flag + "\n";
        mode  = "0400";
        user  = "root";
        group = "root";
      };

      # Expose the flag path as an environment variable for challenge scripts.
      environment.variables.FLAG_PATH = "/etc/flag";

      # microvm networking: forward the host SSH port into the VM.
      microvm = {
        hypervisor = "qemu";

        interfaces = [
          {
            type = "user";
            id   = "vm-${participant.id}";
            # Deterministically generate a locally-administered MAC from the
            # participant ID so multiple VMs never collide on the same host.
            mac  =
              let h = builtins.hashString "sha256" participant.id;
              in "02:${builtins.substring 0 2 h}:${builtins.substring 2 2 h}"
               + ":${builtins.substring 4 2 h}:${builtins.substring 6 2 h}"
               + ":${builtins.substring 8 2 h}";
          }
        ];

        # Expose SSH to the host on the participant's assigned port.
        forwardPorts = [
          {
            from  = "host";
            host.port  = participant.port;
            guest.port = 22;
          }
        ];

        # Read-only share of the Nix store from the host (avoids copying).
        shares = [
          {
            source  = "/nix/store";
            mountPoint = "/nix/.ro-store";
            tag     = "ro-store";
            proto   = "virtiofs";
          }
        ];

        # Ephemeral overlay so every VM boot starts from a clean slate.
        writableStoreOverlay = "/nix/.rw-store";
      };
    })
  ];
}
