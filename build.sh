#!/bin/bash
# =============================================================================
# Guardian Games OS v2 - Build Script
# =============================================================================
# 
# This script builds all components and creates the OCI container image.
#
# Usage:
#   ./build.sh              # Build everything
#   ./build.sh daemon       # Build daemon only
#   ./build.sh launcher     # Build launcher only  
#   ./build.sh image        # Build container image only
#   ./build.sh test         # Build and run local test
#
# Requirements:
#   - Rust toolchain (rustup)
#   - Node.js 18+ and npm/yarn
#   - Podman or Docker
#   - rpm-ostree (for testing)
#
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
DAEMON_DIR="${PROJECT_ROOT}/../guardian-os-v1/guardian-components/guardian-daemon"
LAUNCHER_DIR="${PROJECT_ROOT}/../guardian-games-launcher"
OUTPUT_DIR="${PROJECT_ROOT}/build/binaries"
SYSTEM_FILES="${PROJECT_ROOT}/system_files_v2"

# Image settings
IMAGE_NAME="${IMAGE_NAME:-guardian-games}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FEDORA_VERSION="${FEDORA_VERSION:-41}"
REGISTRY="${REGISTRY:-ghcr.io/guardian-network}"

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is required but not installed."
        exit 1
    fi
}

# =============================================================================
# Build Functions
# =============================================================================

build_daemon() {
    log_info "Building guardian-daemon..."
    
    if [ ! -d "${DAEMON_DIR}" ]; then
        log_error "Daemon source not found at ${DAEMON_DIR}"
        exit 1
    fi
    
    cd "${DAEMON_DIR}"
    
    # Build for release
    cargo build --release
    
    # Copy binary to output
    mkdir -p "${OUTPUT_DIR}"
    cp target/release/guardian-daemon "${OUTPUT_DIR}/"
    
    log_success "guardian-daemon built: ${OUTPUT_DIR}/guardian-daemon"
}

