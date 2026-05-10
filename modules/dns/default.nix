{ ... }:

{
  imports = [
    ./unbound.nix
    ./adguardhome.nix
    ./coredns.nix
  ];

  # Resolve own queries via local CoreDNS so the Pi itself sees the same
  # ad-blocking + local-domain template as everyone else on the LAN.
  networking.nameservers = [ "127.0.0.1" ];

  # Open DNS + AdGuard UI + CoreDNS metrics ports. Combined with base.nix's
  # [22] and observability.nix's [9100] this becomes [22 53 3000 9100 9153].
  networking.firewall = {
    allowedTCPPorts = [ 53 3000 9153 ];
    allowedUDPPorts = [ 53 ];
  };

  # Expose health of the trio via Prometheus node_exporter's systemd
  # collector (see modules/observability.nix). Audio services are
  # deliberately left out — HA has better-suited integrations (Spotify,
  # AirPlay) for the playback-state side of things.
  observability.monitoredServices = [ "coredns" "adguardhome" "unbound" ];
}
