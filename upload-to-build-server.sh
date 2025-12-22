#!/bin/bash
# Upload Guardian Games OS source to build server
# Usage: ./upload-to-build-server.sh

SERVER="136.244.71.108"
USER="root"
PASS='sW9{f2@dYiy?{x7S'
REMOTE_DIR="/root/guardian-build"

# Files to upload
LOCAL_BASE="/Users/davidsmith/Documents/GitHub"

echo "Uploading Guardian Games OS to build server..."

# Use rsync with sshpass
sshpass -p "${PASS}" rsync -avz --progress \
    "${LOCAL_BASE}/guardian-games-os/" \
    "${USER}@${SERVER}:${REMOTE_DIR}/guardian-games-os/"

sshpass -p "${PASS}" rsync -avz --progress \
    "${LOCAL_BASE}/guardian-os-v1/guardian-components/guardian-daemon/" \
    "${USER}@${SERVER}:${REMOTE_DIR}/guardian-os-v1/guardian-components/guardian-daemon/"

echo ""
echo "Upload complete. Now SSH in and run:"
echo "  ssh root@${SERVER}"
echo "  cd ${REMOTE_DIR}/guardian-games-os"
echo "  ./remote-build.sh"
