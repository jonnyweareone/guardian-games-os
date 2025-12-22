# Guardian OS - Deployment Architecture

## Core Concept: Repo = Deployment System

The OS repository **is** the deployment system. Like Vercel, pushing changes triggers builds.

```
┌─────────────────────────────────────────────────────────────────┐
│  VERCEL                              GUARDIAN OS                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Edit code in repo                   Parent saves settings      │
│       ↓                                     ↓                   │
│  git push                            API commits to repo        │
│       ↓                                     ↓                   │
│  Vercel detects change               GitHub detects change      │
│       ↓                                     ↓                   │
│  Build triggered                     Build triggered            │
│       ↓                                     ↓                   │
│  Deploy to CDN                       Push to GHCR               │
│       ↓                                     ↓                   │
│  site.vercel.app                     hash:version               │
│                                                                 │
│  It's the same pattern.                                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Repository Structure

```
guardian-os/
│
├── base/                           # Shared base image
│   ├── Containerfile               # Base OS definition
│   ├── packages/
│   │   ├── core.txt               # Always installed
│   │   ├── gaming.txt             # Gaming packages
│   │   └── education.txt          # Education packages
│   └── system_files/              # Base system config
│
├── deployments/                    # Per-child deployments
│   │
│   ├── a1b2c3d4e5f6/              # Tommy (hash = privacy)
│   │   ├── manifest.json          # Version, metadata
│   │   ├── config.json            # Settings snapshot
│   │   ├── identity.json          # Auth tokens (encrypted)
│   │   ├── apps.json              # Allowed/blocked apps
│   │   └── CHANGELOG.md           # Auto-generated history
│   │
│   ├── f7g8h9i0j1k2/              # Sarah
│   │   └── ...
│   │
│   └── x9y8z7w6v5u4/              # Family shared
│       └── ...
│
├── .github/
│   └── workflows/
│       ├── build-deployment.yml   # Build specific deployment
│       ├── build-base.yml         # Rebuild base image
│       └── validate-config.yml    # PR validation
│
└── scripts/
    ├── build-image.sh             # Image builder
    ├── validate-config.sh         # Config validator
    └── generate-identity.sh       # Token generator
```

## Deployment Files

### manifest.json
```json
{
  "hash": "a1b2c3d4e5f6",
  "version": 7,
  "child_id": "encrypted:xxxxx",
  "family_id": "encrypted:xxxxx",
  "created_at": "2024-12-22T10:00:00Z",
  "updated_at": "2024-12-22T15:30:00Z",
  "updated_by": "parent",
  "change_reason": "Added Minecraft for birthday",
  "base_version": "41-stable"
}
```

### config.json
```json
{
  "screen_time": {
    "enabled": true,
    "weekday_limit_minutes": 120,
    "weekend_limit_minutes": 180,
    "allowed_hours": {
      "start": "08:00",
      "end": "20:00"
    },
    "homework_mode": {
      "enabled": true,
      "required_minutes": 30,
      "before_games": true
    }
  },
  "content_filter": {
    "level": "moderate",
    "custom_blocked": ["gambling", "dating"],
    "custom_allowed": []
  },
  "privacy": {
    "location_sharing": false,
    "activity_reports": true,
    "screenshot_monitoring": false
  },
  "safety": {
    "chat_filtering": true,
    "ai_monitoring": true,
    "parent_intervention": "alerts_only"
  }
}
```

### apps.json
```json
{
  "allowed": [
    { "id": "minecraft-launcher", "source": "flatpak" },
    { "id": "steam", "source": "rpm" },
    { "id": "heroic-games-launcher", "source": "flatpak" },
    { "id": "firefox", "source": "rpm" }
  ],
  "blocked": [
    { "id": "discord", "reason": "Age restriction" },
    { "id": "tiktok", "reason": "Parent blocked" }
  ],
  "game_ratings": {
    "max_esrb": "E10+",
    "max_pegi": "12",
    "allow_unrated": false
  }
}
```

### identity.json (encrypted in repo)
```json
{
  "_encrypted": true,
  "_key_id": "guardian-deploy-key-2024",
  "data": "base64-encrypted-blob..."
}
```

When decrypted during build:
```json
{
  "image_hash": "a1b2c3d4e5f6",
  "version": 7,
  "child_id": "uuid-here",
  "child_name": "Tommy",
  "family_id": "uuid-here",
  "child_token": "eyJ...",
  "nakama_token": "eyJ...",
  "refresh_token": "eyJ...",
  "supabase_url": "https://xxx.supabase.co",
  "nakama_host": "192.248.163.171"
}
```

## GitHub Actions Workflow

```yaml
# .github/workflows/build-deployment.yml

