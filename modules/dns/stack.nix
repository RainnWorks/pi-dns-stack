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

  # Open DNS + AdGuard UI ports. Combined with base.nix's [22] this becomes
  # [22 53 3000] via NixOS list-merge.
  networking.firewall = {
    allowedTCPPorts = [ 53 3000 ];
    allowedUDPPorts = [ 53 ];
  };
}
