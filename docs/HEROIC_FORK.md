# Guardian Games - Heroic Fork Plan

## Overview

Guardian Games is a fork of [Heroic Games Launcher](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher) with added parental controls, age-based game filtering, screen time enforcement, and profile sync for families.

**License**: GPL-3.0 (same as Heroic)

## Heroic Architecture

```
HeroicGamesLauncher/
├── src/
│   ├── backend/                 # Electron main process
│   │   ├── main.ts              # Entry point
│   │   ├── launcher.ts          # Game launching logic ⭐
│   │   ├── config.ts            # Settings management ⭐
│   │   ├── constants.ts         # Paths, defaults
│   │   ├── storeManagers/       # Epic/GOG/Amazon APIs
│   │   │   ├── legendary/       # Epic Games (via Legendary CLI)
│   │   │   ├── gog/             # GOG (via gogdl CLI)
│   │   │   └── nile/            # Amazon (via Nile CLI)
│   │   ├── wine/                # Wine/Proton management
│   │   └── utils/               # Helpers
│   │
│   ├── frontend/                # React UI (renderer process)
│   │   ├── index.tsx            # React entry
│   │   ├── index.scss           # Global styles
│   │   ├── themes.scss          # Theme variables ⭐
│   │   ├── screens/
│   │   │   ├── Library/         # Game library view ⭐
│   │   │   ├── Game/            # Game detail page ⭐
│   │   │   ├── Settings/        # Settings screens ⭐
│   │   │   └── ...
│   │   ├── components/
│   │   │   ├── UI/              # Reusable components
│   │   │   └── ...
│   │   └── state/               # React state management
│   │
│   └── common/                  # Shared types & utilities
│       └── types/               # TypeScript interfaces
│           ├── game.ts          # GameInfo type ⭐
│           └── ...
│
├── public/
│   └── locales/                 # i18n translations
│
├── electron-builder.yml         # Build config
├── package.json
└── electron.vite.config.ts      # Vite config
```

## Key Modifications

### Backend Changes

1. **launcher.ts** - Add pre-launch checks for:
   - Game approval status
   - Screen time remaining
   - Age rating validation

2. **config.ts** - Add Guardian settings schema:
   - `guardian.enabled`, `guardian.userRole`, `guardian.familyId`
   - Per-game approval status

3. **New guardian/ module**:
   - `init.ts` - Initialize Guardian mode on app start
   - `parental.ts` - Age rating checks, game approval logic
   - `ratings.ts` - IGDB API integration for PEGI/ESRB
   - `screenTime.ts` - Track usage, enforce limits
   - `sync.ts` - Guardian Sync server client

### Frontend Changes

1. **Library** - Filter games by age rating, show approval badges
2. **Game Page** - Show rating, approval request button
3. **Settings** - New Guardian section for parents/children
4. **New Components**:
   - `ScreenTimeIndicator` - Shows remaining time
   - `RatingBadge` - PEGI/ESRB age display
   - `ApprovalButton` - Request parent approval

## Implementation Phases

| Phase | Duration | Focus |
|-------|----------|-------|
| 1. Foundation | Week 1-2 | Fork, CI/CD, config schema |
| 2. Age Filtering | Week 3-4 | IGDB API, rating comparison |
| 3. Game Approval | Week 5-6 | Request workflow, notifications |
| 4. Screen Time | Week 7-8 | Usage tracking, enforcement |
| 5. Sync & Polish | Week 9-10 | Server integration, theme |
| 6. Distribution | Week 11-12 | Flatpak, OS integration |

## External Dependencies

- **IGDB API** - Game ratings database (free tier)
- **Guardian Sync Server** - Custom backend (Supabase)
- **D-Bus** - OS-level screen time enforcement

## See Full Plan

For complete code examples and detailed implementation:
- Full file at: `docs/guardian-games-heroic-fork-plan.md`
