#!/usr/bin/env bash
set -euo pipefail

IP="${1:-}"

if [[ -z "$IP" ]]; then
  echo "Usage: ./scripts/test.sh <ip>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOMAIN=$(grep 'domain' "$SCRIPT_DIR/config.nix" | head -1 | sed 's/.*"\(.*\)".*/\1/')
LOCAL_IP=$(grep 'localIP' "$SCRIPT_DIR/config.nix" | head -1 | sed 's/.*"\(.*\)".*/\1/')

pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAILURES=$((FAILURES + 1)); }
info() { printf "  \033[90m→\033[0m %s\n" "$1"; }

FAILURES=0

echo ""
echo "Testing $IP"
echo "─────────────────────────────────"

# Connectivity
echo ""
echo "Connectivity"
if ping -c 1 -t 5 "$IP" > /dev/null 2>&1; then
  LATENCY=$(ping -c 1 -t 5 "$IP" 2>/dev/null | grep "time=" | sed 's/.*time=\([^ ]*\).*/\1/')
  pass "Reachable (${LATENCY}ms)"
else
  fail "Not reachable"
  echo ""
  echo "Node is offline. Aborting."
  exit 1
fi

# Gather all SSH data in a single connection
echo ""
echo "SSH"
SSH_DATA=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$IP" "
  echo \"HOSTNAME:\$(hostname)\"
  for svc in unbound adguardhome coredns systemd-timesyncd systemd-time-wait-sync; do
    echo \"SVC:\$svc:\$(systemctl is-active \$svc)\"
  done
  echo \"TIMESYNC:\$(timedatectl | grep synchronized | awk '{print \$NF}')\"
  echo \"TIME:\$(date '+%Y-%m-%d %H:%M:%S %Z')\"
  echo \"MEM:\$(free -m | grep Mem | awk '{print \$2,\$3,\$7}')\"
  echo \"FILTERS:\$(curl -sf http://127.0.0.1:3000/control/filtering/status 2>/dev/null | jq -r '.filters[] | \"\(.name)|\(.rules_count)\"' 2>/dev/null || echo '')\"
" 2>/dev/null) && SSH_OK=true || SSH_OK=false

if [[ "$SSH_OK" == true ]]; then
  HOSTNAME=$(echo "$SSH_DATA" | grep "^HOSTNAME:" | cut -d: -f2)
  pass "Connected — hostname: $HOSTNAME"
else
  fail "Cannot connect"
fi

# Services
echo ""
echo "Services"
if [[ "$SSH_OK" == true ]]; then
  while IFS= read -r line; do
    SVC=$(echo "$line" | cut -d: -f2)
    STATUS=$(echo "$line" | cut -d: -f3)
    if [[ "$STATUS" == "active" ]]; then
      pass "$SVC"
    else
      fail "$SVC ($STATUS)"
    fi
  done < <(echo "$SSH_DATA" | grep "^SVC:")
else
  info "Skipped (no SSH)"
fi

# Time
echo ""
echo "Clock"
if [[ "$SSH_OK" == true ]]; then
  SYNCED=$(echo "$SSH_DATA" | grep "^TIMESYNC:" | cut -d: -f2)
  TIME=$(echo "$SSH_DATA" | grep "^TIME:" | cut -d: -f2-)
  if [[ "$SYNCED" == "yes" ]]; then
    pass "Synchronized ($TIME)"
  else
    fail "Not synchronized"
  fi
else
  info "Skipped (no SSH)"
fi

# Memory
echo ""
echo "Memory"
if [[ "$SSH_OK" == true ]]; then
  MEM=$(echo "$SSH_DATA" | grep "^MEM:" | cut -d: -f2)
  TOTAL=$(echo "$MEM" | awk '{print $1}')
  USED=$(echo "$MEM" | awk '{print $2}')
  AVAIL=$(echo "$MEM" | awk '{print $3}')
  pass "${USED}MB used / ${AVAIL}MB available / ${TOTAL}MB total"
else
  info "Skipped (no SSH)"
fi

# DNS resolution
echo ""
echo "DNS"
RESULT=$(dig @"$IP" google.com +short +time=5 2>/dev/null | head -1)
if [[ -n "$RESULT" ]]; then
  pass "External resolution (google.com → $RESULT)"
else
  fail "External resolution failed"
fi

RESULT=$(dig @"$IP" "test.${DOMAIN}" +short +time=5 2>/dev/null | head -1)
if [[ "$RESULT" == "$LOCAL_IP" ]]; then
  pass "Local domain (test.${DOMAIN} → $RESULT)"
else
  fail "Local domain (got: ${RESULT:-timeout})"
fi

# Ad blocking
echo ""
echo "Ad blocking"
RESULT=$(dig @"$IP" googleadservices.com +short +time=5 2>/dev/null | head -1)
if [[ "$RESULT" == "0.0.0.0" ]]; then
  pass "Blocking active (googleadservices.com → 0.0.0.0)"
else
  fail "Not blocking (googleadservices.com → ${RESULT:-timeout})"
fi

# Filter lists
if [[ "$SSH_OK" == true ]]; then
  FILTERS=$(echo "$SSH_DATA" | grep "^FILTERS:" | cut -d: -f2-)
  if [[ -n "$FILTERS" ]]; then
    while IFS='|' read -r name count; do
      if [[ "$count" -gt 0 ]] 2>/dev/null; then
        pass "$name: $count rules"
      else
        fail "$name: $count rules"
      fi
    done < <(echo "$FILTERS" | tr ' ' '\n' | grep '|')
  fi
fi

# Latency
echo ""
echo "DNS latency"
COLD=$(dig @"$IP" "random-$(date +%s).example.com" +time=5 2>/dev/null | grep "Query time" | awk '{print $4}')
WARM=$(dig @"$IP" google.com +time=5 2>/dev/null | grep "Query time" | awk '{print $4}')
info "Cached: ${WARM:-?}ms"
info "Cold:   ${COLD:-?}ms"

# Summary
echo ""
echo "─────────────────────────────────"
if [[ $FAILURES -eq 0 ]]; then
  printf "\033[32mAll checks passed.\033[0m\n"
else
  printf "\033[31m%d check(s) failed.\033[0m\n" "$FAILURES"
fi
echo ""