name: Build Deployment

on:
  push:
    paths:
      - 'deployments/**/config.json'
      - 'deployments/**/apps.json'
      - 'deployments/**/manifest.json'
  workflow_dispatch:
    inputs:
      deployment_hash:
        description: 'Deployment hash to build'
        required: true

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      deployments: ${{ steps.changes.outputs.deployments }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2
      
      - name: Detect changed deployments
        id: changes
        run: |
          if [ "${{ github.event_name }}" == "workflow_dispatch" ]; then
            echo "deployments=[\"${{ inputs.deployment_hash }}\"]" >> $GITHUB_OUTPUT
          else
            CHANGED=$(git diff --name-only HEAD~1 | grep '^deployments/' | cut -d'/' -f2 | sort -u | jq -R -s -c 'split("\n") | map(select(length > 0))')
            echo "deployments=$CHANGED" >> $GITHUB_OUTPUT
          fi

  build:
    needs: detect-changes
    runs-on: ubuntu-latest
    strategy:
      matrix:
        deployment: ${{ fromJson(needs.detect-changes.outputs.deployments) }}
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Read manifest
        id: manifest
        run: |
          MANIFEST="deployments/${{ matrix.deployment }}/manifest.json"
          echo "version=$(jq -r '.version' $MANIFEST)" >> $GITHUB_OUTPUT
          echo "hash=${{ matrix.deployment }}" >> $GITHUB_OUTPUT
      
      - name: Decrypt identity
        env:
          DEPLOY_KEY: ${{ secrets.GUARDIAN_DEPLOY_KEY }}
        run: |
          ./scripts/decrypt-identity.sh \
            deployments/${{ matrix.deployment }}/identity.json \
            /tmp/identity-decrypted.json
      
      - name: Build image
        run: |
          podman build \
            --build-arg DEPLOYMENT_DIR=deployments/${{ matrix.deployment }} \
            --build-arg IDENTITY_FILE=/tmp/identity-decrypted.json \
            -t ghcr.io/guardian-os/images/${{ steps.manifest.outputs.hash }}:v${{ steps.manifest.outputs.version }} \
            -f base/Containerfile .
      
      - name: Push to GHCR
        run: |
          echo "${{ secrets.GHCR_TOKEN }}" | podman login ghcr.io -u guardian-os --password-stdin
          podman push ghcr.io/guardian-os/images/${{ steps.manifest.outputs.hash }}:v${{ steps.manifest.outputs.version }}
      
      - name: Update deployment status
        env:
          SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
          SUPABASE_KEY: ${{ secrets.SUPABASE_SERVICE_KEY }}
        run: |
          curl -X POST "$SUPABASE_URL/functions/v1/deployment-ready" \
            -H "Authorization: Bearer $SUPABASE_KEY" \
            -H "Content-Type: application/json" \
            -d '{
              "hash": "${{ steps.manifest.outputs.hash }}",
              "version": ${{ steps.manifest.outputs.version }},
              "image": "ghcr.io/guardian-os/images/${{ steps.manifest.outputs.hash }}:v${{ steps.manifest.outputs.version }}"
            }'
      
      - name: Notify parent
        run: |
          # OneSignal push notification
          curl -X POST "https://onesignal.com/api/v1/notifications" \
            -H "Authorization: Basic ${{ secrets.ONESIGNAL_API_KEY }}" \
            -H "Content-Type: application/json" \
            -d '{
              "app_id": "${{ secrets.ONESIGNAL_APP_ID }}",
              "include_external_user_ids": ["parent-id-from-manifest"],
              "contents": {"en": "Update ready for Tommy'\''s device"},
              "data": {"type": "deployment_ready", "hash": "${{ steps.manifest.outputs.hash }}", "version": ${{ steps.manifest.outputs.version }}}
            }'
