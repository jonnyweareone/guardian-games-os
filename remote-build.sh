#!/bin/bash
# =============================================================================
# Guardian Games OS v2 - Remote Build Script
# =============================================================================
# Run this on the build server (136.244.71.108)
#
# Setup:
#   1. Clone repos or copy source files
#   2. Run this script
#
# =============================================================================

set -euo pipefail

BUILD_DIR="/root/guardian-build"
DAEMON_DIR="${BUILD_DIR}/guardian-daemon"
OUTPUT_DIR="${BUILD_DIR}/output"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[BUILD]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# =============================================================================
# Setup
# =============================================================================

log "Setting up build environment..."

mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}"
cd "${BUILD_DIR}"

# Install dependencies if needed
if ! command -v cargo &> /dev/null; then
    log "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

if ! command -v podman &> /dev/null && ! command -v docker &> /dev/null; then
    log "Installing Podman..."
    if command -v dnf &> /dev/null; then
        dnf install -y podman
    elif command -v apt &> /dev/null; then
        apt update && apt install -y podman
    fi
fi

# Detect container runtime
if command -v podman &> /dev/null; then
    CONTAINER_CMD="podman"
else
    CONTAINER_CMD="docker"
fi

log "Using: cargo $(cargo --version 2>/dev/null || echo 'not found'), ${CONTAINER_CMD}"

# =============================================================================
# Clone/Update Source
# =============================================================================

log "Getting source code..."

# Guardian OS v1 (contains daemon)
if [ -d "guardian-os-v1" ]; then
    cd guardian-os-v1 && git pull && cd ..
else
    git clone https://github.com/guardian-network/guardian-os-v1.git 2>/dev/null || \
    log "Note: Using local daemon source if available"
fi

# Guardian Games OS (container definition)
if [ -d "guardian-games-os" ]; then
    cd guardian-games-os && git pull && cd ..
else
    git clone https://github.com/guardian-network/guardian-games-os.git 2>/dev/null || \
    log "Note: Using local container source if available"
fi

# =============================================================================
# Build Daemon
# =============================================================================

log "Building guardian-daemon..."

DAEMON_SRC="${BUILD_DIR}/guardian-os-v1/guardian-components/guardian-daemon"

if [ -d "${DAEMON_SRC}" ]; then
    cd "${DAEMON_SRC}"
    cargo build --release
    cp target/release/guardian-daemon "${OUTPUT_DIR}/"
    chmod +x "${OUTPUT_DIR}/guardian-daemon"
    success "Daemon built: ${OUTPUT_DIR}/guardian-daemon"
else
    error "Daemon source not found at ${DAEMON_SRC}"
fi

# =============================================================================
# Build Launcher (Rust/iced)
# =============================================================================

log "Building guardian-launcher..."

LAUNCHER_SRC="${BUILD_DIR}/guardian-launcher"

if [ -d "${LAUNCHER_SRC}" ]; then
    cd "${LAUNCHER_SRC}"
    cargo build --release
    cp target/release/guardian-launcher "${OUTPUT_DIR}/"
    chmod +x "${OUTPUT_DIR}/guardian-launcher"
    success "Launcher built: ${OUTPUT_DIR}/guardian-launcher"
else
    warn "Launcher source not found at ${LAUNCHER_SRC}"
    warn "Creating placeholder..."
    cat > "${OUTPUT_DIR}/guardian-launcher" << 'LAUNCHER_EOF'
#!/bin/bash
echo "Guardian Launcher - placeholder (Rust build required)"
LAUNCHER_EOF
    chmod +x "${OUTPUT_DIR}/guardian-launcher"
fi

# =============================================================================
# Create Guardian Selector (placeholder)
# =============================================================================

log "Creating guardian-selector..."

cat > "${OUTPUT_DIR}/guardian-selector" << 'SELECTOR_EOF'
#!/bin/bash
# Guardian Selector - Child profile picker at boot
# This is a placeholder - production version would be GTK/Electron UI

GUARDIAN_DATA="/var/lib/guardian"
PROFILES_DIR="${GUARDIAN_DATA}/profiles"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           🎮 GUARDIAN GAMES - WHO'S PLAYING?             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check if any profiles exist
if [ ! -d "${PROFILES_DIR}" ] || [ -z "$(ls -A ${PROFILES_DIR} 2>/dev/null)" ]; then
    echo "No child profiles found. Starting normal session..."
    exit 0
fi

