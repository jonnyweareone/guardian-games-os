# Guardian Games OS - Development Commands
# Usage: just <command>

# Default image name
image_name := "guardian-games"
registry := "ghcr.io/guardian-network"

# Default recipe
default:
    @just --list

# Build the container image locally
build variant="main":
    #!/bin/bash
    set -euo pipefail
    
    case "{{variant}}" in
        main)       BASE="bazzite" ;;
        nvidia)     BASE="bazzite-nvidia" ;;
        gnome)      BASE="bazzite-gnome" ;;
        deck)       BASE="bazzite-deck" ;;
        *)          echo "Unknown variant: {{variant}}"; exit 1 ;;
    esac
    
    echo "Building {{image_name}}:{{variant}} from $BASE..."
    
    podman build \
        --build-arg BASE_IMAGE=$BASE \
        --build-arg BAZZITE_TAG=stable \
        --build-arg IMAGE_NAME={{image_name}}-{{variant}} \
        -t localhost/{{image_name}}:{{variant}} \
        .

# Build all variants
build-all:
    just build main
    just build nvidia
    just build deck

# Run a shell in the built image
shell variant="main":
    podman run --rm -it localhost/{{image_name}}:{{variant}} /bin/bash

# Push to registry (requires login)
push variant="main":
    podman push localhost/{{image_name}}:{{variant}} {{registry}}/{{image_name}}:{{variant}}

# Clean up local images
clean:
    podman rmi localhost/{{image_name}}:main || true
    podman rmi localhost/{{image_name}}:nvidia || true
    podman rmi localhost/{{image_name}}:deck || true

# Generate signing keys (run once, save cosign.key securely)
generate-keys:
    #!/bin/bash
    if [ -f cosign.key ]; then
        echo "Keys already exist! Remove them first if you want new ones."
        exit 1
    fi
    cosign generate-key-pair
    echo ""
    echo "IMPORTANT:"
    echo "1. Add cosign.pub to your repo"
    echo "2. Add cosign.key contents to GitHub Secrets as SIGNING_SECRET"
    echo "3. DO NOT commit cosign.key!"

# Lint Containerfile
lint:
    hadolint Containerfile || echo "Install hadolint for linting"

# Check for upstream Bazzite updates
check-upstream:
    #!/bin/bash
    echo "Latest Bazzite tags:"
    skopeo list-tags docker://ghcr.io/ublue-os/bazzite 2>/dev/null | jq -r '.Tags[-5:][]' || \
        echo "Install skopeo to check upstream"

# Test rebase locally (use with caution!)
test-rebase variant="main":
    #!/bin/bash
    echo "This will rebase your system to the local image!"
    echo "Only run this on a test machine!"
    read -p "Are you sure? (type YES): " confirm
    if [ "$confirm" = "YES" ]; then
        sudo bootc switch localhost/{{image_name}}:{{variant}}
    else
        echo "Aborted."
    fi
