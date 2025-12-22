# Guardian OS - Identity-as-Image Architecture

## Core Concept

The OS image **IS** the authentication. No separate login needed.

```
┌─────────────────────────────────────────────────────────────────┐
│  IMAGE = IDENTITY                                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  When parent creates deployment for Tommy:                      │
│                                                                 │
│  1. Settings saved in Supabase                                  │
│  2. GitHub Action builds image                                  │
│  3. Image includes /usr/share/guardian/identity.json:           │
│     {                                                           │
│       "image_hash": "a1b2c3d4e5f6",                             │
│       "version": 7,                                             │
│       "child_token": "eyJ...",  // JWT for this child           │
│       "family_id": "uuid",                                      │
│       "child_id": "uuid",                                       │
│       "child_name": "Tommy",                                    │
│       "issued_at": "2024-12-22T...",                            │
│       "nakama_token": "eyJ..."  // Pre-authenticated            │
│     }                                                           │
│  4. Image pushed to GHCR                                        │
│  5. Device pulls & reboots                                      │
│  6. Guardian Launcher reads identity.json                       │
│  7. Child is ALREADY logged in                                  │
│                                                                 │
│  Kid NEVER sees a login screen.                                 │
│  OS = Identity = Authenticated.                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Security Model

```
┌─────────────────────────────────────────────────────────────────┐
│  WHY THIS IS SECURE                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Q: Can't kid extract token and use elsewhere?                  │
│  A: Token is bound to image_hash. Server validates.             │
│     Different machine = different image_hash = rejected.        │
│                                                                 │
│  Q: Can't kid copy the whole disk?                              │
│  A: machine_id is validated. Clone won't have same ID.          │
│     Plus, parent sees "new device" alert.                       │
│                                                                 │
│  Q: Can't kid reinstall regular Linux?                          │
│  A: Sure. Then they have no Guardian, no games.                 │
│     Parent gets alert "device offline".                         │
│     Physical access = game over (true for all systems)          │
│                                                                 │
│  Q: What about token expiry?                                    │
│  A: Refresh token in identity.json.                             │
│     Daemon refreshes silently. New deployment = new tokens.     │
│                                                                 │
│  Q: Can parent revoke?                                          │
│  A: Mark image_hash as revoked in Supabase.                     │
│     Next API call fails. Device locked out instantly.           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Build Process