build_selector() {
    log_info "Building guardian-selector..."
    
    # For now, guardian-selector is a shell script wrapper
    # In production, this would be a Rust/GTK app
    
    mkdir -p "${OUTPUT_DIR}"
    
    cat > "${OUTPUT_DIR}/guardian-selector" << 'EOF'
#!/bin/bash
# Guardian Selector - Child profile picker at boot
# This is a placeholder - production version would be GTK/Electron UI

GUARDIAN_DATA="/var/lib/guardian"
PROFILES_DIR="${GUARDIAN_DATA}/profiles"

# Check if any profiles exist
if [ ! -d "${PROFILES_DIR}" ] || [ -z "$(ls -A ${PROFILES_DIR})" ]; then
    echo "No child profiles found. Please activate this device."
    exit 1
fi

# List available profiles
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           🎮 GUARDIAN GAMES - WHO'S PLAYING?             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

PROFILES=()
i=1
for profile in "${PROFILES_DIR}"/*.json; do
    if [ -f "${profile}" ]; then
        name=$(jq -r '.name // "Unknown"' "${profile}")
        PROFILES+=("${profile}")
        echo "  ${i}) ${name}"
        ((i++))
    fi
done

echo ""
read -p "Select profile (1-${#PROFILES[@]}): " selection

if [ -z "${selection}" ] || [ "${selection}" -lt 1 ] || [ "${selection}" -gt "${#PROFILES[@]}" ]; then
    echo "Invalid selection"
    exit 1
fi

# Get selected profile
SELECTED_PROFILE="${PROFILES[$((selection-1))]}"
CHILD_ID=$(jq -r '.child_id' "${SELECTED_PROFILE}")
CHILD_USER=$(jq -r '.linux_user // "guardian-child"' "${SELECTED_PROFILE}")

echo ""
echo "Starting session for: $(jq -r '.name' "${SELECTED_PROFILE}")"

# Configure autologin for this session
mkdir -p /etc/gdm
cat > /etc/gdm/custom.conf << EOL
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=${CHILD_USER}

[security]
AllowRoot=false
EOL

# Signal GDM to start
systemctl start gdm

exit 0
EOF

    chmod +x "${OUTPUT_DIR}/guardian-selector"
    log_success "guardian-selector built: ${OUTPUT_DIR}/guardian-selector"
}

build_launcher() {
    log_info "Building guardian-games-launcher..."
    
    if [ ! -d "${LAUNCHER_DIR}" ]; then
        log_warn "Launcher source not found at ${LAUNCHER_DIR}"
        log_warn "Creating placeholder..."
        mkdir -p "${OUTPUT_DIR}/guardian-games-launcher"
        echo "Placeholder - build launcher from ${LAUNCHER_DIR}" > "${OUTPUT_DIR}/guardian-games-launcher/README.txt"
        return
    fi
    
    cd "${LAUNCHER_DIR}"
    
    # Install dependencies
    if [ -f "package-lock.json" ]; then
        npm ci
    else
        npm install
    fi
    
    # Build Electron app
    npm run build
    
    # Package for Linux
    npm run package:linux || npm run dist:linux || {
        log_warn "Electron packaging failed, copying source instead"
        mkdir -p "${OUTPUT_DIR}/guardian-games-launcher"
        cp -r dist/* "${OUTPUT_DIR}/guardian-games-launcher/" 2>/dev/null || \
        cp -r build/* "${OUTPUT_DIR}/guardian-games-launcher/" 2>/dev/null || \
        cp -r ./* "${OUTPUT_DIR}/guardian-games-launcher/"
    }
    
    log_success "guardian-games-launcher built"
}

build_image() {
    log_info "Building container image: ${IMAGE_NAME}:${IMAGE_TAG}"
    
    # Check for required files
    if [ ! -f "${PROJECT_ROOT}/Containerfile.v2" ]; then
        log_error "Containerfile.v2 not found"
        exit 1
    fi
    
    if [ ! -d "${OUTPUT_DIR}" ]; then
        log_error "Binaries not built. Run './build.sh daemon' first"
        exit 1
    fi
    
    # Create build context structure
    BUILD_CONTEXT="${PROJECT_ROOT}/build/context"
    rm -rf "${BUILD_CONTEXT}"
    mkdir -p "${BUILD_CONTEXT}"
    
    # Copy Containerfile
    cp "${PROJECT_ROOT}/Containerfile.v2" "${BUILD_CONTEXT}/Containerfile"
    
    # Copy binaries
    mkdir -p "${BUILD_CONTEXT}/binaries"
    cp -r "${OUTPUT_DIR}"/* "${BUILD_CONTEXT}/binaries/"
    
    # Copy system files
    if [ -d "${SYSTEM_FILES}" ]; then
        cp -r "${SYSTEM_FILES}"/* "${BUILD_CONTEXT}/"
    else
        log_warn "System files not found at ${SYSTEM_FILES}"
    fi
    
    # Build with podman (preferred) or docker
    if command -v podman &> /dev/null; then
        log_info "Building with Podman..."
        podman build \
            --build-arg FEDORA_VERSION="${FEDORA_VERSION}" \
            --build-arg IMAGE_NAME="${IMAGE_NAME}" \
            --build-arg IMAGE_VERSION="${IMAGE_TAG}" \
            -t "${IMAGE_NAME}:${IMAGE_TAG}" \
            -f "${BUILD_CONTEXT}/Containerfile" \
            "${BUILD_CONTEXT}"
    elif command -v docker &> /dev/null; then
        log_info "Building with Docker..."
        docker build \
            --build-arg FEDORA_VERSION="${FEDORA_VERSION}" \
            --build-arg IMAGE_NAME="${IMAGE_NAME}" \
            --build-arg IMAGE_VERSION="${IMAGE_TAG}" \
            -t "${IMAGE_NAME}:${IMAGE_TAG}" \
            -f "${BUILD_CONTEXT}/Containerfile" \
            "${BUILD_CONTEXT}"
    else
        log_error "Neither podman nor docker found"
        exit 1
    fi
    
    log_success "Container image built: ${IMAGE_NAME}:${IMAGE_TAG}"
}

push_image() {
    log_info "Pushing image to ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    
    if command -v podman &> /dev/null; then
        podman tag "${IMAGE_NAME}:${IMAGE_TAG}" "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        podman push "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    else
        docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        docker push "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    fi
    
    log_success "Image pushed to ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
}

run_tests() {
    log_info "Running tests..."
    
    # Test daemon compilation
    cd "${DAEMON_DIR}"
    cargo test
    
    log_success "All tests passed"
}

clean() {
    log_info "Cleaning build artifacts..."
    
    rm -rf "${PROJECT_ROOT}/build"
    
    if [ -d "${DAEMON_DIR}" ]; then
        cd "${DAEMON_DIR}"
        cargo clean 2>/dev/null || true
    fi
    
    if [ -d "${LAUNCHER_DIR}" ]; then
        cd "${LAUNCHER_DIR}"
        rm -rf node_modules dist build 2>/dev/null || true
    fi
    
    log_success "Clean complete"
}

show_help() {
    echo ""
    echo "Guardian Games OS v2 - Build Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  all       Build everything (default)"
    echo "  daemon    Build guardian-daemon (Rust)"
    echo "  selector  Build guardian-selector"
    echo "  launcher  Build guardian-games-launcher (Electron)"
    echo "  image     Build OCI container image"
    echo "  push      Push image to registry"
    echo "  test      Run tests"
    echo "  clean     Clean build artifacts"
    echo "  help      Show this help"
    echo ""
    echo "Environment variables:"
    echo "  IMAGE_NAME      Image name (default: guardian-games)"
    echo "  IMAGE_TAG       Image tag (default: latest)"
    echo "  FEDORA_VERSION  Fedora version (default: 41)"
    echo "  REGISTRY        Container registry (default: ghcr.io/guardian-network)"
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    local cmd="${1:-all}"
    
    case "${cmd}" in
        all)
            check_dependency cargo
            check_dependency npm
            
            build_daemon
            build_selector
            build_launcher
            build_image
            ;;
        daemon)
            check_dependency cargo
            build_daemon
            ;;
        selector)
            build_selector
            ;;
        launcher)
            check_dependency npm
            build_launcher
            ;;
        image)
            build_image
            ;;
        push)
            push_image
            ;;
        test)
            check_dependency cargo
            run_tests
            ;;
        clean)
            clean
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: ${cmd}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
