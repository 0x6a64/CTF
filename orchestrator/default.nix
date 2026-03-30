# orchestrator/default.nix
#
# Nix package for the NixCTF orchestrator.
# Build with: nix build .#orchestrator
{ pkgs, lib ? pkgs.lib }:

pkgs.writeShellApplication {
  name = "nixctf-orchestrate";

  # Runtime dependencies available on PATH inside the script.
  runtimeInputs = with pkgs; [
    bash
    coreutils
    jq
    nix
    iproute2   # for 'ss' in nixctf-list-vms
  ];

  text = builtins.readFile ./orchestrate.sh;

  meta = with lib; {
    description = "Lifecycle orchestrator for NixCTF challenge VMs";
    license     = licenses.gpl2Only;
    platforms   = platforms.linux;
    mainProgram = "nixctf-orchestrate";
  };
}
