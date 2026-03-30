# challenges/suid-privesc.nix
#
# Challenge: SUID Privilege Escalation
# Category:  Privilege Escalation
# Difficulty: Beginner
#
# Scenario:
#   A SUID binary owned by root is installed on the system.  The binary is
#   intentionally vulnerable — it calls system(3) with attacker-controlled
#   input, allowing any user to execute code as root and read /etc/flag.
#
# Goal:
#   Obtain a root shell (or directly read /etc/flag) to capture the flag.
#
# Local test:
#   nix run .#nixosConfigurations.example-suid-player1.config.microvm.declaredRunner
#   ssh -p 2201 ctf@localhost   # password: ctf
{ config, pkgs, lib, ... }:

let
  # Build the intentionally-vulnerable SUID binary from source.
  suidShell = pkgs.callPackage ../pkgs/vuln-binaries/suid-shell { };
in
{
  # ---------------------------------------------------------------------------
  # Challenge metadata (consumed by mkChallengeVM to derive the flag)
  # ---------------------------------------------------------------------------
  nixctf.challengeName = "suid-privesc";

  # ---------------------------------------------------------------------------
  # Vulnerable configuration
  # ---------------------------------------------------------------------------

  # Install the vulnerable binary.
  environment.systemPackages = [ suidShell ];

  # Register it as a SUID wrapper so the setuid bit survives the Nix store
  # (which is mounted nosetuid by default).
  security.wrappers.suid-shell = {
    source  = "${suidShell}/bin/suid-shell";
    owner   = "root";
    group   = "root";
    setuid  = true;
  };

  # The flag lives at /etc/flag (injected by mkChallengeVM) and is readable
  # only by root.  The activation script below enforces that on every boot.
  system.activationScripts.flag-permissions = lib.stringAfter [ "etc" ] ''
    if [ -f /etc/flag ]; then
      chmod 0400 /etc/flag
      chown root:root /etc/flag
    fi
  '';

  # Add a hint for the participant.
  environment.etc."motd".text = ''
    ╔══════════════════════════════════════════════╗
    ║  NixCTF — SUID Privilege Escalation          ║
    ║                                              ║
    ║  A mysterious binary lives at:               ║
    ║    /run/wrappers/bin/suid-shell              ║
    ║                                              ║
    ║  The flag is at /etc/flag (root-only).       ║
    ║  Good luck!                                  ║
    ╚══════════════════════════════════════════════╝
  '';
}
