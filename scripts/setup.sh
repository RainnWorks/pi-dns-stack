#!/usr/bin/env bash
set -euo pipefail

VM_NAME="nixbuilder"

if orb list -q | grep -q "^${VM_NAME}$"; then
  echo "OrbStack VM '$VM_NAME' already exists, skipping creation."
else
  echo "Creating OrbStack VM '$VM_NAME'..."
  orb create ubuntu "$VM_NAME"
fi

echo "Installing dependencies..."
orb run -m "$VM_NAME" -u root bash -c "
  apt-get update -qq
  apt-get install -y -qq xz-utils
"

if orb run -m "$VM_NAME" bash -c "test -d /nix"; then
  echo "Nix already installed, skipping."
else
  echo "Installing Nix..."
  orb run -m "$VM_NAME" bash -c "curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes"
fi

echo "Configuring Nix..."
orb run -m "$VM_NAME" -u root bash -c "
  grep -q 'experimental-features' /etc/nix/nix.conf 2>/dev/null || echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf
  systemctl restart nix-daemon
"

echo "Verifying..."
orb run -m "$VM_NAME" bash -c ". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && nix --version"

echo "Done. You can now run ./build.sh <host>"