```yaml
# .github/workflows/build-child-image.yml

name: Build Child Image

on:
  repository_dispatch:
    types: [build-deployment]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Get deployment details
        id: deployment
        run: |
          # Fetch from Supabase (passed via dispatch payload)
          echo "image_hash=${{ github.event.client_payload.image_hash }}" >> $GITHUB_OUTPUT
          echo "version=${{ github.event.client_payload.version }}" >> $GITHUB_OUTPUT
          echo "child_id=${{ github.event.client_payload.child_id }}" >> $GITHUB_OUTPUT
          echo "family_id=${{ github.event.client_payload.family_id }}" >> $GITHUB_OUTPUT
          echo "child_name=${{ github.event.client_payload.child_name }}" >> $GITHUB_OUTPUT
      
      - name: Generate identity tokens
        id: tokens
        env:
          SUPABASE_SERVICE_KEY: ${{ secrets.SUPABASE_SERVICE_KEY }}
        run: |
          # Call Supabase Edge Function to generate tokens
          RESPONSE=$(curl -X POST \
            "${{ secrets.SUPABASE_URL }}/functions/v1/generate-child-tokens" \
            -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
            -H "Content-Type: application/json" \
            -d '{
              "child_id": "${{ steps.deployment.outputs.child_id }}",
              "image_hash": "${{ steps.deployment.outputs.image_hash }}",
              "version": ${{ steps.deployment.outputs.version }}
            }')
          
          echo "child_token=$(echo $RESPONSE | jq -r '.child_token')" >> $GITHUB_OUTPUT
          echo "nakama_token=$(echo $RESPONSE | jq -r '.nakama_token')" >> $GITHUB_OUTPUT
          echo "refresh_token=$(echo $RESPONSE | jq -r '.refresh_token')" >> $GITHUB_OUTPUT
      
      - name: Create identity.json
        run: |
          mkdir -p build/usr/share/guardian
          cat > build/usr/share/guardian/identity.json << EOF
          {
            "image_hash": "${{ steps.deployment.outputs.image_hash }}",
            "version": ${{ steps.deployment.outputs.version }},
            "family_id": "${{ steps.deployment.outputs.family_id }}",
            "child_id": "${{ steps.deployment.outputs.child_id }}",
            "child_name": "${{ steps.deployment.outputs.child_name }}",
            "child_token": "${{ steps.tokens.outputs.child_token }}",
            "nakama_token": "${{ steps.tokens.outputs.nakama_token }}",
            "refresh_token": "${{ steps.tokens.outputs.refresh_token }}",
            "issued_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
            "supabase_url": "${{ secrets.SUPABASE_URL }}",
            "nakama_host": "192.248.163.171",
            "nakama_port": "7350"
          }
          EOF
          
          # Secure permissions
          chmod 600 build/usr/share/guardian/identity.json
      
      - name: Build OCI image
        run: |
          podman build \
            --build-arg IDENTITY_DIR=build/usr/share/guardian \
            -t ghcr.io/guardian-os/images/${{ steps.deployment.outputs.image_hash }}:v${{ steps.deployment.outputs.version }} \
            -f Containerfile .
      
      - name: Push to GHCR
        run: |
          echo "${{ secrets.GHCR_TOKEN }}" | podman login ghcr.io -u guardian-os --password-stdin
          podman push ghcr.io/guardian-os/images/${{ steps.deployment.outputs.image_hash }}:v${{ steps.deployment.outputs.version }}
      
      - name: Update deployment status
        run: |
          curl -X PATCH \
            "${{ secrets.SUPABASE_URL }}/rest/v1/deployments?id=eq.${{ github.event.client_payload.deployment_id }}" \
            -H "Authorization: Bearer ${{ secrets.SUPABASE_SERVICE_KEY }}" \
            -H "Content-Type: application/json" \
            -H "Prefer: return=minimal" \
            -d '{"status": "ready", "build_finished_at": "now()"}'
```

## Containerfile Addition

```dockerfile
# In Containerfile, add identity baking

# ... existing build steps ...

# Bake in identity (passed as build arg or copied)
ARG IDENTITY_DIR
COPY ${IDENTITY_DIR}/identity.json /usr/share/guardian/identity.json
RUN chmod 600 /usr/share/guardian/identity.json && \
    chown root:guardian /usr/share/guardian/identity.json
```

## Guardian Launcher - Auto Auth

