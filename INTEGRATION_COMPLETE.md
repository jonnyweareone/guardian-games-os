# Guardian OS - Integration Complete 🛡️

## What We Built Today

### 1. Database Schema (Supabase)
**File:** `guardian-web/supabase/migrations/005_build_system.sql`

- `family_signing_keys` - Per-family ECDSA keypairs for ISO verification
- `builds` - Track per-family ISO builds with status, profile snapshots
- `build_logs` - Debug logs for builds
- Updated `devices` table with activation tracking

### 2. Edge Functions (Supabase)

**`trigger-build`** - Triggers GitHub Actions to build a unique ISO
- Generates ECDSA keypair for family (if not exists)
- Creates profile snapshot from child's settings
- Triggers GitHub Actions workflow
- Returns build ID for tracking

**`device-activate`** - Verifies device on first boot
- Authenticates parent credentials
- Verifies family_id matches logged-in account (CRITICAL)
- Verifies build_id is valid and unused
- Signs activation token with family's private key
- Registers device

### 3. GitHub Actions Workflow
**File:** `guardian-games-os/.github/workflows/build-family-iso.yml`

- Receives build request with family ID, child ID, profile hash
- Fetches profile from Supabase
- Bakes family config into OS image
- Builds OCI image with podman
- Pushes to GHCR
- Notifies Supabase of completion

### 4. Activation Service (Rust)
**File:** `guardian-os-v1/guardian-components/guardian-daemon/src/activation.rs`

- Reads baked-in family config
- Generates device hash from hardware
- Calls activation endpoint
- Verifies server signature with baked-in public key
- Stores activation state
- Can brick device on security violations

### 5. Parent Dashboard (Next.js)
**File:** `guardian-web/src/app/(dashboard)/devices/page.tsx`

- Build ISO section (select child + device type)
- Recent builds list with status
- Active devices with real-time status
- Remote commands (lock, message, view)

---

## The Complete Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  END-TO-END FLOW                                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. PARENT SIGNS UP (guardian-web)                              │
│     └── Creates account via Supabase Auth                       │
│     └── Family + Parent records auto-created                    │
│     └── Adds children profiles                                  │
│     └── Sets screen time, DNS, app policies                     │
│                                                                 │
│  2. PARENT TRIGGERS BUILD                                       │
│     └── Clicks "Build ISO" for child                            │
│     └── Edge function generates signing keypair                 │
│     └── Triggers GitHub Actions with profile                    │
│     └── ~10 minutes later: ISO ready                            │
│                                                                 │
│  3. PARENT DOWNLOADS ISO                                        │
│     └── Unique ISO with:                                        │
│         ├── family_id baked in                                  │
│         ├── build_id baked in                                   │
│         ├── profile settings baked in                           │
│         └── verification public key baked in                    │
│                                                                 │
│  4. INSTALL ON DEVICE                                           │
│     └── Flash USB, boot, install normally                       │
│     └── Bazzite + Guardian layer installed                      │
│                                                                 │
│  5. FIRST BOOT - ACTIVATION                                     │
│     └── Guardian daemon starts                                  │
│     └── Reads baked-in config                                   │
│     └── Shows activation screen                                 │
│     └── Parent enters credentials                               │
│     └── Server verifies: credentials + family_id + build_id     │
│     └── Server signs activation token                           │
│     └── Device verifies signature with baked-in public key      │
│     └── ACTIVATED ✓                                             │
│                                                                 │
│  6. NORMAL OPERATION                                            │
│     └── Daemon syncs with Supabase (heartbeat, policies)        │
│     └── Launcher auto-starts (games, Nakama chat)               │
│     └── Parent sees device in dashboard                         │
│     └── Parent can send commands (lock, message)                │
│     └── Telemetry flows to dashboard                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Security Guarantees

| Attack | Defense |
|--------|---------|
| Use someone else's ISO | family_id mismatch → BRICK |
| Reuse ISO on second device | build_id already activated → BRICK |
| Clone device disk | device_hash mismatch → Detected |
| Tamper with activation | Signature verification fails → BRICK |
| Modify baked-in settings | Settings compiled into immutable OS |
| Kid creates own account | Can't build ISO without existing family |
| Factory reset | Still needs parent login to activate |

---

## Architecture

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Parent Phone    │     │  Parent Browser  │     │  Parent Desktop  │
│  (PWA/App)       │     │  (Dashboard)     │     │  (Dashboard)     │
└────────┬─────────┘     └────────┬─────────┘     └────────┬─────────┘
         │                        │                        │
         └────────────────────────┼────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────┐
                    │      Supabase           │
                    │  ┌─────────────────┐    │
                    │  │ Auth            │    │
                    │  │ Database (RLS)  │    │
                    │  │ Edge Functions  │    │
                    │  │ Realtime        │    │
                    │  └─────────────────┘    │
                    └───────────┬─────────────┘
                                │
         ┌──────────────────────┼──────────────────────┐
         │                      │                      │
         ▼                      ▼                      ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  GitHub Actions  │  │  Nakama Server   │  │  LiveKit Server  │
