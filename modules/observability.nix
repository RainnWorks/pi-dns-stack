{ config, lib, ... }:

# Prometheus node exporter on :9100 — CPU, RAM, disk, network, rpi
# thermal_zone, and per-systemd-unit state. HA's Prometheus integration
# scrapes this directly; no MQTT broker needed.
#
# By default the systemd collector exposes every unit (hundreds — too
# noisy). Other modules add the units they care about via
# `observability.monitoredServices`:
#
#   # in modules/dns/stack.nix
#   observability.monitoredServices = [ "coredns" "adguardhome" "unbound" ];
#
# The lists merge across imports, so a host's filter is the union of
# every imported module's claims.

let
  inherit (lib) mkOption types concatStringsSep;
  cfg = config.observability;
in
{
  options.observability.monitoredServices = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = ''
      systemd unit names to expose state metrics for. Each name is matched
      as <name>.service via the node_exporter systemd collector filter.
    '';
  };

  config = {
    services.prometheus.exporters.node = {
      enable = true;
      port = 9100;
      enabledCollectors = [
        "systemd"          # per-unit active/failed state
        "processes"        # process counts
        "pressure"         # PSI metrics
        "thermal_zone"     # rpi SoC temperature
      ];
      extraFlags = lib.optionals (cfg.monitoredServices != [ ]) [
        "--collector.systemd.unit-include=^(${concatStringsSep "|" cfg.monitoredServices})\\.service$"
      ];
    };

    networking.firewall.allowedTCPPorts = [ 9100 ];
  };
}
