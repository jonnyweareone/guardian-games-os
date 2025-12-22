# Guardian Games OS

Custom gaming OS for families, built on Bazzite with parental controls and profile sync.

## Quick Start

```bash
# Rebase from any Fedora Atomic / Bazzite system
sudo bootc switch ghcr.io/jonnyweareone/guardian-games:stable
```

## What's Included

Everything from Bazzite PLUS:
- **Guardian Sync** - Roaming profiles across family devices
- **Guardian Games** - Game launcher with parental controls (forked Heroic)
- **Screen Time** - Daily limits per child profile
- **Game Approval** - Kids request, parents approve
- **Family Portal** - First-boot family enrollment

## Architecture

```
Guardian Games OS (this repo)
├── guardian-syncd (roaming profile daemon)
├── guardian-portal (first-run family enrollment)
├── guardian-games (Heroic fork with parental controls)
└── screen-time-enforcer (systemd service)
───────────────────────────────────────────
Bazzite (Steam, Lutris, Proton-GE, HDR)
───────────────────────────────────────────
Universal Blue (NVIDIA, codecs, Flatpak)
───────────────────────────────────────────
Fedora Atomic (immutable, rpm-ostree)
```

## Repository Structure

```
guardian-games-os/
├── Containerfile                 # Main build - FROM bazzite
├── Justfile                      # Build commands
├── build.sh                      # Package installation script
├── cosign.pub                    # Signing key (public)
├── .github/
│   ├── workflows/
│   │   └── build.yml             # Build & push to GHCR
│   └── pull.yml                  # Keep in sync with upstream Bazzite
├── system_files/
│   ├── etc/
│   │   └── guardian/
│   │       └── default-config.json
│   └── usr/
│       ├── lib/systemd/user/
│       │   ├── guardian-syncd.service
│       │   └── screen-time-enforcer.service
│       └── share/
│           ├── applications/
│           │   └── guardian-games.desktop
│           └── polkit-1/rules.d/
│               └── 50-guardian-parental.rules
└── docs/
    ├── guardian-games-heroic-fork-plan.md
    └── guardian-sync-architecture.md
```

## Variants

| Image | Base | Use Case |
|-------|------|----------|
| `guardian-games:main` | bazzite | Desktop AMD/Intel (KDE) |
| `guardian-games:nvidia` | bazzite-nvidia | Desktop Nvidia (KDE) |
| `guardian-games:gnome` | bazzite-gnome | Desktop GNOME AMD/Intel |
| `guardian-games:gnome-nvidia` | bazzite-gnome-nvidia | Desktop GNOME Nvidia |
| `guardian-games:deck` | bazzite-deck | Steam Deck / HTPC |
| `guardian-games:deck-gnome` | bazzite-deck-gnome | HTPC with GNOME |

## Installation

### From Bazzite (rebase)
```bash
sudo bootc switch ghcr.io/jonnyweareone/guardian-games:main
systemctl reboot
```

### From ISO
Download from releases, burn to USB, boot and install.

## Development

### Prerequisites
- podman or docker
- just (command runner)
- cosign (for signing)

### Build locally
```bash
# Build default variant
just build

# Build specific variant
just build nvidia
just build deck

# Run shell in built image
just shell

# Check upstream Bazzite updates
just check-upstream
```

### CI/CD
- Push to `main` triggers build of all variants
- Daily builds at 15:00 UTC (after Bazzite)
- Images pushed to `ghcr.io/jonnyweareone/guardian-games`
- Images signed with cosign

## Related Projects

- [Guardian Games](https://github.com/guardian-network/guardian-games) - Heroic fork with parental controls
- [Guardian Sync](https://github.com/guardian-network/guardian-sync) - Profile sync daemon
- [Guardian Portal](https://github.com/guardian-network/guardian-portal) - First-boot enrollment wizard
- [Guardian Dashboard](https://github.com/guardian-network/guardian-dashboard) - Parent web/mobile app

## License

Apache-2.0 (same as Bazzite/Universal Blue)
