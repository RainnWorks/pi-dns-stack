{
  imports = [
    ../modules/hardware/pi-zero2w.nix
    ../modules/dns
    ../modules/observability.nix
  ];

  networking.hostName = "dns1";

  networking.useDHCP = true;
}
