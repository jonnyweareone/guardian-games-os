#!/bin/bash
# Guardian Games OS - Build Script
# This runs inside the container during image build

set -euo pipefail

echo "=============================================="
echo "  Building Guardian Games OS"
echo "=============================================="

# =============================================================================
# Install Guardian packages
# =============================================================================

echo ">>> Installing Guardian dependencies..."

# Core dependencies for our daemons
rpm-ostree install \
    libnotify \
    python3-dbus \
    python3-gobject \
    python3-requests \
    || echo "Some packages may already be installed"

# TODO: Once we have COPR packages, install them:
# dnf copr enable guardian-network/guardian-games -y
# rpm-ostree install \
#     guardian-syncd \
#     guardian-games \
#     guardian-portal \
#     screen-time-enforcer

# =============================================================================
# Enable Guardian services
# =============================================================================

echo ">>> Enabling Guardian services..."

# User services (will start on login)
mkdir -p /usr/lib/systemd/user/default.target.wants

# Guardian sync daemon
if [ -f /usr/lib/systemd/user/guardian-syncd.service ]; then
    ln -sf /usr/lib/systemd/user/guardian-syncd.service \
           /usr/lib/systemd/user/default.target.wants/guardian-syncd.service
    echo "    - guardian-syncd.service enabled"
fi

# Screen time enforcer
if [ -f /usr/lib/systemd/user/screen-time-enforcer.service ]; then
    ln -sf /usr/lib/systemd/user/screen-time-enforcer.service \
           /usr/lib/systemd/user/default.target.wants/screen-time-enforcer.service
    echo "    - screen-time-enforcer.service enabled"
fi

# =============================================================================
# Configure polkit for parental controls
# =============================================================================

echo ">>> Configuring polkit rules..."

if [ -f /usr/share/polkit-1/rules.d/50-guardian-parental.rules ]; then
    chmod 644 /usr/share/polkit-1/rules.d/50-guardian-parental.rules
    echo "    - Parental control polkit rules installed"
fi

# =============================================================================
# Set up Guardian Portal (first-boot wizard)
# =============================================================================

echo ">>> Configuring first-boot setup..."

# Guardian Portal should run on first login
# Using similar mechanism to yafti
mkdir -p /usr/share/guardian/firstboot

# =============================================================================
# Configure default settings
# =============================================================================

echo ">>> Setting Guardian defaults..."

# Create default config directory
mkdir -p /etc/guardian

# Ensure proper permissions
chmod 755 /etc/guardian

# =============================================================================
# Desktop integration
# =============================================================================

echo ">>> Installing desktop entries..."

# Ensure .desktop files are in place
if [ -f /usr/share/applications/guardian-games.desktop ]; then
    chmod 644 /usr/share/applications/guardian-games.desktop
    echo "    - Guardian Games launcher installed"
fi

# =============================================================================
# Cleanup
# =============================================================================

echo ">>> Cleaning up..."

rpm-ostree cleanup -m
rm -rf /tmp/* /var/tmp/* || true

echo "=============================================="
echo "  Guardian Games OS build complete!"
echo "=============================================="
