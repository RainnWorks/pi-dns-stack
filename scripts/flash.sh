#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-}"
VALID_HOSTS=(dns1 dns2 kitchen-music)
OUTPUT_DIR="$(pwd)/out"

if [[ -z "$HOST" ]]; then
  echo "Usage: ./flash.sh <host>"
  echo "Available hosts: ${VALID_HOSTS[*]}"
  exit 1
fi

if [[ ! " ${VALID_HOSTS[*]} " =~ " ${HOST} " ]]; then
  echo "Error: unknown host '$HOST'"
  echo "Available hosts: ${VALID_HOSTS[*]}"
  exit 1
fi

IMAGE="$OUTPUT_DIR/${HOST}.img.zst"
if [[ ! -f "$IMAGE" ]]; then
  echo "Error: no image for $HOST at $IMAGE"
  echo "Run 'make build HOST=$HOST' first."
  exit 1
fi

echo "Image: $IMAGE"
echo ""

# Find the boot disk so we can exclude it
BOOT_DISK=$(diskutil info / | grep "Part of Whole" | awk '{print $NF}')

# List only safe candidate disks
echo "Available disks (excluding system disks):"
echo "---"
for disk in $(diskutil list | grep "^/dev/disk" | awk '{print $1}' | sed 's|/dev/||'); do
  # Skip boot disk
  [[ "$disk" == "$BOOT_DISK" ]] && continue
  # Skip any disk containing Apple/APFS/synthesized/disk image partitions
  disk_listing=$(diskutil list "$disk" 2>/dev/null)
  echo "$disk_listing" | grep -qi "Apple\|APFS\|synthesized\|disk image" && continue
  echo "$disk_listing"
  echo ""
done
echo "---"
echo ""

read -rp "Enter disk to flash (e.g. disk4): " DISK

if [[ -z "$DISK" ]]; then
  echo "No disk specified, aborting."
  exit 1
fi

# Normalise — strip /dev/ prefix if provided
DISK="${DISK#/dev/}"

if [[ ! -e "/dev/$DISK" ]]; then
  echo "Error: /dev/$DISK does not exist"
  exit 1
fi

# Safety: refuse to flash any system-related disk
if [[ "$DISK" == "$BOOT_DISK" ]]; then
  echo "Error: /dev/$DISK is the boot disk. Aborting."
  exit 1
fi

DISK_INFO=$(diskutil info "/dev/$DISK" 2>/dev/null)
if echo "$DISK_INFO" | grep -qi "APFS"; then
  echo "Error: /dev/$DISK is an APFS volume (system disk). Aborting."
  exit 1
fi

if echo "$DISK_INFO" | grep -qi "Apple"; then
  echo "Error: /dev/$DISK is an Apple volume. Aborting."
  exit 1
fi

if echo "$DISK_INFO" | grep -qi "synthesized\|disk image"; then
  echo "Error: /dev/$DISK is a virtual disk. Aborting."
  exit 1
fi

SIZE=$(diskutil info "/dev/$DISK" | grep "Disk Size" | sed 's/.*: *//')
NAME=$(diskutil list "/dev/$DISK" | grep "^ " | head -1 | awk '{for(i=2;i<NF-2;i++) printf $i" "; print ""}' | xargs)
echo ""
echo "WARNING: This will erase ALL data on /dev/$DISK"
echo "  Size: $SIZE"
echo "  Name: $NAME"
read -rp "Type 'yes' to continue: " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

echo "Decompressing image..."
RAW_IMAGE="$OUTPUT_DIR/nixos-${HOST}.img"
zstd -d "$IMAGE" -o "$RAW_IMAGE" -f

echo "Unmounting /dev/$DISK..."
diskutil unmountDisk force "/dev/$DISK"

echo "Flashing to /dev/r${DISK} (this may take a while)..."
sudo dd if="$RAW_IMAGE" of="/dev/r${DISK}" bs=4m status=progress

echo "Ejecting..."
diskutil eject "/dev/$DISK"

echo "Cleaning up..."
rm "$RAW_IMAGE"

echo "Done. SD card is ready for $HOST."
