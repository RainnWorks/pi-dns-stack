{ pkgs, ... }:

{
  imports = [ ./_shared/rpi-base.nix ];

  boot.kernelPackages = pkgs.linuxPackages_rpi4;
  boot.initrd.availableKernelModules = [ "xhci_pci" "usbhid" "usb_storage" ];

  hardware.deviceTree = {
    enable = true;
    filter = "*rpi-4*";
  };
}