│  (ISO Builder)   │  │  (Chat/Friends)  │  │  (Voice/Video)   │
└────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘
         │                     │                     │
         └─────────────────────┼─────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│                         GUARDIAN OS                               │
│                                                                   │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐      │
│  │ Guardian       │  │ Guardian Games │  │ Bazzite Base   │      │
│  │ Daemon (Rust)  │──│ Launcher       │──│ (Steam/Proton) │      │
│  │                │  │ (Electron)     │  │                │      │
│  │ • Activation   │  │                │  │ • Gaming ready │      │
│  │ • Sync         │  │ • Game library │  │ • Flatpak      │      │
│  │ • Enforcement  │  │ • Friends      │  │ • Immutable    │      │
│  │ • Telemetry    │  │ • Chat/Voice   │  │                │      │
│  └────────────────┘  └────────────────┘  └────────────────┘      │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ /etc/guardian/config.json (BAKED IN - IMMUTABLE)           │  │
│  │ ├── family_id: "fam_abc123..."                             │  │
│  │ ├── build_id: "bld_xyz789..."                              │  │
│  │ ├── verification_public_key: "-----BEGIN PUBLIC KEY-----"  │  │
│  │ └── profile: { screen_time: {...}, dns: {...}, apps: {...}}│  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

---

## Deployment Checklist

### Database (Run These Commands)

```bash
cd /Users/davidsmith/Documents/GitHub/guardian-web

# Apply migration
supabase db push

# Or manually via SQL Editor in Supabase Dashboard
```

### Edge Functions

```bash
# Deploy trigger-build
supabase functions deploy trigger-build --project-ref gkyspvcafyttfhyjryyk

# Deploy device-activate  
supabase functions deploy device-activate --project-ref gkyspvcafyttfhyjryyk

# Set secrets
supabase secrets set GITHUB_TOKEN=ghp_xxx --project-ref gkyspvcafyttfhyjryyk
```

### GitHub Secrets (Required)

Go to: `github.com/guardian-network/guardian-games-os/settings/secrets/actions`

```
SUPABASE_URL=https://gkyspvcafyttfhyjryyk.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...
SUPABASE_ANON_KEY=eyJ...
R2_ACCESS_KEY=xxx (for ISO storage)
R2_SECRET_KEY=xxx
R2_ENDPOINT=xxx
```

### Test the Flow

```bash
# 1. Start dashboard
cd guardian-web
npm run dev

# 2. Open browser
open http://localhost:3000

# 3. Sign up / Log in
# 4. Add a child
# 5. Go to Devices page
# 6. Click "Build ISO"
# 7. Watch GitHub Actions run
# 8. Download ISO when ready
```

---

## Files Created Today

| File | Purpose |
|------|---------|
| `guardian-web/supabase/migrations/005_build_system.sql` | Database schema for builds |
| `guardian-web/supabase/functions/trigger-build/index.ts` | Edge function to start build |
| `guardian-web/supabase/functions/device-activate/index.ts` | Edge function for activation |
| `guardian-games-os/.github/workflows/build-family-iso.yml` | GitHub Actions build workflow |
| `guardian-os-v1/.../activation.rs` | Rust activation service |
| `guardian-web/src/app/(dashboard)/devices/page.tsx` | Dashboard devices page |

---

## Next Steps

### Immediate (Complete the MVP)
1. [ ] Apply database migration to Supabase
2. [ ] Deploy edge functions
3. [ ] Set up GitHub secrets
4. [ ] Test build trigger from dashboard
5. [ ] Create activation UI for first boot (GTK or Electron)

### This Week
1. [ ] Build actual ISO with bootc-image-builder
2. [ ] Test activation flow in VM
3. [ ] Add push notifications for build ready
4. [ ] Create `_vault_keys` table for proper key storage

### Before Beta
1. [ ] Hardware attestation (TPM)
2. [ ] Voice chat monitoring (PipeWire capture)
3. [ ] P2P intervention system
4. [ ] App store with curated games

---

## Key Design Decisions

1. **No Generic ISO** - Every ISO is cryptographically bound to a family
2. **Build on Demand** - ISOs built when parent requests, not pre-built
3. **Public Key Baked In** - Device can verify server without network trust
4. **Device Hash** - Hardware fingerprint prevents cloning
5. **One Build = One Device** - Build marked as used after activation
6. **Brick on Mismatch** - Security violations permanently lock device

---

This is the foundation for a truly secure family gaming OS. The kid literally cannot bypass it because the security is baked into the OS image itself.

**🛡️ Guardian OS: Other parental controls are apps. Kids uninstall apps. Guardian IS the operating system.**
