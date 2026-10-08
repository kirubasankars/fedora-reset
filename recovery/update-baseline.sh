#!/usr/bin/env bash
set -euo pipefail

# Configuration
PRIMARY_LABEL="PRIMARY_ROOT"
RECOVERY_LABEL="RECOVER_DATA"
RECOVERY_MNT="/mnt/recovery_data"

IMG_FILE="$RECOVERY_MNT/primary_clean.img"
BMAP_FILE="$RECOVERY_MNT/primary_clean.bmap"

echo "=== Updating Primary OS Recovery Baseline ==="

# 1. Root check
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

# 2. Clear any lingering trigger file before taking the baseline
if [ -f /reset_me ]; then
    echo "[!] Removing existing /reset_me trigger file..."
    rm -f /reset_me
fi

# 3. Ensure filesystem caches are flushed to disk
echo "[1/4] Flushing filesystem buffers to disk..."
sync

# 4. Mount recovery volume
echo "[2/4] Mounting recovery volume..."
mkdir -p "$RECOVERY_MNT"
if ! mountpoint -q "$RECOVERY_MNT"; then
    RECOVERY_DEV=$(blkid -L "$RECOVERY_LABEL")
    if [ -z "$RECOVERY_DEV" ]; then
        echo "ERROR: Could not locate volume labeled '$RECOVERY_LABEL'."
        exit 1
    fi
    mount "$RECOVERY_DEV" "$RECOVERY_MNT"
fi

PRIMARY_DEV=$(blkid -L "$PRIMARY_LABEL")
if [ -z "$PRIMARY_DEV" ]; then
    echo "ERROR: Could not locate volume labeled '$PRIMARY_LABEL'."
    exit 1
fi

# 5. Capture sparse image
echo "[3/4] Creating sparse raw image ($IMG_FILE)..."
# Freeze so the image and its XFS log are a consistent snapshot. A copy of a
# mounted filesystem replays into metadata corruption on the next boot.
unfreeze() { xfs_freeze -u / || true; }
trap unfreeze EXIT
xfs_freeze -f /
dd if="$PRIMARY_DEV" of="$IMG_FILE" bs=4M iflag=direct conv=sparse status=none </dev/null >/dev/null 2>&1
xfs_freeze -u /
sync
trap - EXIT

# 6. Generate updated bmap file
echo "[4/4] Generating new block map file ($BMAP_FILE)..."
bmaptool create "$IMG_FILE" -o "$BMAP_FILE"
sync

echo ""
echo "=== Baseline Successfully Updated! ==="
echo "Image Size: $(du -sh "$IMG_FILE" | cut -f1)"
echo "Bmap File:  $BMAP_FILE"
