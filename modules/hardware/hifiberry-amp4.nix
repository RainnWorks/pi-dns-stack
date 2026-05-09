{ config, pkgs, lib, ... }:

let
  rpiKernel = config.boot.kernelPackages.kernel;

  # NixOS's hardware.deviceTree.overlays uses an apply_overlays.py that skips
  # overlays whose `compatible` string doesn't intersect the base DTB's. The
  # hifiberry overlay declares `brcm,bcm2835` (the rpi convention for "any
  # rpi SoC"), but the Pi 4 DTB is `brcm,bcm2711`, so the check incorrectly
  # rejects it. Bypass the check by pre-merging the DTB ourselves and feeding
  # it via dtbSource.
  #
  # Note: hifiberry-dacplus-std covers the DAC+ Standard, Amp2, and Amp4
  # family (kernel >= 6.1.77). For the Amp4 Pro use hifiberry-amp4pro instead.
  mergedDtbs = pkgs.runCommandNoCC "rpi-dtbs-with-hifiberry-amp4" {
    nativeBuildInputs = [ pkgs.dtc ];
  } ''
    mkdir -p $out
    cp -r ${rpiKernel}/dtbs/* $out/
    chmod -R u+w $out
    fdtoverlay \
      -i $out/broadcom/bcm2711-rpi-4-b.dtb \
      -o $out/broadcom/bcm2711-rpi-4-b.dtb.merged \
      ${rpiKernel}/dtbs/overlays/hifiberry-dacplus-std.dtbo
    mv $out/broadcom/bcm2711-rpi-4-b.dtb.merged $out/broadcom/bcm2711-rpi-4-b.dtb
  '';
in
{
  hardware.deviceTree.dtbSource = mergedDtbs;

  # NixOS's modules-shrunk derivation strips kernel modules that aren't
  # explicitly referenced. Listing the HiFiBerry stack here ensures the
  # BCM I2S driver, the dacplus machine driver, and the PCM512x codec
  # driver survive into the deployed kernel-modules tree.
  boot.kernelModules = [
    "snd_soc_bcm2835_i2s"
    "snd_soc_hifiberry_dacplus"
    "snd_soc_pcm512x_i2c"
  ];

  # Default ALSA to the HiFiBerry by card name so it's stable across boots
  # (numeric card IDs depend on probe order — onboard audio still ends up
  # as card0, USB audio as card2, etc.). Music Assistant's builtin player
  # opens the default ALSA device.
  environment.etc."asound.conf".text = ''
    pcm.!default {
      type plug
      slave.pcm "hw:sndrpihifiberry,0"
    }
    ctl.!default {
      type hw
      card "sndrpihifiberry"
    }
  '';

  # Let interactive logins (e.g. `aplay`, `speaker-test`) reach /dev/snd.
  users.users.tom.extraGroups = [ "audio" ];

  # Audio-stack settings specific to this HAT. Plain (non-mkDefault) values
  # override audio module mkDefault fallbacks; hosts can still override
  # these via lib.mkForce if needed.
  #
  # PCM5121 has a hardware Digital mixer with 207 steps and 0.5dB resolution
  # — better SNR than software volume, and saves a tiny bit of CPU. Linear
  # scaling is also gentler on the Amp4 (logarithmic ALSA mapping plus a
  # 30W amp = ear-blast on the bottom 5% of the slider).
  services.spotifyd.settings.global = {
    volume_controller = "alsa_linear";
    mixer = "hw:CARD=sndrpihifiberry";
    control = "Digital";
  };
}