```typescript
// src/main/services/identityAuth.ts

import * as fs from 'fs';
import * as path from 'path';

interface GuardianIdentity {
  image_hash: string;
  version: number;
  family_id: string;
  child_id: string;
  child_name: string;
  child_token: string;
  nakama_token: string;
  refresh_token: string;
  issued_at: string;
  supabase_url: string;
  nakama_host: string;
  nakama_port: string;
}

const IDENTITY_PATH = '/usr/share/guardian/identity.json';

class IdentityAuthService {
  private identity: GuardianIdentity | null = null;

  /**
   * Load identity from OS image
   * This is baked in at build time - no login needed!
   */
  async loadIdentity(): Promise<GuardianIdentity | null> {
    try {
      // Check if running on Guardian OS
      if (!fs.existsSync(IDENTITY_PATH)) {
        console.log('Not running on Guardian OS - identity.json not found');
        return null;
      }

      const content = fs.readFileSync(IDENTITY_PATH, 'utf-8');
      this.identity = JSON.parse(content);
      
      console.log(`Loaded identity: ${this.identity.child_name} (${this.identity.image_hash}:v${this.identity.version})`);
      
      return this.identity;
    } catch (error) {
      console.error('Failed to load identity:', error);
      return null;
    }
  }

  /**
   * Get Supabase session from baked-in token
   */
  async getSupabaseSession(): Promise<any> {
    if (!this.identity) {
      await this.loadIdentity();
    }
    
    if (!this.identity) {
      throw new Error('No identity available');
    }

    // Token is pre-authenticated - just use it
    return {
      access_token: this.identity.child_token,
      refresh_token: this.identity.refresh_token,
      user: {
        id: this.identity.child_id,
        email: `${this.identity.image_hash}@guardian.local`,
        user_metadata: {
          name: this.identity.child_name,
          family_id: this.identity.family_id,
          image_hash: this.identity.image_hash
        }
      }
    };
  }

  /**
   * Get Nakama session from baked-in token
   */
  getNakamaCredentials(): { host: string; port: string; token: string } | null {
    if (!this.identity) return null;
    
    return {
      host: this.identity.nakama_host,
      port: this.identity.nakama_port,
      token: this.identity.nakama_token
    };
  }

  /**
   * Refresh tokens (called by daemon periodically)
   */
  async refreshTokens(): Promise<boolean> {
    if (!this.identity) return false;

    try {
      const response = await fetch(`${this.identity.supabase_url}/functions/v1/refresh-child-tokens`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.identity.child_token}`
        },
        body: JSON.stringify({
          refresh_token: this.identity.refresh_token,
          image_hash: this.identity.image_hash,
          machine_id: this.getMachineId()
        })
      });

      if (!response.ok) {
        // Token revoked or invalid
        return false;
      }

      const newTokens = await response.json();
      
      // Update in-memory (can't write to immutable OS)
      this.identity.child_token = newTokens.child_token;
      this.identity.nakama_token = newTokens.nakama_token;
      
      return true;
    } catch (error) {
      console.error('Token refresh failed:', error);
      return false;
    }
  }

  /**
   * Get machine ID for validation
   */
  private getMachineId(): string {
    try {
      return fs.readFileSync('/etc/machine-id', 'utf-8').trim();
    } catch {
      return 'unknown';
    }
  }

  /**
   * Check if running on Guardian OS with valid identity
   */
  isGuardianOS(): boolean {
    return this.identity !== null;
  }

  getIdentity(): GuardianIdentity | null {
    return this.identity;
  }
}

export const identityAuth = new IdentityAuthService();
export default identityAuth;
```

## Updated Auth Store

```typescript
// src/renderer/stores/authStore.ts - Updated for identity-based auth

import { create } from 'zustand';
import { Session } from '@heroiclabs/nakama-js';
import nakama from '../services/nakama';

interface User {
  id: string;
  username: string;
  displayName?: string;
  familyId: string;
  imageHash: string;
  isGuardianOS: boolean;
}

interface AuthState {
  session: Session | null;
  user: User | null;
  isLoading: boolean;
  error: string | null;
  isGuardianOS: boolean;
  
  // Actions
  initializeAuth: () => Promise<void>;
  logout: () => Promise<void>;
}

