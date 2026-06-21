#!/bin/bash
#
# fwgood.sh  —  the ONLY thing that touches the firewall. Runs as root via a
# tightly-scoped sudo rule; the web app (wwwrun) calls: sudo fwgood.sh apply
#
# It reads a flat "one IP per line" file (good.list), re-validates every line,
# and rebuilds the allow-list. Re-validation here is defence in depth: even if
# good.list were tampered with, only well-formed IPs ever reach the kernel.
#
set -euo pipefail

# ---- defaults (override in /etc/fwgood.conf) -------------------------------
BACKEND="xt_recent"                               # "xt_recent" or "ipset"
SETNAME="GOOD"
LISTFILE="/srv/www/htdocs/iptable/good.list"
IPSET_TYPE="hash:ip"                              # use hash:net if you allow CIDR
IPSET_MAXELEM="65536"

[ -r /etc/fwgood.conf ] && . /etc/fwgood.conf

log() { logger -t fwgood -- "$*" 2>/dev/null || true; echo "fwgood: $*" >&2; }

# Accept IPv4, IPv6, or CIDR. Returns 0 if valid.
valid_ip() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]] && return 0   # IPv4 / CIDR
  [[ "$ip" =~ ^[0-9A-Fa-f:]+(/[0-9]{1,3})?$ && "$ip" == *:* ]] && return 0  # IPv6 / CIDR
  return 1
}

apply_ipset() {
  command -v ipset >/dev/null || { log "ipset not installed"; exit 4; }
  # Build into a temp set, then atomic swap — the live set is never empty,
  # so a rebuild can never briefly lock anyone out.
  ipset create -exist "$SETNAME"      "$IPSET_TYPE" maxelem "$IPSET_MAXELEM"
  ipset create -exist "${SETNAME}_tmp" "$IPSET_TYPE" maxelem "$IPSET_MAXELEM"
  ipset flush "${SETNAME}_tmp"
  local n=0
  if [ -r "$LISTFILE" ]; then
    while IFS= read -r ip; do
      ip="${ip//[$'\t\r\n ']/}"
      [ -z "$ip" ] && continue
      if valid_ip "$ip"; then ipset add -exist "${SETNAME}_tmp" "$ip"; n=$((n+1));
      else log "skipped invalid entry: $ip"; fi
    done < "$LISTFILE"
  fi
  ipset swap "${SETNAME}_tmp" "$SETNAME"
  ipset destroy "${SETNAME}_tmp"
  log "ipset $SETNAME rebuilt with $n entries"
}

apply_xt_recent() {
  local proc="/proc/net/xt_recent/$SETNAME"
  if [ ! -e "$proc" ]; then
    log "ERROR: $proc missing. Is the iptables rule with --name $SETNAME loaded?"
    exit 3
  fi
  echo / > "$proc"            # flush
  local n=0
  if [ -r "$LISTFILE" ]; then
    while IFS= read -r ip; do
      ip="${ip//[$'\t\r\n ']/}"
      [ -z "$ip" ] && continue
      if valid_ip "$ip"; then echo "+$ip" > "$proc"; n=$((n+1));
      else log "skipped invalid entry: $ip"; fi
    done < "$LISTFILE"
  fi
  log "xt_recent $SETNAME rebuilt with $n entries"
}

case "${1:-}" in
  apply)
    if [ "$BACKEND" = "ipset" ]; then apply_ipset; else apply_xt_recent; fi
    ;;
  *)
    echo "usage: $0 apply" >&2
    exit 1
    ;;
esac
