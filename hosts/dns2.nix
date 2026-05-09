{
  imports = [
    ../modules/hardware/pi-zero2w.nix
    ../modules/dns
    ../modules/observability.nix
  ];

  networking.hostName = "dns2";

  networking.useDHCP = true;
}
