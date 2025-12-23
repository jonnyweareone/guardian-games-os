#!/bin/bash
# =============================================================================
# Guardian Games OS - Container Build Script
# =============================================================================
# 
# This script runs inside the container build to install packages
# and configure the system. Rust binaries are already built in stage 1.
#
# =============================================================================

set -euo pipefail

echo "=== Guardian Games OS Build Script ==="

# Install parental control packages
echo "Installing malcontent parental controls..."
rpm-ostree install \
    malcontent \
    malcontent-control \
    || echo "Malcontent may already be installed"

# Create Guardian directories
echo "Creating Guardian directories..."
mkdir -p /var/lib/guardian
mkdir -p /etc/guardian
mkdir -p /usr/share/guardian

# Set up systemd service for guardian-daemon
echo "Configuring guardian-daemon service..."
cat > /etc/systemd/system/guardian-daemon.service << 'EOF'
[Unit]
Description=Guardian Daemon - Family Safety Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/guardian-daemon
Restart=always
RestartSec=5
User=root
Environment=RUST_LOG=info

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
systemctl enable guardian-daemon.service || true

# Create desktop entry for launcher
echo "Creating desktop entry..."
mkdir -p /usr/share/applications
cat > /usr/share/applications/guardian-launcher.desktop << 'EOF'
[Desktop Entry]
Name=Guardian Games
Comment=Family-safe game launcher
Exec=/usr/bin/guardian-launcher
Icon=applications-games
Terminal=false
Type=Application
Categories=Game;
StartupWMClass=guardian-launcher
EOF

# Create autostart for child sessions
mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/guardian-launcher.desktop << 'EOF'
[Desktop Entry]
Name=Guardian Games
Comment=Family-safe game launcher
Exec=/usr/bin/guardian-launcher
Icon=applications-games
Terminal=false
Type=Application
X-GNOME-Autostart-enabled=true
EOF

echo "=== Build script complete ==="
