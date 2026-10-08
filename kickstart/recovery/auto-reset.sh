#!/usr/bin/env bash
set -euo pipefail

# Configuration: Update partition labels / paths if needed
PRIMARY_LABEL="PRIMARY_ROOT"
RECOVERY_LABEL="RECOVER_DATA"
RECOVERY_MNT="/mnt/recovery_data"
MODULE_DIR="/usr/lib/dracut/modules.d/99auto-reset"

echo "=== Starting Auto-Reset Framework Setup ==="

# 1. Install prerequisites
echo "[1/5] Installing dependencies (bmap-tools, python3)..."
if command -v dnf &>/dev/null; then
    dnf install -y bmap-tools python3 dracut
elif command -v apt-get &>/dev/null; then
    apt-get update && apt-get install -y bmap-tools python3 dracut
else
    echo "Unsupported package manager. Please install bmap-tools manually."
    exit 1
fi

# 2. Verify partition labels
echo "[2/5] Validating storage labels..."
PRIMARY_DEV=$(blkid -L "$PRIMARY_LABEL" || true)
RECOVERY_DEV=$(blkid -L "$RECOVERY_LABEL" || true)

if [ -z "$PRIMARY_DEV" ] || [ -z "$RECOVERY_DEV" ]; then
    echo "ERROR: Could not locate volumes by label."
    echo "  Primary ($PRIMARY_LABEL): ${PRIMARY_DEV:-NOT FOUND}"
    echo "  Recovery ($RECOVERY_LABEL): ${RECOVERY_DEV:-NOT FOUND}"
    echo "Ensure partitions are labeled with e2label/fatlabel/xfs_admin or edit script variables."
    exit 1
fi

# 3. Mount recovery volume and generate initial base image & bmap
echo "[3/5] Capturing pristine recovery image and bmap file..."
mkdir -p "$RECOVERY_MNT"
if ! mountpoint -q "$RECOVERY_MNT"; then
    mount "$RECOVERY_DEV" "$RECOVERY_MNT"
fi

IMG_FILE="$RECOVERY_MNT/primary_clean.img"
BMAP_FILE="$RECOVERY_MNT/primary_clean.bmap"

# Dump primary partition as sparse image. Freeze first so the XFS log matches
# the metadata; restoring a live copy otherwise corrupts the volume.
unfreeze() { xfs_freeze -u / || true; }
trap unfreeze EXIT
xfs_freeze -f /
dd if="$PRIMARY_DEV" of="$IMG_FILE" bs=4M iflag=direct conv=sparse status=none </dev/null >/dev/null 2>&1
xfs_freeze -u /
sync
trap - EXIT

# Generate bmap map file
bmaptool create "$IMG_FILE" -o "$BMAP_FILE"
sync

echo "Clean image captured successfully at $IMG_FILE"

# 4. Create Dracut module
echo "[4/5] Constructing Dracut hook module..."
mkdir -p "$MODULE_DIR"

# Write module-setup.sh
cat <<'EOF' > "$MODULE_DIR/module-setup.sh"
#!/bin/bash

check() {
    return 0
}

depends() {
    echo "base"
    return 0
}

install() {
    # Include required binaries into initramfs
    inst_multiple bmaptool python3 mount umount reboot blkid mkdir lvm udevadm blkdiscard dd

    # bmaptool is a Python program. The stdlib, including encodings, has to be
    # in the initramfs or it exits before copying anything. inst_dir only
    # creates the directory, so copy the files themselves.
    stdlib=$(python3 -c 'import sysconfig; print(sysconfig.get_path("stdlib"))')
    pkg=$(python3 -c 'import bmaptool, os; print(os.path.dirname(bmaptool.__file__))')
    while IFS= read -r file; do
        inst "$file"
    done < <(find "$stdlib" "$pkg" \( -type f -o -type l \))

    # Register hook to run prior to root filesystem mount.
    # $moddir is the 99auto-reset directory where this module's auto-reset.sh lives.
    inst_hook pre-mount 99 "$moddir/auto-reset.sh"
    # udev does not always activate the root LV before the initqueue times out.
    inst_hook initqueue/settled 90 "$moddir/lvm-settle.sh"
}
EOF
chmod +x "$MODULE_DIR/module-setup.sh"

cat <<'EOF' > "$MODULE_DIR/lvm-settle.sh"
#!/bin/sh
# Activate the volume group before dracut gives up waiting for the root LV.
lvm vgchange -ay --sysinit
udevadm settle
EOF
chmod +x "$MODULE_DIR/lvm-settle.sh"

