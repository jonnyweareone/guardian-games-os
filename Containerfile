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
# Install Guardian packages
# =============================================================================

# Copy build scripts
COPY build.sh /tmp/build.sh
RUN chmod +x /tmp/build.sh

# Copy system configuration files
COPY system_files/ /

# Run the build script
RUN /tmp/build.sh

# =============================================================================
# Guardian branding
# =============================================================================

# Set default wallpaper (if exists)
# COPY branding/wallpaper.png /usr/share/backgrounds/guardian-default.png
# RUN ln -sf /usr/share/backgrounds/guardian-default.png /usr/share/backgrounds/default.png

# =============================================================================
# Image info for ublue-update compatibility
# =============================================================================

RUN echo '{"image-name":"'"${IMAGE_NAME}"'","image-flavor":"main","image-vendor":"'"${IMAGE_VENDOR}"'","image-ref":"'"${IMAGE_REF}"'","image-tag":"'"${IMAGE_TAG}"'","base-image-name":"'"${BASE_IMAGE}"'","fedora-version":"'"${FEDORA_MAJOR_VERSION}"'"}' > /usr/share/ublue-os/image-info.json

# =============================================================================
# Finalize
# =============================================================================

# Clean up
RUN rm -rf /tmp/* /var/tmp/*

# Commit the ostree container
RUN ostree container commit
