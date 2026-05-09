{
  imports = [
    ../modules/hardware/pi4.nix
    ../modules/hardware/hifiberry-amp4.nix
    ../modules/dns
    ../modules/audio/spotify-connect.nix
    ../modules/audio/airplay.nix
    ../modules/observability.nix
  ];

  networking.hostName = "kitchen-music";

  networking.useDHCP = true;

  # How this device appears in Spotify Connect / AirPlay device pickers.
  services.spotifyd.settings.global.device_name = "Kitchen";
  services.shairport-sync.arguments = ''-a "Kitchen" -o alsa -- -d default'';
}