```

## Parent Dashboard → Repo Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  PARENT SAVES SETTINGS                                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Parent clicks "Save" in dashboard                           │
│       ↓                                                         │
│  2. Supabase Edge Function triggered                            │
│       ↓                                                         │
│  3. Edge Function:                                              │
│     a. Increments version in manifest.json                      │
│     b. Updates config.json with new settings                    │
│     c. Regenerates identity.json with fresh tokens              │
│     d. Commits to repo via GitHub API                           │
│       ↓                                                         │
│  4. GitHub Actions detects change                               │
│       ↓                                                         │
│  5. Build workflow runs                                         │
│       ↓                                                         │
│  6. Image pushed to GHCR                                        │
│       ↓                                                         │
│  7. Supabase updated with "ready" status                        │
│       ↓                                                         │
│  8. Parent notified "Update ready"                              │
│       ↓                                                         │
│  9. Parent can deploy now or schedule                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Supabase Edge Function: Save Settings

```typescript
// supabase/functions/save-child-settings/index.ts

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { Octokit } from 'https://esm.sh/octokit';

const octokit = new Octokit({ auth: Deno.env.get('GITHUB_TOKEN') });
const REPO_OWNER = 'guardian-os';
const REPO_NAME = 'guardian-os';

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  // Verify parent auth
  const authHeader = req.headers.get('Authorization');
  const { data: { user }, error: authError } = await supabase.auth.getUser(
    authHeader?.replace('Bearer ', '')
  );
  if (authError || !user) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
  }

  const { child_id, settings, reason } = await req.json();

  // Get child's deployment info
  const { data: child } = await supabase
    .from('children')
    .select('*, image_hashes(*), deployments(*)')
    .eq('id', child_id)
    .single();

  if (!child) {
    return new Response(JSON.stringify({ error: 'Child not found' }), { status: 404 });
  }

  const hash = child.image_hashes.hash;
  const currentVersion = child.deployments?.[0]?.version || 0;
  const newVersion = currentVersion + 1;

  // Generate new identity tokens
  const identity = await generateIdentityTokens(child, hash, newVersion);

  // Encrypt identity for repo storage
  const encryptedIdentity = await encryptIdentity(identity);

  // Update files in repo
  const deploymentPath = `deployments/${hash}`;

  // 1. Update manifest.json
  const manifest = {
    hash,
    version: newVersion,
    child_id: encrypt(child_id),
    family_id: encrypt(child.family_id),
    created_at: child.image_hashes.created_at,
    updated_at: new Date().toISOString(),
    updated_by: user.id,
    change_reason: reason,
    base_version: '41-stable'
  };

  await updateRepoFile(
    `${deploymentPath}/manifest.json`,
    JSON.stringify(manifest, null, 2),
    `v${newVersion}: ${reason}`
  );

  // 2. Update config.json
  await updateRepoFile(
    `${deploymentPath}/config.json`,
    JSON.stringify(settings, null, 2),
    `v${newVersion}: ${reason}`
  );

  // 3. Update identity.json (encrypted)
  await updateRepoFile(
    `${deploymentPath}/identity.json`,
    JSON.stringify(encryptedIdentity, null, 2),
    `v${newVersion}: ${reason}`
  );

  // Record deployment in Supabase
  const { data: deployment } = await supabase
    .from('deployments')
    .insert({
      image_hash_id: child.image_hashes.id,
      version: newVersion,
      status: 'building',
      settings_snapshot: settings,
      change_reason: reason,
      deployed_by: user.id
    })
    .select()
    .single();

  return new Response(JSON.stringify({
    success: true,
    deployment_id: deployment.id,
    version: newVersion,
    status: 'building'
  }));
});

