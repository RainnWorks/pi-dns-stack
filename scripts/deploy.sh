#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-}"
IP="${2:-}"
VALID_HOSTS=(dns1 dns2 kitchen-music)
VM_NAME="nixbuilder"
PROJECT_DIR="/mnt/mac$(pwd)"
NIX=". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"

if [[ -z "$HOST" ]]; then
  echo "Usage: $0 <host> [ip]"
  echo "If [ip] is omitted, <host>.local is tried via mDNS."
  echo "Available hosts: ${VALID_HOSTS[*]}"
  exit 1
fi

if [[ ! " ${VALID_HOSTS[*]} " =~ " ${HOST} " ]]; then
  echo "Error: unknown host '$HOST'. Valid: ${VALID_HOSTS[*]}"
  exit 1
fi

[[ -z "$IP" ]] && IP="${HOST}.local"

if ! ping -c 1 -t 3 "$IP" >/dev/null 2>&1; then
  echo "Error: $IP not reachable. Pass IP explicitly: $0 $HOST 192.168.x.y"
  exit 1
fi

echo "▸ Deploying $HOST → $IP"
echo ""

# 1. Build the system closure on the build VM
echo "[1/3] building system closure on $VM_NAME..."
STORE_PATH=$(orb run -m "$VM_NAME" bash -c "
  $NIX
  cd $PROJECT_DIR
  nix build .#nixosConfigurations.${HOST}.config.system.build.toplevel --no-link --print-out-paths 2>&1 | tail -1
")
if [[ ! "$STORE_PATH" =~ ^/nix/store/ ]]; then
  echo "Error: build failed. Run manually to see full output:"
  echo "  orb run -m $VM_NAME bash -c \"$NIX && cd $PROJECT_DIR && nix build .#nixosConfigurations.${HOST}.config.system.build.toplevel\""
  exit 1
fi
echo "  $STORE_PATH"
echo ""

# 2. Copy the closure to the Pi via ssh-ng. Agent-forward through orb so the
#    builder VM can authenticate to the Pi using the laptop's 1Password agent.
#    NIX_SSHOPTS auto-accepts new host keys so a re-flashed Pi doesn't trip
#    StrictHostKeyChecking on the builder side.
echo "[2/3] copying closure to $IP (only changed paths transfer)..."
ssh -A "$VM_NAME@orb" "
  $NIX
  export NIX_SSHOPTS='-o StrictHostKeyChecking=accept-new'
  nix copy --no-check-sigs --to 'ssh-ng://tom@$IP' '$STORE_PATH'
"
echo ""

# 3. Register the closure as a system generation and activate it
echo "[3/3] activating on $IP..."
ssh -o StrictHostKeyChecking=accept-new "tom@$IP" "
  sudo nix-env -p /nix/var/nix/profiles/system --set '$STORE_PATH' && \
  sudo '$STORE_PATH/bin/switch-to-configuration' switch
"

echo ""
echo "▸ Done. New generation active on $HOST."
echo "  (Reboot needed only if kernel/initrd changed — switch-to-configuration"
echo "   will print 'reboot required' if so.)"
