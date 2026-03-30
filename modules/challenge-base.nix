# modules/challenge-base.nix
#
# Base NixOS module imported by every challenge VM.
# Provides a minimal, hardened-enough system with SSH access for participants.
{ config, pkgs, lib, ... }:
{
  # -------------------------------------------------------------------------
  # NixCTF challenge metadata option
  # -------------------------------------------------------------------------
  options.nixctf = {
    challengeName = lib.mkOption {
      type        = lib.types.str;
      description = ''
        Unique kebab-case identifier for this challenge.
        Used by mkChallengeVM to derive the participant-unique flag and to
        name the VM.  Every challenge module MUST set this option.
      '';
      example = "suid-privesc";
    };
  };

  # -------------------------------------------------------------------------
  # System configuration
  # -------------------------------------------------------------------------
  config = {
    # System basics
    system.stateVersion = "24.05";

    # Minimal boot — microvm handles the actual boot loader.
    boot.loader.grub.enable = false;

    # Networking
    networking = {
      # hostName is overridden per-VM by mkChallengeVM.
      hostName = lib.mkDefault "ctf-challenge";
      firewall = {
        enable          = true;
        allowedTCPPorts = [ 22 ];
      };
    };

    # SSH daemon
    services.openssh = {
      enable = true;
      settings = {
        # Allow root login so participants can reach root after privilege
        # escalation challenges without needing a password manager.
        PermitRootLogin        = lib.mkDefault "yes";
        PasswordAuthentication = lib.mkDefault "yes";
        # Reduce noise from host-key checks in ephemeral VMs.
        StrictModes            = false;
      };
      # Generate host keys on first boot (ephemeral; lost on VM reset, which is
      # fine since the VM is treated as disposable).
      hostKeys = [
        { type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }
      ];
    };

    # Users
    users.mutablePasswords = false;

    # Unprivileged participant account.
    users.users.ctf = {
      isNormalUser = true;
      password     = "ctf";   # intentionally weak; this is a CTF
      home         = "/home/ctf";
      shell        = pkgs.bash;
      extraGroups  = [];
      description  = "CTF participant account";
    };

    # Root password (challenges that need root access use privilege escalation).
    users.users.root.password = lib.mkDefault "root";

    # Basic environment
    environment.systemPackages = with pkgs; [
      bash
      coreutils
      findutils
      file
      gdb
      ltrace
      strace
      netcat-gnu
      curl
      less
      vim
    ];

    # Disable unnecessary services to keep the attack surface minimal and the
    # VM boot fast.
    services.udisks2.enable               = lib.mkDefault false;
    documentation.enable                  = lib.mkDefault false;
    documentation.man.enable              = lib.mkDefault false;
    programs.command-not-found.enable     = lib.mkDefault false;
  };
}

