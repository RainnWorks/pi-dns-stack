{ lib, ... }:

{
  services.shairport-sync = {
    enable = true;
    openFirewall = true;
    # `-o alsa -- -d default` routes through /etc/asound.conf, which
    # hifiberry-amp4.nix already points at the HiFiBerry. The AirPlay
    # display name is set per-host (defaults to system hostname here).
    arguments = lib.mkDefault ''-o alsa -- -d default'';
  };
}
