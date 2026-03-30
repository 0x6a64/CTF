# CTF — NixCTF: NixOS-based CTF Challenge Framework

**NixCTF** turns NixOS modules into fully reproducible, ephemeral Capture-The-Flag
challenge environments powered by [microvm.nix](https://github.com/astro/microvm.nix)
(Firecracker / QEMU).

> _Define your CTF challenge as a NixOS module. Deploy it as a microVM.
> Every participant gets an identical, isolated environment with a unique flag._

---

## Table of Contents

1. [Why NixCTF?](#why-nixctf)
2. [Repository Layout](#repository-layout)
3. [Quick Start](#quick-start)
4. [Core API — `mkChallengeVM`](#core-api--mkchallengevm)
5. [Flag Derivation — `mkFlag`](#flag-derivation--mkflag)
6. [Writing a Challenge Module](#writing-a-challenge-module)
7. [Bundled Challenges](#bundled-challenges)
8. [SSH Gateway](#ssh-gateway)
9. [Orchestrator](#orchestrator)
10. [Secrets Management](#secrets-management)
11. [Contributing](#contributing)

---

## Why NixCTF?

| Feature | Docker/k8s/nsjail | **NixCTF** |
|---|---|---|
| Reproducible environments | Partial (image layers) | ✅ Bit-for-bit via Nix |
| Composable challenges | Ad-hoc Dockerfiles | ✅ NixOS module imports |
| Auditable attack surface | Opaque layers | ✅ It's just NixOS config |
| Local challenge testing | `docker run` | ✅ `nix run` |
| Sub-second VM boot | N/A (containers) | ✅ Firecracker microVMs |
| Unique flags per participant | Manual scripting | ✅ Deterministic derivation |

---

## Repository Layout

```
.
├── flake.nix                     # Main Nix flake (entry point)
├── lib/
│   ├── default.nix               # Public API exports
│   ├── mkChallengeVM.nix         # Core VM builder
│   └── mkFlag.nix                # Deterministic flag derivation
├── modules/
│   ├── challenge-base.nix        # Base NixOS module for all challenge VMs
│   └── ssh-gateway.nix           # Host-side SSH gateway NixOS module
├── challenges/
│   ├── suid-privesc.nix          # SUID privilege escalation challenge
│   ├── web-sqli.nix              # SQL injection web challenge
│   └── pwn-bof.nix               # Buffer overflow pwn challenge
├── pkgs/
│   └── vuln-binaries/
│       ├── suid-shell/           # Intentionally vulnerable SUID C binary
│       └── bof-server/           # Intentionally vulnerable BOF network service
├── orchestrator/
│   ├── default.nix               # Nix package for the orchestrator
│   └── orchestrate.sh            # VM lifecycle management script
└── secrets/                      # Operator secrets (gitignored; see below)
    └── .gitkeep
```

---

## Quick Start

### Prerequisites

* Nix with flakes enabled (`~/.config/nix/nix.conf`: `experimental-features = nix-command flakes`)
* Linux host (x86\_64 or aarch64)
* KVM available (`/dev/kvm` readable)

### Run an example challenge locally

```bash
# Clone the repo
git clone https://github.com/0x6a64/CTF && cd CTF

# Run the SUID privesc challenge VM for player1
nix run .#nixosConfigurations.example-suid-player1.config.microvm.declaredRunner

# In another terminal — connect as the participant
ssh -p 2201 ctf@localhost   # password: ctf
```

The flag is at `/etc/flag` (root-only). Exploit the SUID binary to read it.

### Build the orchestrator

```bash
nix build .#orchestrator
./result/bin/nixctf-orchestrate --help
```

---

## Core API — `mkChallengeVM`

```nix
# In your flake.nix outputs:
nixosConfigurations.player1-suid = nixctf.lib.mkChallengeVM {
  inherit nixpkgs microvm;

  # Path to (or inline) NixOS module describing the challenge.
  challenge = ./challenges/suid-privesc.nix;

  # Participant descriptor.
  participant = {
    id   = "player1";   # unique identifier — used in flag derivation + VM name
    port = 2201;        # host-side TCP port forwarded to VM's SSH (port 22)
  };

  # Operator secret — never stored in the Nix store.
  # Every challenge × participant combination gets a unique, reproducible flag.
  secret = builtins.readFile ./secrets/flag-key;
};
```

`mkChallengeVM` returns a standard `nixpkgs.lib.nixosSystem` value, so it
integrates transparently with `nixosConfigurations` and all standard NixOS
tooling (`nixos-rebuild`, `nix build`, etc.).

### Composing challenges

Because each challenge is a NixOS module, you can compose them:

```nix
# A "hard mode" VM that chains multiple challenges.
challenge = { imports = [
  ./challenges/suid-privesc.nix
  ./challenges/web-sqli.nix
]; };
```

---

## Flag Derivation — `mkFlag`

```nix
nixctf.lib.mkFlag {
  secret        = "my-operator-secret";
  participantId = "player1";
  challengeName = "suid-privesc";   # must match meta.challengeName in the module
}
# => "CTF{3a7f9c2b1e4d8a6f0b5c9d2e7f3a1b4c}"
```

The flag is the first 32 hex characters of
`SHA-256("${secret}:${participantId}:${challengeName}")`.

Properties:
* **Unique per participant** — different IDs produce different flags.
* **Reproducible** — same inputs always produce the same flag.
* **Verifiable** — the flag submission backend can recompute it without a DB.
* **No storage required** — flags are never written to disk by the framework.

---

## Writing a Challenge Module

A challenge module is a standard NixOS module with one required attribute:

```nix
# challenges/my-challenge.nix
{ config, pkgs, lib, ... }:
{
  # REQUIRED — used by mkChallengeVM to derive the participant's unique flag.
  meta.challengeName = "my-challenge";

  # Everything else is normal NixOS config.
  # The flag is injected at /etc/flag (root:root, mode 0400) by mkChallengeVM.
  # Your challenge should restrict or hide it appropriately.

  environment.systemPackages = [ pkgs.myVulnerableApp ];

  systemd.services.my-service = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.ExecStart = "${pkgs.myVulnerableApp}/bin/my-service";
  };

  environment.etc."motd".text = ''
    Welcome to my-challenge! The flag is at /etc/flag.
  '';
}
```

The `challenge-base` module (imported automatically) provides:
* A minimal NixOS system (no GUI, no docs)
* OpenSSH with password authentication enabled
* A `ctf` user (password: `ctf`)
* Common CTF tools: `gdb`, `strace`, `ltrace`, `netcat`, `curl`, `vim`

---

## Bundled Challenges

| File | Category | Difficulty | Description |
|------|----------|------------|-------------|
| `challenges/suid-privesc.nix` | Privilege Escalation | Beginner | SUID binary calls `setuid(0)` then `execl("/bin/sh")` — escalate to root to read `/etc/flag` |
| `challenges/web-sqli.nix` | Web | Beginner | Flask login form with unsanitised SQL — bypass auth via injection |
| `challenges/pwn-bof.nix` | Pwn | Intermediate | Stack buffer overflow with `gets()`; overwrite return address to call `win()` |

---

## SSH Gateway

Add the `sshGateway` module to your **host** NixOS configuration to
automatically route each participant's port to their VM:

```nix
# host/configuration.nix
{ inputs, ... }:
{
  imports = [ inputs.nixctf.nixosModules.sshGateway ];

  nixctf.sshGateway = {
    enable = true;
    participants = [
      { id = "player1"; port = 2201; }
      { id = "player2"; port = 2202; }
    ];
  };
}
```

Participants connect with:

```bash
ssh -p 2201 ctf@<host-ip>   # player1's VM
ssh -p 2202 ctf@<host-ip>   # player2's VM
```

---

## Orchestrator

The orchestrator manages VM lifecycles from the command line:

```bash
# Start a VM
nixctf-orchestrate launch /etc/nixctf player1

# Show running VMs
nixctf-orchestrate status

# Reset a VM (destroy + relaunch — ephemeral overlay discarded)
nixctf-orchestrate reset /etc/nixctf player1

# Destroy a VM
nixctf-orchestrate destroy player1

# Destroy inactive VMs (for use in a cron job / systemd timer)
NIXCTF_INACTIVITY_TIMEOUT=1800 nixctf-orchestrate watchdog
```

State is stored in `$NIXCTF_STATE_DIR` (default: `/var/lib/nixctf`).

### systemd integration (example)

```nix
systemd.services."nixctf-vm@" = {
  description    = "NixCTF VM for %i";
  after          = [ "network.target" ];
  serviceConfig  = {
    ExecStart  = "${pkgs.nixctf-orchestrator}/bin/nixctf-orchestrate launch /etc/nixctf %i";
    ExecStop   = "${pkgs.nixctf-orchestrator}/bin/nixctf-orchestrate destroy %i";
    RemainAfterExit = true;
  };
};
```

---

## Secrets Management

1. Generate a strong random secret:
   ```bash
   head -c 32 /dev/urandom | base64 > secrets/flag-key
   ```
2. Reference it in `flake.nix`:
   ```nix
   secret = builtins.readFile ./secrets/flag-key;
   ```
3. The `secrets/` directory is listed in `.gitignore` — **never commit it**.
4. For production deployments use [sops-nix](https://github.com/Mic92/sops-nix)
   or [agenix](https://github.com/ryantm/agenix) to manage secrets declaratively.

---

## Contributing

Contributions of new challenge modules are especially welcome!  Each challenge
should live in `challenges/` as a self-contained NixOS module with:

* `meta.challengeName` set to a kebab-case identifier
* A descriptive comment block at the top (category, difficulty, scenario, goal)
* An `/etc/motd` hint for participants
* Any required packages built from source in `pkgs/`

Please ensure challenges are **intentionally** insecure only within the NixOS
module boundary, and document the intended exploitation path in comments.

