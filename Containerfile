# =============================================================================
# Stage 1: Build Rust binaries
# =============================================================================
FROM rust:1.83-bookworm AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Clone and build guardian-daemon
RUN git clone --depth 1 https://github.com/jonnyweareone/guardian-os-v1.git && \
    cd guardian-os-v1/guardian-components/guardian-daemon && \
    cargo build --release

# Clone and build guardian-launcher
RUN git clone --depth 1 https://github.com/jonnyweareone/guardian-launcher.git && \
    cd guardian-launcher && \
    cargo build --release

# =============================================================================
# Stage 2: Guardian Games OS
# =============================================================================
ARG FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION:-41}"
ARG BAZZITE_TAG="${BAZZITE_TAG:-stable}"
ARG BASE_IMAGE="${BASE_IMAGE:-bazzite}"

FROM ghcr.io/ublue-os/${BASE_IMAGE}:${BAZZITE_TAG}

# Image metadata
ARG IMAGE_NAME="${IMAGE_NAME:-guardian-games}"
ARG IMAGE_VENDOR="${IMAGE_VENDOR:-Guardian Network}"
ARG IMAGE_REF="${IMAGE_REF:-ghcr.io/guardian-network/guardian-games}"
ARG IMAGE_TAG="${IMAGE_TAG:-latest}"
ARG BASE_IMAGE="${BASE_IMAGE:-bazzite}"
ARG FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION:-41}"

LABEL org.opencontainers.image.title="${IMAGE_NAME}"
LABEL org.opencontainers.image.vendor="${IMAGE_VENDOR}"
LABEL org.opencontainers.image.description="Family gaming OS with parental controls, built on Bazzite"
LABEL org.opencontainers.image.source="https://github.com/jonnyweareone/guardian-games-os"
LABEL io.artifacthub.package.readme-url="https://raw.githubusercontent.com/jonnyweareone/guardian-games-os/main/README.md"

# =============================================================================
# Copy pre-built binaries from builder stage
# =============================================================================

# Copy Guardian Daemon binary
COPY --from=builder /build/guardian-os-v1/guardian-components/guardian-daemon/target/release/guardian-daemon /usr/bin/guardian-daemon
RUN chmod 755 /usr/bin/guardian-daemon

# Copy Guardian Games Launcher
COPY --from=builder /build/guardian-launcher/target/release/guardian-launcher /opt/guardian-games/guardian-launcher
RUN mkdir -p /opt/guardian-games && chmod 755 /opt/guardian-games/guardian-launcher

# =============================================================================
# Copy system configuration files
# =============================================================================

COPY system_files/ /

# =============================================================================
# Install dependencies and configure
# =============================================================================

COPY build.sh /tmp/build.sh
RUN chmod +x /tmp/build.sh && /tmp/build.sh

# =============================================================================
# Guardian branding & identity
# =============================================================================

RUN echo '{"image-name":"'"${IMAGE_NAME}"'","image-flavor":"main","image-vendor":"'"${IMAGE_VENDOR}"'","image-ref":"'"${IMAGE_REF}"'","image-tag":"'"${IMAGE_TAG}"'","base-image-name":"'"${BASE_IMAGE}"'","fedora-version":"'"${FEDORA_MAJOR_VERSION}"'"}' > /usr/share/ublue-os/image-info.json

# =============================================================================
# Create identity mount point for per-child images
# =============================================================================

RUN mkdir -p /usr/share/guardian && \
    echo '{"placeholder": true, "note": "identity.json baked during per-child build"}' > /usr/share/guardian/identity.json

# =============================================================================
# Finalize
# =============================================================================

RUN rm -rf /tmp/* /var/tmp/*
RUN ostree container commit
