{ lib, pkgs, ... }:

let
  # One-shot handler run per TCP connection by systemd socket activation.
  # stdin/stdout are wired straight to the socket, so we speak just enough
  # HTTP/1.1 by hand. There is no auth: instead, anything that isn't the one
  # exact request we accept — `GET /flush` or `GET /flush?d=<domain>` — gets
  # zero bytes and a closed connection (bare `exit 0`), so a probe sees an
  # empty reply and the port reads as dead. Only a perfect request ever
  # produces a response.
  handler = pkgs.writeShellScript "dns-flush-handler" ''
    set -eu
    export PATH=${lib.makeBinPath (with pkgs; [ unbound systemd coreutils ])}

    # Request line: "METHOD /target HTTP/1.1". No line at all → drop.
    read -r method target _proto || exit 0
    target=''${target%$'\r'}

    # This is only a server for exactly one shape of request. Anything else
    # falls straight through to `exit 0` with nothing written.
    [ "$method" = GET ] || exit 0

    path=''${target%%\?*}
    [ "$path" = /flush ] || exit 0

    query=""
    case "$target" in *\?*) query=''${target#*\?} ;; esac

    # Query must be empty (flush everything) or exactly `d=<domain>` — a single
    # param, clean hostname characters only. Anything else: drop.
    dom=""
    if [ -n "$query" ]; then
      case "$query" in d=*) dom=''${query#d=} ;; *) exit 0 ;; esac
      case "$dom" in ""|*[!a-zA-Z0-9.-]*) exit 0 ;; esac
    fi

    # Perfect request — drain the rest of the headers so the client's write
    # completes, then do the work.
    while IFS= read -r line; do
      line=''${line%$'\r'}
      [ -z "$line" ] && break
    done

    # Track failures so we can answer 500 instead of lying with a 200. Every
    # command is guarded with `|| rc=1` so `set -e` can't abort us mid-flush.
    rc=0
    if [ -n "$dom" ]; then
      unbound-control flush_zone "$dom" >/dev/null 2>&1 || rc=1
      # Also flush the immediate parent zone. A leaf flush leaves a stale NS
      # delegation or cached NXDOMAIN one level up (e.g. after the domain's
      # nameservers migrate), which is exactly what a leaf flush can't fix.
      parent=''${dom#*.}
      msg="flushed unbound zone '$dom'"
      case "$parent" in
        "$dom") : ;;   # no dot to strip (single-label name) — nothing above it
        *.*)
          unbound-control flush_zone "$parent" >/dev/null 2>&1 || rc=1
          msg="$msg + parent '$parent'"
          ;;
      esac
    else
      unbound-control reload >/dev/null 2>&1 || rc=1
      msg="flushed all unbound cache"
    fi

    # CoreDNS (cache 300) and AdGuard cache in front of unbound with no runtime
    # flush API, so bounce them. In-memory only, so ~1s blip on this node.
    systemctl restart adguardhome coredns >/dev/null 2>&1 || rc=1

    if [ "$rc" -ne 0 ]; then
      printf 'HTTP/1.1 500 Internal Server Error\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nflush FAILED (unbound-control or service restart errored)\n'
      exit 0
    fi
    printf 'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n%s\n' "$msg"
  '';
in
{
  # Socket activation: nothing resident. systemd listens on 8053 and, per
  # connection (Accept=true), spawns one dns-flush@<n>.service running the
  # handler with the connection on stdin/stdout.
  systemd.sockets.dns-flush = {
    description = "DNS cache-flush HTTP listener";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = 8053;
      Accept = true;
    };
  };

  systemd.services."dns-flush@" = {
    description = "DNS cache flush (one-shot, per connection)";
    serviceConfig = {
      ExecStart = handler;
      StandardInput = "socket";
      StandardOutput = "socket";
      # Runs as root (default): needs unbound-control + systemctl restart.
      ProtectHome = true;
      ProtectSystem = "strict";
      NoNewPrivileges = false; # systemctl restart needs to talk to PID 1
    };
  };

  networking.firewall.allowedTCPPorts = [ 8053 ];
}
