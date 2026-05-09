{ pkgs, ... }:

{
  services.unbound = {
    enable = true;
    settings = {
      server = {
        interface = [ "127.0.0.1" ];
        port = 5335;

        do-ip4 = true;
        do-ip6 = false;
        do-udp = true;
        do-tcp = true;

        num-threads = 1;

        qname-minimisation = true;
        harden-glue = true;
        harden-dnssec-stripped = true;
        hide-identity = true;
        hide-version = true;
        use-caps-for-id = false;

        prefetch = true;
        prefetch-key = true;

        msg-cache-size = "2m";
        rrset-cache-size = "4m";
        key-cache-size = "512k";
        neg-cache-size = "128k";
        infra-cache-numhosts = 256;

        outgoing-range = 64;
        num-queries-per-thread = 32;

        verbosity = 1;
      };
    };
  };

  systemd.services.unbound = {
    after = [ "systemd-time-wait-sync.service" ];
    wants = [ "systemd-time-wait-sync.service" ];
    serviceConfig.MemoryMax = "128M";
  };

  # Dump cache to SD card every 30 minutes
  systemd.services.unbound-cache-dump = {
    description = "Dump Unbound cache to disk";
    after = [ "unbound.service" ];
    serviceConfig.Type = "oneshot";
    path = with pkgs; [ unbound ];
    script = ''
      unbound-control dump_cache > /var/lib/unbound/cache.dump 2>/dev/null || true
    '';
  };

  systemd.timers.unbound-cache-dump = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "2h";
    };
  };

  # Reload cache on start
  systemd.services.unbound-cache-load = {
    description = "Load Unbound cache from disk";
    after = [ "unbound.service" ];
    wants = [ "unbound.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    path = with pkgs; [ unbound ];
    script = ''
      if [ -f /var/lib/unbound/cache.dump ]; then
        unbound-control load_cache < /var/lib/unbound/cache.dump 2>/dev/null || true
      fi
    '';
  };
}
