{ pkgs, ... }:

{
  services.unbound = {
    enable = true;
    # Enable remote-control over a root-only unix socket (no TLS certs needed,
    # unlike the default TCP control interface). Without this `unbound-control`
    # is disabled, so every unbound-control call below — the cache dump/load
    # timers and the /flush HTTP endpoint — silently no-ops. unbound-control's
    # default `-c /etc/unbound/unbound.conf` picks this socket up automatically.
    localControlSocketPath = "/run/unbound/unbound.ctl";
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
    path = with pkgs; [ unbound coreutils ];
    # Write to a temp file and only promote it on success. A bare
    # `dump_cache > cache.dump` truncates the target to 0 bytes *before*
    # running unbound-control, so any failure leaves an empty file behind —
    # and load_cache then hangs forever on that empty file (this took dns1
    # down once). Atomic-move means cache.dump is always either a complete
    # dump or absent, never a truncated trap.
    script = ''
      if unbound-control dump_cache > /var/lib/unbound/cache.dump.tmp 2>/dev/null; then
        mv -f /var/lib/unbound/cache.dump.tmp /var/lib/unbound/cache.dump
      else
        rm -f /var/lib/unbound/cache.dump.tmp
      fi
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
    serviceConfig = {
      Type = "oneshot";
      # Hard ceiling: this unit gates multi-user.target and system activation,
      # so it must never be able to hang them. systemd SIGKILLs it after 30s.
      TimeoutStartSec = "30s";
    };
    path = with pkgs; [ unbound coreutils ];
    # `-s` = exists AND non-empty, so an empty/corrupt dump is skipped rather
    # than fed to load_cache (which blocks waiting for data that never comes).
    # `timeout` is a second belt-and-braces guard against a malformed but
    # non-empty dump.
    script = ''
      if [ -s /var/lib/unbound/cache.dump ]; then
        timeout 20 unbound-control load_cache < /var/lib/unbound/cache.dump 2>/dev/null || true
      fi
    '';
  };
}
