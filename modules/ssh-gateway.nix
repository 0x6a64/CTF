# modules/ssh-gateway.nix
#
# Host-side SSH gateway NixOS module.
#
# Add this module to your *host* NixOS configuration to create an SSH
# ProxyJump / port-forward gateway that routes incoming connections to the
# correct participant VM.
#
# Example (host flake):
#
#   nixosConfigurations.ctf-host = nixpkgs.lib.nixosSystem {
#     modules = [
#       nixctf.nixosModules.sshGateway
#       {
#         nixctf.sshGateway.participants = [
#           { id = "player1"; port = 2201; }
#           { id = "player2"; port = 2202; }
#         ];
#       }
#     ];
#   };
#
# Participants then connect with:
#   ssh -p 2201 ctf@<host-ip>
{ config, pkgs, lib, ... }:

let
  cfg = config.nixctf.sshGateway;
in
{
  options.nixctf.sshGateway = {
    enable = lib.mkEnableOption "NixCTF SSH gateway";

    listenAddress = lib.mkOption {
      type    = lib.types.str;
      default = "0.0.0.0";
      description = "Address on which to listen for incoming SSH connections.";
    };

    participants = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          id = lib.mkOption {
            type        = lib.types.str;
            description = "Unique participant identifier.";
          };
          port = lib.mkOption {
            type        = lib.types.port;
            description = "Host-side TCP port that forwards into the participant's VM (port 22).";
          };
        };
      });
      default     = [];
      description = "List of participants whose VMs are reachable via this gateway.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Open every participant port in the firewall.
    networking.firewall.allowedTCPPorts =
      map (p: p.port) cfg.participants;

    # One sshd instance per participant port, each forwarding to localhost:<port>
    # inside the VM (microvm forwardPorts maps host:<port> -> guest:22).
    services.openssh = {
      enable = true;
      # The gateway sshd listens on all participant ports.
      listenAddresses = map
        (p: { addr = cfg.listenAddress; port = p.port; })
        cfg.participants;
      settings = {
        # Gateway does not allow direct logins — it only proxies.
        PermitRootLogin = "no";
        PasswordAuthentication = "no";
      };
    };

    # Install a helper script that operators can use to list active VMs.
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "nixctf-list-vms" ''
        echo "Active NixCTF VMs:"
        for port in ${lib.concatMapStringsSep " " (p: toString p.port) cfg.participants}; do
          pid=$(ss -tlnp | awk -v port=":$port " '$4 ~ port {print}' | grep -oP 'pid=\K[0-9]+' | head -1)
          if [ -n "$pid" ]; then
            echo "  port $port → PID $pid (running)"
          else
            echo "  port $port → (no process)"
          fi
        done
      '')
    ];
  };
}
