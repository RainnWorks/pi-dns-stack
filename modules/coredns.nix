{ pkgs, cfg, ... }:

{
  environment.etc."coredns/Corefile".text = ''
    ${cfg.domain}:53 {
        template IN A {
            match ^(.*)\.${cfg.domain}\.$
            answer "{{ .Name }} 60 IN A ${cfg.localIP}"
        }
        errors
        cache 60
    }

    .:53 {
        forward . 127.0.0.1:5353
        cache 300
        errors
    }
  '';

  services.coredns = {
    enable = true;
  };

  systemd.services.coredns = {
    after = [ "adguardhome.service" ];
    wants = [ "adguardhome.service" ];
  };

  systemd.services.coredns.serviceConfig = {
    ExecStart = [
      ""
      "${pkgs.coredns}/bin/coredns -conf /etc/coredns/Corefile"
    ];
    MemoryMax = "64M";
  };
}
