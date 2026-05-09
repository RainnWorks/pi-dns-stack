{
  imports = [
    ../modules/hardware/pi-zero2w.nix
    ../modules/dns/stack.nix
  ];

  networking.hostName = "dns1";

  networking.useDHCP = true;
}
