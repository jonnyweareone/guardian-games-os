#!/bin/bash
# =============================================================================
# Guardian Games OS v2 - Local Test Build
# =============================================================================
#
# This script builds a test version of the container image locally.
# It uses a Linux container to cross-compile the Rust daemon.
#
# Requirements:
#   - Docker or Podman
#
# Usage:
#   ./test-build.sh
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
BUILD_DIR="${PROJECT_ROOT}/build"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${BLUE}[BUILD]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Detect container runtime
if command -v podman &> /dev/null; then
    CONTAINER_CMD="podman"
elif command -v docker &> /dev/null; then
    CONTAINER_CMD="docker"
else
    echo "Error: Neither podman nor docker found"
    exit 1
fi

log "Using container runtime: ${CONTAINER_CMD}"

# Clean build directory
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/binaries"

# =============================================================================
# Step 1: Build daemon in Linux container
# =============================================================================

log "Building guardian-daemon in Linux container..."

DAEMON_SRC="${PROJECT_ROOT}/../guardian-os-v1/guardian-components/guardian-daemon"

if [ ! -d "${DAEMON_SRC}" ]; then
    warn "Daemon source not found at ${DAEMON_SRC}"
    warn "Creating placeholder binary..."
    echo '#!/bin/bash' > "${BUILD_DIR}/binaries/guardian-daemon"
    echo 'echo "Guardian Daemon placeholder"' >> "${BUILD_DIR}/binaries/guardian-daemon"
    chmod +x "${BUILD_DIR}/binaries/guardian-daemon"
else
    # Build in Rust container
    ${CONTAINER_CMD} run --rm \
        -v "${DAEMON_SRC}:/src:Z" \
        -v "${BUILD_DIR}/binaries:/out:Z" \
        -w /src \
        docker.io/rust:latest \
        bash -c "
            cargo build --release && \
            cp target/release/guardian-daemon /out/ && \
            chmod +x /out/guardian-daemon
        "
    success "Daemon built successfully"
fi

# =============================================================================
# Step 2: Create guardian-selector placeholder
# =============================================================================

log "Creating guardian-selector..."

cat > "${BUILD_DIR}/binaries/guardian-selector" << 'EOF'
#!/bin/bash
# Guardian Selector - placeholder for test builds
# Production version will be a Rust/GTK application

echo "╔══════════════════════════════════════════════════════════╗"
echo "║           🎮 GUARDIAN GAMES - WHO'S PLAYING?             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "This is a test build - selector UI not implemented yet"
echo ""

# For testing, just start GDM normally
exit 0
EOF
chmod +x "${BUILD_DIR}/binaries/guardian-selector"

# =============================================================================
# Step 3: Create launcher placeholder
# =============================================================================

log "Creating launcher placeholder..."

LAUNCHER_SRC="${PROJECT_ROOT}/../guardian-games-launcher"

if [ -d "${LAUNCHER_SRC}" ] && [ -f "${LAUNCHER_SRC}/package.json" ]; then
    log "Found launcher source, but skipping Electron build for test"
fi

mkdir -p "${BUILD_DIR}/binaries/guardian-games-launcher"
cat > "${BUILD_DIR}/binaries/guardian-games-launcher/guardian-games-launcher" << 'EOF'
#!/bin/bash
echo "Guardian Games Launcher - placeholder"
echo "Production version is an Electron app"
EOF
chmod +x "${BUILD_DIR}/binaries/guardian-games-launcher/guardian-games-launcher"

# =============================================================================
# Step 4: Copy system files
# =============================================================================

log "Copying system files..."

if [ -d "${PROJECT_ROOT}/system_files_v2" ]; then
    cp -r "${PROJECT_ROOT}/system_files_v2"/* "${BUILD_DIR}/"
    success "System files copied"
else
    warn "system_files_v2 not found, creating minimal structure..."
    mkdir -p "${BUILD_DIR}/etc/guardian"
    mkdir -p "${BUILD_DIR}/usr/lib/systemd/system"
    mkdir -p "${BUILD_DIR}/usr/lib/systemd/user"
    mkdir -p "${BUILD_DIR}/usr/share/polkit-1/rules.d"
    mkdir -p "${BUILD_DIR}/usr/share/glib-2.0/schemas"
    mkdir -p "${BUILD_DIR}/usr/share/applications"
fi

# =============================================================================
# Step 5: Copy Containerfile
# =============================================================================

log "Preparing Containerfile..."

cp "${PROJECT_ROOT}/Containerfile.v2" "${BUILD_DIR}/Containerfile"

# =============================================================================
# Step 6: Build container image
# =============================================================================

log "Building container image..."

cd "${BUILD_DIR}"

${CONTAINER_CMD} build \
    --build-arg FEDORA_VERSION=41 \
    --build-arg IMAGE_NAME=guardian-games \
    --build-arg IMAGE_VERSION=test \
    -t guardian-games:test \
    -f Containerfile \
    .

success "Container image built: guardian-games:test"

# =============================================================================
# Step 7: Show summary
# =============================================================================

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              BUILD COMPLETE                              ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║                                                          ║"
echo "║  Image: guardian-games:test                              ║"
echo "║                                                          ║"
echo "║  To inspect:                                             ║"
echo "║    ${CONTAINER_CMD} inspect guardian-games:test                    ║"
echo "║                                                          ║"
echo "║  To run shell:                                           ║"
echo "║    ${CONTAINER_CMD} run -it --rm guardian-games:test bash          ║"
echo "║                                                          ║"
echo "║  To rebase a Silverblue VM:                              ║"
echo "║    rpm-ostree rebase ostree-unverified-image:            ║"
echo "║      docker://guardian-games:test                        ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