# Write auto-reset.sh hook script
cat <<EOF > "$MODULE_DIR/auto-reset.sh"
#!/bin/sh
# Early boot hook: Restores primary OS if reset trigger exists

PRIMARY_DEV="/dev/disk/by-label/$PRIMARY_LABEL"
RECOVERY_DEV="/dev/disk/by-label/$RECOVERY_LABEL"
MNT_PRIMARY="/sysroot_check"
MNT_RECOVERY="/recovery_check"

mkdir -p "\$MNT_PRIMARY" "\$MNT_RECOVERY"

# Mount primary partition read-only to check for trigger. Do not use
# norecovery: the superblock can outlive this mount and /sysroot would then
# inherit it, which makes remounting / read-write fail.
if mount -o ro "\$PRIMARY_DEV" "\$MNT_PRIMARY" 2>/dev/null; then
    if [ -f "\$MNT_PRIMARY/reset_me" ]; then
        echo "===================================================="
        echo "RESET TRIGGER DETECTED: Restoring Primary OS Volume..."
        echo "===================================================="

        umount "\$MNT_PRIMARY"

        # Root and swap are activated from the kernel command line. Recovery is not.
        if [ ! -e "\$RECOVERY_DEV" ]; then
            lvm vgchange -ay
            udevadm settle
        fi

        # Mount recovery volume to read image and bmap
        if mount -o ro "\$RECOVERY_DEV" "\$MNT_RECOVERY"; then
            echo "Applying clean image via bmaptool..."

            if bmaptool copy \\
              --bmap "\$MNT_RECOVERY/primary_clean.bmap" \\
              "\$MNT_RECOVERY/primary_clean.img" \\
              "\$PRIMARY_DEV"
            then
                # bmaptool leaves unmapped blocks untouched, so files created
                # after the baseline would survive. Discard those ranges.
                bmap="\$MNT_RECOVERY/primary_clean.bmap"
                block_size=\$(sed -n 's/.*<BlockSize> *\\([0-9]*\\).*/\\1/p' "\$bmap")
                blocks=\$(sed -n 's/.*<BlocksCount> *\\([0-9]*\\).*/\\1/p' "\$bmap")
                prev=0
                sed -n 's/.*<Range[^>]*> *\\([0-9]*-[0-9]*\\).*/\\1/p' "\$bmap" | while read -r range; do
                    start=\${range%-*}
                    end=\${range#*-}
                    if [ "\$start" -gt "\$prev" ]; then
                        offset=\$((prev * block_size))
                        length=\$(((start - prev) * block_size))
                        blkdiscard -o "\$offset" -l "\$length" "\$PRIMARY_DEV" \\
                            || dd if=/dev/zero of="\$PRIMARY_DEV" bs="\$block_size" seek="\$prev" count=\$((start - prev)) status=none
                    fi
                    prev=\$((end + 1))
                    echo "\$prev" > /tmp/bmap-prev
                done
                prev=\$(cat /tmp/bmap-prev 2>/dev/null || echo 0)
                if [ "\$prev" -lt "\$blocks" ]; then
                    offset=\$((prev * block_size))
                    length=\$(((blocks - prev) * block_size))
                    blkdiscard -o "\$offset" -l "\$length" "\$PRIMARY_DEV" \\
                        || dd if=/dev/zero of="\$PRIMARY_DEV" bs="\$block_size" seek="\$prev" count=\$((blocks - prev)) status=none
                fi
                rm -f /tmp/bmap-prev
            else
                echo "ERROR: bmaptool copy failed; leaving the volume unchanged."
                umount "\$MNT_RECOVERY"
                sleep 10
                exit 0
            fi

            umount "\$MNT_RECOVERY"

            echo "Restoration complete! Rebooting..."
            sleep 2
            reboot -f
        else
            echo "ERROR: Failed to mount recovery data volume!"
            sleep 10
        fi
    else
        umount "\$MNT_PRIMARY"
    fi
fi
EOF
chmod +x "$MODULE_DIR/auto-reset.sh"

# 5. Rebuild initramfs
echo "[5/5] Rebuilding initramfs image..."
# Keep the module in initramfs images that kernel updates regenerate.
echo 'add_dracutmodules+=" auto-reset "' > /etc/dracut.conf.d/90-auto-reset.conf
# In kickstart %post, uname -r is the installer kernel, so build every
# installed kernel explicitly.
for kdir in /lib/modules/*/; do
    kver=$(basename "$kdir")
    [ -e "/boot/vmlinuz-$kver" ] || continue
    dracut --force --hostonly --kver "$kver"
done

echo "=== Setup Complete ==="
echo "To test the reset sequence run:"
echo "  sudo touch /reset_me && sudo reboot"
