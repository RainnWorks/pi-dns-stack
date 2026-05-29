{ config, pkgs, cfg, ... }:

{
  environment.etc."coredns/Corefile".text = ''
${cfg.domain}:53 {
    # Wildcard A: *.${cfg.domain} resolves to the homelab server, so local
    # services keep resolving even when the internet is down. fallthrough
    # lets every *other* query type (SOA, TXT, MX, NS, AAAA) drop to the
    # forward below instead of SERVFAILing — without it CoreDNS shadows the
    # whole public zone and breaks Let's Encrypt DNS-01 (SOA + _acme-challenge
    # TXT lookups) and email record lookups on the LAN.
    template IN A {
        match ^(.*)\.${cfg.domain}\.$
        answer "{{ .Name }} 60 IN A ${cfg.localIP}"
        fallthrough
    }
    forward . 127.0.0.1:5353
    errors
    cache 60
}

.:53 {
    forward . 127.0.0.1:5353
    cache 300
    errors
    prometheus :9153
}
  '';

  services.coredns = {
    enable = true;
  };

  systemd.services.coredns = {
    after = [ "adguardhome.service" ];
    wants = [ "adguardhome.service" ];
    # Force a restart when the Corefile changes (NixOS otherwise only
    # restarts services whose unit definitions change, not their external
    # config files).
    restartTriggers = [ config.environment.etc."coredns/Corefile".source ];
  };

  systemd.services.coredns.serviceConfig = {
    ExecStart = [
      ""
      "${pkgs.coredns}/bin/coredns -conf /etc/coredns/Corefile"
    ];
    MemoryMax = "64M";
  };
}
