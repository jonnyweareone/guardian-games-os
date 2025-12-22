# Guardian Games OS v2

A managed gaming environment for families, built on Fedora Silverblue.

## Philosophy

> "We control the gaming experience, not the kid."

Unlike Bazzite which gives you everything and says "go wild", Guardian Games OS puts the **launcher as gatekeeper**. Even if Steam is installed, kids launch through our UI which:

- Filters library by age rating / parent whitelist
- Enforces time limits mid-session
- Logs playtime per title
- Can pause/kill sessions remotely
- Integrates with Guardian Network parental controls

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    GUARDIAN GAMES OS v2                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  BASE: ghcr.io/ublue-os/silverblue-main:41                      │
│  ├── Clean GNOME + Wayland                                      │
│  ├── Mesa drivers (Intel/AMD)                                   │
│  ├── Malcontent (parental controls)                             │
│  └── Flatpak-first app model                                    │
│                                                                 │
│  GAMING LAYER:                                                  │
│  ├── game-devices-udev (controller support)                     │
│  ├── gamemode (performance optimization)                        │
│  └── vulkan-loader (GPU acceleration)                           │
│                                                                 │
│  GUARDIAN LAYER:                                                │
│  ├── guardian-daemon (Rust)                                     │
│  │   ├── Policy sync from Supabase                              │
│  │   ├── Malcontent integration                                 │
│  │   ├── Session tracking                                       │
│  │   └── Remote commands                                        │
│  ├── guardian-games-launcher (Electron)                         │
│  │   ├── Game library UI                                        │
│  │   ├── Friends, parties, chat                                 │
│  │   └── Policy enforcement                                     │
│  ├── guardian-selector (boot-time child picker)                 │
│  ├── Polkit rules (lockdown guardian-child group)               │
│  └── GNOME schema overrides                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Experience Modes

| Mode | Description | Desktop Access |
|------|-------------|----------------|
| `kiosk` | Launcher-only. No desktop, file manager, browser. | None |
| `desktop_supervised` | Desktop visible, heavy monitoring, can't install apps. | Limited |
| `desktop_trusted` | Full desktop, light monitoring, parent notified of risky activity. | Full |

## Boot Flow

```
1. Power on → guardian-selector.service
2. Shows child selection UI: [Tommy] [Emma] [Jake]
3. Unlock method (PIN / FaceID / ask_parent / auto)
4. Configure autologin for that Linux user
5. GNOME session starts (or kiosk launcher)
6. guardian-agent.service starts in user session
7. Syncs policies from Supabase
8. Applies malcontent filters
9. Kid can play! 🎮
```

## Policy Sync

Guardian daemon syncs from Supabase tables:

- `children` - Child profile (name, age, avatar)
- `guardian_app_policies` - Per-child app rules (allowed/blocked/time-limited)
- `screen_time_policies` - Daily limits, bedtime
- `dns_policies` - Content filtering, safe search

The daemon converts these to:
- Malcontent app filters (OARS ratings + blocked apps)
- dconf settings (GNOME lockdown)
- Local rules cache (works offline)

## Game Library Scanning

The daemon scans installed games from:

| Source | Location |
|--------|----------|
| Steam | `~/.local/share/Steam/steamapps` |
| Steam (Flatpak) | `~/.var/app/com.valvesoftware.Steam/...` |
| Heroic (Epic) | `~/.config/heroic/legendaryConfig/installed.json` |
| Heroic (GOG) | `~/.config/heroic/gog_store/installed.json` |
| Lutris | `~/.config/lutris/games/*.yml` |
| Flatpak | `flatpak list --app` (game categories) |

Games are reported to Supabase. Parents approve/deny in dashboard.

## Parent Approval Flow

```
1. Kid launches game not in whitelist
2. Launcher shows "Ask parent for permission?"
3. Request sent to Supabase → Push notification to parent app
4. Parent sees: "Tommy wants to play GTA V (PEGI 18)" [Deny] [Approve]
5. Parent approves → guardian_app_policies updated
6. Daemon syncs → Kid can play
```

## Building

```bash
# Build the OCI image
podman build -t guardian-games:latest -f Containerfile.v2 .

# Or use BlueBuild
bluebuild build recipe.yml

# Create ISO for installation
# (uses lorax/mkksiso with the OCI image)
```

## Components

| Component | Language | Description |
|-----------|----------|-------------|
| `guardian-daemon` | Rust | System service, policy sync, malcontent |
| `guardian-selector` | Rust | Boot-time child picker UI |
| `guardian-games-launcher` | Electron/React | Game library, friends, chat |
| `guardian-web` | Next.js | Parent dashboard |
| `guardian-agent` | Rust | User session monitoring |

## Supabase Schema

Key tables:
- `families`, `children`, `devices`
- `app_catalog` - 49 games with PEGI ratings
- `guardian_app_policies` - Per-child rules
- `guardian_app_sessions` - Usage tracking
- `screen_time_policies`, `dns_policies`
- `device_commands` - Remote control queue

## Security Model

- **guardian-child** group: No sudo, blocked polkit actions
- **guardian-parent** group: Full admin access
- **Malcontent**: OARS-based app filtering
- **Polkit**: Blocks package install, network config, time changes
- **dconf lockdown**: No terminal, no extension install

## Compared to Bazzite

| Feature | Bazzite | Guardian |
|---------|---------|----------|
| Target user | Gamers | Families |
| Model | "Here's everything" | "Here's what you're allowed" |
| Launcher | Steam Big Picture | Guardian Games Launcher |
| Parental controls | None | Full stack |
| Remote management | None | Parent dashboard |
| Session tracking | None | Per-game, per-child |

## License

Proprietary - Guardian Network Solutions Ltd