export const useAuthStore = create<AuthState>((set, get) => ({
  session: null,
  user: null,
  isLoading: true,
  error: null,
  isGuardianOS: false,

  initializeAuth: async () => {
    set({ isLoading: true, error: null });

    try {
      // Check if running on Guardian OS
      const identity = await window.electron?.identity?.load();
      
      if (identity) {
        // Guardian OS - auto-authenticate with baked-in tokens
        console.log('Guardian OS detected - auto-authenticating as', identity.child_name);
        
        const nakamaCredentials = await window.electron?.identity?.getNakamaCredentials();
        
        if (nakamaCredentials) {
          // Restore Nakama session from pre-authenticated token
          const session = await nakama.restoreFromToken(nakamaCredentials.token);
          
          set({
            session,
            user: {
              id: identity.child_id,
              username: identity.child_name,
              displayName: identity.child_name,
              familyId: identity.family_id,
              imageHash: identity.image_hash,
              isGuardianOS: true
            },
            isGuardianOS: true,
            isLoading: false
          });
          
          return;
        }
      }
      
      // Not Guardian OS - fall back to manual auth
      console.log('Not Guardian OS - showing login screen');
      set({ isLoading: false, isGuardianOS: false });
      
    } catch (error: any) {
      console.error('Auth initialization failed:', error);
      set({ error: error.message, isLoading: false });
    }
  },

  logout: async () => {
    // On Guardian OS, "logout" doesn't make sense
    // The OS IS the identity
    const { isGuardianOS } = get();
    
    if (isGuardianOS) {
      // Can't really logout - just disconnect socket
      await nakama.logout();
      // User is still "logged in" - would need OS reinstall to change identity
    } else {
      await nakama.logout();
      await window.electron?.store.delete('nakama_token');
      set({ session: null, user: null });
    }
  }
}));
```

## Flow Comparison

```
┌─────────────────────────────────────────────────────────────────┐
│  BEFORE (Device Binding)                                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. OS installs (generic Guardian OS)                           │
│  2. First boot shows pairing screen                             │
│  3. Parent enters code on phone                                 │
│  4. Device bound to child                                       │
│  5. Subsequent boots auto-login                                 │
│                                                                 │
│  Complexity: Medium                                             │
│  First-boot: Requires parent interaction                        │
│  Security: Good                                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  AFTER (Identity-as-Image)                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Parent creates child profile online                         │
│  2. Parent downloads Tommy's personalized ISO                   │
│     (or USB installer with image hash)                          │
│  3. OS installs with identity baked in                          │
│  4. First boot = already logged in                              │
│  5. All subsequent boots = already logged in                    │
│                                                                 │
│  Complexity: Lower (simpler client)                             │
│  First-boot: Zero interaction needed                            │
│  Security: Best (token bound to image)                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## What Parent Sees

```
┌─────────────────────────────────────────────────────────────────┐
│  GUARDIAN PARENT PORTAL                                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Add New Device for Tommy                                       │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  Choose installation method:                                    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 📀 Download ISO                                         │   │
│  │    Full installer with Tommy's profile baked in         │   │
│  │    Best for: New PC, clean install                      │   │
│  │                                                         │   │
│  │    [Download ISO (4.2 GB)]                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 💾 USB Installer                                        │   │
│  │    Create bootable USB for Tommy                        │   │
│  │    Best for: Multiple installs                          │   │
│  │                                                         │   │
│  │    [Download USB Creator]                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 🔄 Existing Bazzite/Fedora                              │   │
│  │    Rebase existing install to Guardian OS               │   │
│  │    Best for: Already have Linux installed               │   │
│  │                                                         │   │
│  │    Run this command:                                    │   │
│  │    ┌─────────────────────────────────────────────────┐ │   │
│  │    │ rpm-ostree rebase \                             │ │   │
│  │    │   ghcr.io/guardian-os/images/a1b2c3d4e5f6:v7    │ │   │
│  │    └─────────────────────────────────────────────────┘ │   │
│  │                                            [Copy]       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Summary

| Aspect | Device Binding | Identity-as-Image |
|--------|---------------|-------------------|
| **First boot** | Pairing screen | Already logged in |
| **Token storage** | Encrypted on device | Baked in image |
| **Token refresh** | On device | New deployment |
| **Revocation** | Mark device revoked | Mark image revoked |
| **Multi-device** | Pair each separately | Deploy to each |
| **Updates** | Separate from auth | Same mechanism |
| **Complexity** | More client logic | More build logic |

**Identity-as-Image is cleaner because the deployment system already exists!**