async function updateRepoFile(path: string, content: string, message: string) {
  // Get current file SHA (if exists)
  let sha: string | undefined;
  try {
    const { data } = await octokit.rest.repos.getContent({
      owner: REPO_OWNER,
      repo: REPO_NAME,
      path
    });
    sha = (data as any).sha;
  } catch (e) {
    // File doesn't exist yet
  }

  // Create or update file
  await octokit.rest.repos.createOrUpdateFileContents({
    owner: REPO_OWNER,
    repo: REPO_NAME,
    path,
    message,
    content: btoa(content),
    sha
  });
}

async function generateIdentityTokens(child: any, hash: string, version: number) {
  // Generate JWT for this child
  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  // Create custom JWT with child claims
  const { data: { session } } = await supabaseAdmin.auth.admin.generateLink({
    type: 'magiclink',
    email: `${hash}@device.guardian.local`
  });

  // Generate Nakama token
  const nakamaToken = await generateNakamaToken(child.id, child.username);

  return {
    image_hash: hash,
    version,
    child_id: child.id,
    child_name: child.display_name || child.username,
    family_id: child.family_id,
    child_token: session?.access_token,
    nakama_token: nakamaToken,
    refresh_token: session?.refresh_token,
    supabase_url: Deno.env.get('SUPABASE_URL'),
    nakama_host: '192.248.163.171',
    nakama_port: '7350',
    issued_at: new Date().toISOString()
  };
}
```

## Device Update Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  DEVICE RECEIVES UPDATE                                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Device daemon polls Supabase every 5 minutes                   │
│       ↓                                                         │
│  SELECT target_deployment_id FROM devices                       │
│  WHERE machine_id = 'xxx'                                       │
│       ↓                                                         │
│  If target != current:                                          │
│       ↓                                                         │
│  Fetch deployment details                                       │
│       ↓                                                         │
│  If status = 'ready' AND within update window:                  │
│       ↓                                                         │
│  rpm-ostree rebase ghcr.io/guardian-os/images/hash:vN           │
│       ↓                                                         │
│  Schedule reboot (or immediate if parent requested)             │
│       ↓                                                         │
│  After reboot: Update current_deployment_id                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Benefits

| Aspect | Before (API-triggered) | After (Repo-based) |
|--------|------------------------|---------------------|
| **Trigger** | Webhook + Edge Function | Git push |
| **History** | Supabase only | Git + Supabase |
| **Rollback** | Query old settings | `git revert` |
| **Audit** | Custom logging | Git blame |
| **Debugging** | Check logs | Check commits |
| **Diff** | Custom UI | GitHub diff |
| **CI/CD** | Custom | Native GitHub Actions |
| **Secrets** | Edge Function | GitHub Secrets |

## Privacy Maintained

```
┌─────────────────────────────────────────────────────────────────┐
│  WHAT'S VISIBLE IN PUBLIC REPO                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ✓ Deployment hashes: a1b2c3d4e5f6, f7g8h9i0j1k2               │
│  ✓ Config structure (not values in production)                  │
│  ✓ Version numbers                                              │
│  ✓ Timestamps                                                   │
│                                                                 │
│  ✗ Child names (encrypted)                                      │
│  ✗ Family info (encrypted)                                      │
│  ✗ Auth tokens (encrypted)                                      │
│  ✗ Parent identities                                            │
│                                                                 │
│  For private repo (recommended):                                │
│  Everything is private, GitHub Team plan $4/user/month          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Summary

**The repo IS the deployment system:**
- Git commits = deployments
- Git history = audit log
- GitHub Actions = build system
- GHCR = artifact registry
- `git revert` = rollback

**Simplifies everything:**
- No custom webhook infrastructure
- No edge function complexity
- Native GitHub tooling
- Free CI/CD minutes
- Built-in collaboration features

**This is literally Vercel for OS deployments.**
