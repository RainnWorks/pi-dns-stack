{ pkgs, lib, ... }:

{
  imports = [ ./_shared/rpi-base.nix ];

  boot.kernelPackages = pkgs.linuxPackages_rpi02w;
  boot.initrd.availableKernelModules = [ "xhci_pci" "usbhid" "usb_storage" "r8152" ];
  boot.kernelModules = [ "r8152" ];

  hardware.deviceTree = {
    enable = true;
    filter = "*rpi-zero-2*";
  };

  sdImage.populateFirmwareCommands = lib.mkAfter ''
    chmod u+w firmware/config.txt
    cat >> firmware/config.txt <<EOT
    # Free up VRAM for system memory
    start_x=0
    gpu_mem=16
    # Enable USB host mode for Pi Zero 2 W (needed for USB ethernet HATs)
    dtoverlay=dwc2,dr_mode=host
    EOT
  '';
}
