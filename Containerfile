ARG FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION:-41}"
ARG BAZZITE_TAG="${BAZZITE_TAG:-stable}"
ARG BASE_IMAGE="${BASE_IMAGE:-bazzite}"

# =============================================================================
# Guardian Games OS
# Built FROM Bazzite - inherits all gaming features
# Adds: Parental controls, profile sync, family management
# =============================================================================

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
LABEL org.opencontainers.image.source="https://github.com/guardian-network/guardian-games-os"
LABEL io.artifacthub.package.readme-url="https://raw.githubusercontent.com/guardian-network/guardian-games-os/main/README.md"

# =============================================================================
# Copy pre-built binaries (from CI artifacts mounted at /tmp)
# =============================================================================

# Copy Guardian Daemon binary
COPY --from=build-context /guardian-daemon /usr/bin/guardian-daemon
RUN chmod 755 /usr/bin/guardian-daemon || true

# Copy Guardian Games Launcher
COPY --from=build-context /guardian-games-launcher /opt/guardian-games/
RUN chmod 755 /opt/guardian-games/guardian-games-launcher || true

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
