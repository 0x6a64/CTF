# challenges/pwn-bof.nix
#
# Challenge: Buffer Overflow (Stack-Based)
# Category:  Pwn
# Difficulty: Intermediate
#
# Scenario:
#   A network service reads input into a fixed-size stack buffer without
#   bounds checking.  The classic stack-based buffer overflow lets you
#   redirect execution to a win() function that prints /etc/flag.
#
# Goal:
#   Exploit the buffer overflow in the running service to call win() and
#   capture the flag.
#
# Local test:
#   nix run .#nixosConfigurations.example-pwn-player1.config.microvm.declaredRunner
#   nc localhost 1337
{ config, pkgs, lib, ... }:

let
  bofServer = pkgs.callPackage ../pkgs/vuln-binaries/bof-server { };
in
{
  # ---------------------------------------------------------------------------
  # Challenge metadata
  # ---------------------------------------------------------------------------
  nixctf.challengeName = "pwn-bof";

  # ---------------------------------------------------------------------------
  # Vulnerable network service
  # ---------------------------------------------------------------------------
  environment.systemPackages = [ bofServer ];

  systemd.services.ctf-pwn = {
    description   = "NixCTF Buffer Overflow Challenge";
    wantedBy      = [ "multi-user.target" ];
    after         = [ "network.target" ];
    serviceConfig = {
      # socat wraps the binary so it can be reached over TCP.
      ExecStart = ''
        ${pkgs.socat}/bin/socat \
          TCP-LISTEN:1337,reuseaddr,fork \
          EXEC:${bofServer}/bin/bof-server
      '';
      Restart = "on-failure";
      User    = "ctf-pwn";
      Group   = "ctf-pwn";
    };
  };

  users.users.ctf-pwn = {
    isSystemUser = true;
    group        = "ctf-pwn";
  };
  users.groups.ctf-pwn = {};

  # The win() function inside bof-server reads /etc/flag.
  # The service runs as ctf-pwn; add it to a flag-readers group.
  system.activationScripts.flag-permissions = lib.stringAfter [ "etc" ] ''
    if [ -f /etc/flag ]; then
      chown root:ctf-pwn /etc/flag
      chmod 0440 /etc/flag
    fi
  '';

  networking.firewall.allowedTCPPorts = [ 1337 ];

  environment.etc."motd".text = ''
    ╔══════════════════════════════════════════════╗
    ║  NixCTF — Buffer Overflow                    ║
    ║                                              ║
    ║  A service listens on port 1337.             ║
    ║  Overflow the buffer and call win()!         ║
    ║                                              ║
    ║  nc localhost 1337                           ║
    ╚══════════════════════════════════════════════╝
  '';
}