# List available profiles
PROFILES=()
i=1
for profile in "${PROFILES_DIR}"/*.json; do
    if [ -f "${profile}" ]; then
        name=$(jq -r '.name // "Unknown"' "${profile}" 2>/dev/null || basename "${profile}" .json)
        PROFILES+=("${profile}")
        echo "  ${i}) ${name}"
        ((i++))
    fi
done

if [ ${#PROFILES[@]} -eq 0 ]; then
    echo "No profiles found. Starting normal session..."
    exit 0
fi

echo ""
read -t 30 -p "Select profile (1-${#PROFILES[@]}, or wait 30s for default): " selection || selection=1

if [ -z "${selection}" ] || [ "${selection}" -lt 1 ] || [ "${selection}" -gt "${#PROFILES[@]}" ]; then
    selection=1
fi

SELECTED_PROFILE="${PROFILES[$((selection-1))]}"
CHILD_USER=$(jq -r '.linux_user // "guardian-child"' "${SELECTED_PROFILE}" 2>/dev/null || echo "guardian-child")

echo ""
echo "Starting session..."

# Signal completion
exit 0
SELECTOR_EOF

chmod +x "${OUTPUT_DIR}/guardian-selector"
success "Selector created"

# =============================================================================
# Create Launcher Placeholder
# =============================================================================

log "Creating launcher placeholder..."

mkdir -p "${OUTPUT_DIR}/guardian-games-launcher"
cat > "${OUTPUT_DIR}/guardian-games-launcher/guardian-games-launcher" << 'LAUNCHER_EOF'
#!/bin/bash
# Guardian Games Launcher - Placeholder
# Production version is Electron app from guardian-games-launcher repo

echo "Guardian Games Launcher"
echo "======================="
echo ""
echo "This is a placeholder. The full launcher provides:"
echo "  - Game library with age filtering"
echo "  - Friends, parties, chat (via Nakama)"
echo "  - Session tracking and time limits"
echo "  - Parent approval workflow"
echo ""
echo "Build the Electron app from guardian-games-launcher for full functionality."
LAUNCHER_EOF

chmod +x "${OUTPUT_DIR}/guardian-games-launcher/guardian-games-launcher"
success "Launcher placeholder created"

# =============================================================================
# Prepare Container Build Context
# =============================================================================

log "Preparing container build context..."

CONTAINER_SRC="${BUILD_DIR}/guardian-games-os"
CONTEXT_DIR="${BUILD_DIR}/container-context"

rm -rf "${CONTEXT_DIR}"
mkdir -p "${CONTEXT_DIR}/binaries/guardian-games-launcher"

# Copy binaries
cp "${OUTPUT_DIR}/guardian-daemon" "${CONTEXT_DIR}/binaries/"
cp "${OUTPUT_DIR}/guardian-selector" "${CONTEXT_DIR}/binaries/"
cp -r "${OUTPUT_DIR}/guardian-games-launcher"/* "${CONTEXT_DIR}/binaries/guardian-games-launcher/"

# Copy system files
if [ -d "${CONTAINER_SRC}/system_files_v2" ]; then
    cp -r "${CONTAINER_SRC}/system_files_v2"/* "${CONTEXT_DIR}/"
    success "System files copied from repo"
else
    log "Creating minimal system files..."
    mkdir -p "${CONTEXT_DIR}/etc/guardian"
    mkdir -p "${CONTEXT_DIR}/usr/lib/systemd/system"
    mkdir -p "${CONTEXT_DIR}/usr/lib/systemd/user"
    mkdir -p "${CONTEXT_DIR}/usr/share/polkit-1/rules.d"
    mkdir -p "${CONTEXT_DIR}/usr/share/glib-2.0/schemas"
    mkdir -p "${CONTEXT_DIR}/usr/share/applications"
    
    # Create minimal config
    cat > "${CONTEXT_DIR}/etc/guardian/config.json" << 'CONFIG_EOF'
{
  "version": "2.0",
  "supabase_url": "https://gkyspvcafyttfhyjryyk.supabase.co",
  "supabase_anon_key": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdreXNwdmNhZnl0dGZoeWpyeXlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjYxMDIzMzQsImV4cCI6MjA4MTY3ODMzNH0.Ns5N9Y9uZgWqdhnYiX5IrubOO-Xopl2urBDR1AVD7FI",
  "features": {
    "malcontent_integration": true,
    "game_library_scan": true
  }
}
CONFIG_EOF
fi

# Copy Containerfile
if [ -f "${CONTAINER_SRC}/Containerfile.v2" ]; then
    cp "${CONTAINER_SRC}/Containerfile.v2" "${CONTEXT_DIR}/Containerfile"
else
    error "Containerfile.v2 not found!"
fi

success "Container context prepared at ${CONTEXT_DIR}"

# =============================================================================
# Build Container Image
# =============================================================================

log "Building container image..."

cd "${CONTEXT_DIR}"

${CONTAINER_CMD} build \
    --build-arg FEDORA_VERSION=41 \
    --build-arg IMAGE_NAME=guardian-games \
    --build-arg IMAGE_VERSION=2.0.0-test \
    -t guardian-games:latest \
    -t guardian-games:2.0.0-test \
    -f Containerfile \
    .

success "Container image built!"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                    BUILD COMPLETE                                ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║                                                                  ║"
echo "║  Binaries:                                                       ║"
echo "║    ${OUTPUT_DIR}/guardian-daemon                                 ║"
echo "║    ${OUTPUT_DIR}/guardian-selector                               ║"
echo "║                                                                  ║"
echo "║  Container Image:                                                ║"
echo "║    guardian-games:latest                                         ║"
echo "║    guardian-games:2.0.0-test                                     ║"
echo "║                                                                  ║"
echo "║  To test in a Silverblue VM:                                     ║"
echo "║    rpm-ostree rebase ostree-unverified-image:                    ║"
echo "║      docker://localhost/guardian-games:latest                    ║"
echo "║                                                                  ║"
echo "║  To push to registry:                                            ║"
echo "║    ${CONTAINER_CMD} push guardian-games:latest ghcr.io/guardian-network/guardian-games:latest ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
