#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-}"
VALID_HOSTS=(dns1 dns2)
PROJECT_DIR="/mnt/mac$(pwd)"
OUTPUT_DIR="$(pwd)/out"

if [[ -z "$HOST" ]]; then
  echo "Usage: ./build.sh <host>"
  echo "Available hosts: ${VALID_HOSTS[*]}"
  exit 1
fi

if [[ ! " ${VALID_HOSTS[*]} " =~ " ${HOST} " ]]; then
  echo "Error: unknown host '$HOST'"
  echo "Available hosts: ${VALID_HOSTS[*]}"
  exit 1
fi

echo "Building SD image for $HOST..."

# orb run merges stdout/stderr, so we grab the store path from the last line
STORE_PATH=$(orb run -m nixbuilder bash -c "
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  cd $PROJECT_DIR
  nix build .#nixosConfigurations.${HOST}.config.system.build.sdImage --no-link --print-out-paths 2>&1 | tail -1
")

if [[ ! "$STORE_PATH" =~ ^/nix/store/ ]]; then
  echo "Error: build failed. Run manually to see full output:"
  echo "  orb run -m nixbuilder bash -c \". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && cd $PROJECT_DIR && nix build .#nixosConfigurations.${HOST}.config.system.build.sdImage\""
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
echo "Copying image to $OUTPUT_DIR..."
orb run -m nixbuilder bash -c "cp ${STORE_PATH}/sd-image/*.img.zst $PROJECT_DIR/out/"

echo "Done:"
ls -lh "$OUTPUT_DIR"/*.img.zst
