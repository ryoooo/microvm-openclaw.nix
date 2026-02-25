# microvm-openclaw.nix

Declarative NixOS configuration that isolates an AI agent ([OpenClaw](https://openclaw.dev)) at the kernel level using [microvm.nix](https://github.com/microvm-nix/microvm.nix).

## Architecture

```
┌─ NixOS Host ────────────────────────────────────────┐
│  Unbound (DNS log)  nftables (egress log)  auditd   │
│                                                      │
│  ┌─ OpenClaw VM (4GB) ───────────┐                   │
│  │  Gateway + Discord             │                   │
│  │  openclaw-defender (3 layers)  │                   │
│  │    Layer 1: regex              │   ┌─ gogcli VM ─┐│
│  │    Layer 2: Prompt Guard 2     │──→│  Google API  ││
│  │            + DeBERTa v3        │SSH│  OAuth jail  ││
│  │    Layer 3: Cerebras LLM      │   └──────────────┘│
│  └────────────────────────────────┘                   │
│        virtiofs /run/secrets (buduroiu pattern)       │
└──────────────────────────────────────────────────────┘
```

## Files

| File | Role |
|---|---|
| `flake.nix` | Flake inputs (nixpkgs, home-manager, microvm, nix-openclaw, nix-openclaw-defender, etc.) |
| `configuration.nix` | Host config: microVM networking (bridge + NAT), nftables, Unbound, auditd, secrets services |
| `vms/openclaw.nix` | OpenClaw VM: Gateway, defender plugin, ML servers, Docker, Home Manager |
| `vms/gogcli.nix` | gogcli VM: Google Workspace CLI isolation, SSH `command=` restriction, audit logging |
| `docs/SOUL.md` | Agent character definition |
| `docs/AGENTS.md` | Tool execution policy (read auto-exec / write requires approval) |
| `docs/TOOLS.md` | Available tools |

## Defense in Depth

- **KVM isolation** — microvm.nix (Cloud Hypervisor) provides kernel-level separation, eliminating the shared-kernel risk of Docker containers
- **Network observability** — Unbound DNS query logging + nftables egress logging for all VM traffic
- **Inter-VM restriction** — Only OpenClaw → gogcli SSH is allowed; reverse direction is dropped
- **Secrets management** — virtiofs mounts to `/run/secrets/`; gateway-token is regenerated on every boot
- **Prompt injection defense** — [openclaw-defender](https://github.com/nyosegawa/openclaw-defender) 3-layer pipeline (regex → ML classifiers → LLM judgment)
- **OAuth isolation** — Google OAuth tokens are confined to the gogcli VM; SSH `command=` restricts allowed subcommands
- **Auditing** — auditd monitors all access to secrets directories

## Flake Dependencies

- [microvm.nix](https://github.com/microvm-nix/microvm.nix) — Cloud Hypervisor-based NixOS microVMs
- [nix-openclaw](https://github.com/openclaw/nix-openclaw) — OpenClaw Home Manager module + overlay
- [nix-openclaw-defender](https://github.com/ryoooo/nix-openclaw-defender) — Nix flake that packages [openclaw-defender](https://github.com/nyosegawa/openclaw-defender) (fork) via `buildNpmPackage` and provides ML server NixOS modules
- [nix-steipete-tools/gogcli](https://github.com/openclaw/nix-steipete-tools) — Google Workspace CLI skill

## Note

This repository is a public reference codebase for a technical article. Desktop environment configuration (Hyprland, WezTerm, etc.) has been omitted. Generate your own `hardware-configuration.nix` with `nixos-generate-config`.
