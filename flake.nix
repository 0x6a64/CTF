{
  description = "NixCTF — NixOS-based CTF challenge framework";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, microvm }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # The NixCTF library, parameterised by nixpkgs so callers can override it.
      nixctfLib = import ./lib { lib = nixpkgs.lib; };
    in
    {
      # -----------------------------------------------------------------------
      # Library — the primary public API
      # -----------------------------------------------------------------------
      # mkChallengeVM { nixpkgs, microvm, challenge, participant, secret } -> nixosConfiguration
      # mkFlag        { secret, participantId, challengeName }             -> string
      lib = nixctfLib;

      # -----------------------------------------------------------------------
      # Reusable NixOS modules
      # -----------------------------------------------------------------------
      nixosModules = {
        challengeBase = import ./modules/challenge-base.nix;
        sshGateway    = import ./modules/ssh-gateway.nix;
      };

      # -----------------------------------------------------------------------
      # Example NixOS configurations (one VM per challenge × participant)
      # -----------------------------------------------------------------------
      nixosConfigurations = {
        example-suid-player1 = nixctfLib.mkChallengeVM {
          inherit nixpkgs microvm;
          challenge   = ./challenges/suid-privesc.nix;
          participant = { id = "player1"; port = 2201; };
          secret      = "demo-secret-change-in-production";
        };

        example-web-player1 = nixctfLib.mkChallengeVM {
          inherit nixpkgs microvm;
          challenge   = ./challenges/web-sqli.nix;
          participant = { id = "player1"; port = 2202; };
          secret      = "demo-secret-change-in-production";
        };

        example-pwn-player1 = nixctfLib.mkChallengeVM {
          inherit nixpkgs microvm;
          challenge   = ./challenges/pwn-bof.nix;
          participant = { id = "player1"; port = 2203; };
          secret      = "demo-secret-change-in-production";
        };
      };

      # -----------------------------------------------------------------------
      # Packages
      # -----------------------------------------------------------------------
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          vulnBinaries = import ./pkgs/vuln-binaries { inherit pkgs; };
        in
        {
          orchestrator = pkgs.callPackage ./orchestrator { };
          default      = self.packages.${system}.orchestrator;
        } // vulnBinaries
      );

      # -----------------------------------------------------------------------
      # Developer shell
      # -----------------------------------------------------------------------
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nix
              nixos-rebuild
              bash
              jq
            ];
            shellHook = ''
              echo "NixCTF dev shell — run 'nix build .#orchestrator' to build the orchestrator"
            '';
          };
        }
      );
    };
}
