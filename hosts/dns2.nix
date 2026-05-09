{
  imports = [
    ../modules/hardware/pi-zero2w.nix
    ../modules/dns/stack.nix
  ];

  networking.hostName = "dns2";

  networking.useDHCP = true;
}
