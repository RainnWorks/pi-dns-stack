# pi-dns-stack

Network-wide ad blocking and local DNS for the home network, running on Raspberry Pi Zero 2 W devices with NixOS.

## Making it yours

Copy the example config and fill in your details:

```sh
cp config.example.nix config.local.nix
git add -N config.local.nix
```

Edit `config.local.nix` with your local domain, IP, SSH key, and timezone. This file is gitignored but must be registered with `git add -N` for Nix flakes to see it (the content is never committed).

You may also want to edit:

| File | What to change |
|------|---------------|
| `modules/adguardhome.nix` | Filter lists and whitelist rules |
| `hosts/dns1.nix`, `hosts/dns2.nix` | Hostnames for your nodes |
| `flake.nix` | Add or remove nodes |

Everything else should work out of the box on a Pi Zero 2 W with a Waveshare PoE/ETH/USB HAT.

## Why

The homelab runs on a single server with services behind local domains. AdGuard Home on Home Assistant handled DNS and ad blocking — until the internet went down. Without a connection, AdGuard couldn't resolve local domains either, taking the entire homelab offline. Home Assistant, dashboards, cameras — all gone because DNS died.

The fix: dedicated DNS hardware that keeps local resolution working regardless of internet status. CoreDNS handles local domains independently, so they always resolve even when the upstream connection is down. Ad blocking and recursive DNS are separate layers that degrade gracefully.

Raspberry Pi Zero 2 Ws are cheap (~$15), and paired with the Waveshare PoE/ETH/USB HAT, each node gets power and ethernet from a single cable — no power supplies, no WiFi dependencies. NixOS makes the whole stack declarative and reproducible: one `make build && make flash` and a fresh node is ready.

## How it works

Every DNS query on the network flows through three layers:

```mermaid
graph LR
    D[Devices on network] -->|port 53| C[CoreDNS]
    C -->|local domain| L[Local IP]
    C -->|everything else| A[AdGuard Home]
    A -->|blocked| B[0.0.0.0]
    A -->|allowed| U[Unbound]
    U -->|recursive lookup| R[Root DNS servers]
```

**CoreDNS** handles incoming queries. Local domains get routed to the homelab server. Everything else goes to AdGuard Home.

**AdGuard Home** filters queries against blocklists covering ads, tracking, smart TV telemetry, and annoyances. Blocked domains return `0.0.0.0`. Clean queries pass through to Unbound.

**Unbound** is a recursive resolver — it talks directly to root DNS servers instead of forwarding to Google/Cloudflare. This means DNS lookups never leave your control.

## Boot sequence

The Pi Zero 2 W has no real-time clock, so the boot order matters:

```mermaid
graph TD
    T[NTP sync via IP] -->|clock correct| W[time-wait-sync]
    W --> U[Unbound starts]
    U --> A[AdGuard Home starts]
    A --> C[CoreDNS starts]
    A --> F[Filter lists download]
```

NTP servers are configured by IP address to avoid a chicken-and-egg problem — you need DNS to resolve NTP hostnames, but you need correct time for DNSSEC validation.

## Hardware

- **Raspberry Pi Zero 2 W** (512MB RAM, quad-core ARM)
- **Waveshare PoE/ETH/USB HUB HAT** for ethernet + power-over-ethernet
- Runs entirely from an SD card with tmpfs for logs (no SD card wear)

## Project structure

```
flake.nix              # Nix flake defining dns1 and dns2 nodes
config.example.nix     # Example config (copy to config.nix)
hosts/
  dns1.nix             # Per-host config (hostname, DHCP)
  dns2.nix
modules/
  dns-node.nix         # Base system (networking, SSH, NTP, users)
  hardware.nix         # Pi Zero 2 W kernel, device tree, firmware
  unbound.nix          # Recursive DNS resolver (port 5335)
  adguardhome.nix      # Ad blocking + filter lists (port 5353)
  coredns.nix          # Frontend DNS + local domains (port 53)
scripts/
  setup.sh             # Create OrbStack build VM + install Nix
  build.sh             # Build SD card image
  flash.sh             # Flash image to SD card (with safety checks)
  test.sh              # Run health checks against a node
Makefile               # Convenience wrapper
```

## Usage

### First time setup

```sh
cp config.example.nix config.nix  # edit with your details
make setup                        # create OrbStack build VM
```

### Build and flash

```sh
make build HOST=dns1
make flash HOST=dns1
```

Insert the SD card, power on the Pi, and it should appear on the network within a minute or two.

### Test a node

```sh
make test IP=192.168.x.x
```

### SSH access

```sh
ssh <user>@<ip>
```

Password auth is disabled — SSH key only.

## Memory budget

With 512MB RAM and `gpu_mem=16`, roughly 450MB is available:

| Service     | Limit  |
|-------------|--------|
| Unbound     | 128 MB |
| AdGuard Home| 128 MB |
| CoreDNS     |  64 MB |
| OS + system | ~130 MB|

All services restart automatically if they crash.
