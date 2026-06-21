#!/bin/bash
#
# install.sh  —  set up the hardened IP-whitelist tool from /root/iptable.
#
# Run as root:   ./install.sh
# Options (env vars):
#   BACKEND=ipset        use ipset instead of xt_recent (default: xt_recent)
#   WEB_USER=wwwrun      web server user (auto-detected if unset)
#   WEB_DIR=/srv/www/htdocs/iptable   where the web files live
#   IP_LIST_TOT=4096     xt_recent address cap (xt_recent backend only)
#   HTPASSWD_USER / HTPASSWD_PASS   create basic-auth user non-interactively
#
# Everything it changes is backed up under  <src>/.fwgood-install/  so that
# uninstall.sh can restore the exact previous state.
#
# Re-exec under bash if started with sh/dash (this script uses bash features).
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

SRC_DIR="${SRC_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
WEB_DIR="${WEB_DIR:-/srv/www/htdocs/iptable}"
BACKEND="${BACKEND:-xt_recent}"
SETNAME="${SETNAME:-GOOD}"
IP_LIST_TOT="${IP_LIST_TOT:-4096}"
STATE_DIR="${STATE_DIR:-$SRC_DIR/.fwgood-install}"

HELPER="/usr/local/sbin/fwgood.sh"
CONF="/etc/fwgood.conf"
SUDOERS="/etc/sudoers.d/fwgood"
UNIT="/etc/systemd/system/fwgood.service"
MODPROBE="/etc/modprobe.d/xt_recent.conf"
SUSEFW="/etc/sysconfig/scripts/SuSEfirewall2-custom"
LISTFILE="$WEB_DIR/good.list"
ETC_BAK="$STATE_DIR/etc-backup"

log()  { echo "[install] $*"; }
warn() { echo "[install][warn] $*" >&2; }
die()  { echo "[install][ERROR] $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must be run as root"
[ -f "$SRC_DIR/index.php" ] && [ -f "$SRC_DIR/fwgood.sh" ] \
    || die "source files not found in $SRC_DIR (expected index.php, fwgood.sh, ...)"
case "$BACKEND" in xt_recent|ipset) ;; *) die "BACKEND must be xt_recent or ipset" ;; esac

# ---- detect web user/group --------------------------------------------------
if [ -z "${WEB_USER:-}" ]; then
    for u in wwwrun www-data apache nginx; do
        if id "$u" >/dev/null 2>&1; then WEB_USER="$u"; break; fi
    done
fi
[ -n "${WEB_USER:-}" ] || die "could not detect web user; set WEB_USER=..."
WEB_GROUP="$(id -gn "$WEB_USER")"
log "web user = $WEB_USER:$WEB_GROUP, web dir = $WEB_DIR, backend = $BACKEND"

mkdir -p "$STATE_DIR" "$ETC_BAK"

# ---- helpers: back up a path exactly once, so revert is reliable ------------
slug() { echo "$1" | sed 's#[/.]#_#g'; }
backup_once() {
    local p="$1" s; s="$(slug "$p")"
    [ -e "$ETC_BAK/$s.existed" ] && return 0
    [ -e "$ETC_BAK/$s.absent" ]  && return 0
    if [ -e "$p" ]; then cp -a "$p" "$ETC_BAK/$s.orig"; touch "$ETC_BAK/$s.existed"
    else touch "$ETC_BAK/$s.absent"; fi
}

# ---- record install state (read by uninstall.sh) ---------------------------
if [ ! -f "$STATE_DIR/state.env" ]; then
    cat > "$STATE_DIR/state.env" <<EOF
# created by install.sh on $(date '+%Y-%m-%d %H:%M:%S')
BACKEND="$BACKEND"
WEB_USER="$WEB_USER"
WEB_GROUP="$WEB_GROUP"
WEB_DIR="$WEB_DIR"
SETNAME="$SETNAME"
HELPER="$HELPER"
CONF="$CONF"
SUDOERS="$SUDOERS"
UNIT="$UNIT"
MODPROBE="$MODPROBE"
SUSEFW="$SUSEFW"
EOF
fi

# ---- back up & install the web directory -----------------------------------
if [ -d "$WEB_DIR" ] && [ ! -f "$STATE_DIR/webdir-backup.tar.gz" ]; then
    log "backing up existing $WEB_DIR"
    tar -C "$WEB_DIR" -czf "$STATE_DIR/webdir-backup.tar.gz" . 2>/dev/null || true
    echo "WEBDIR_EXISTED=1" >> "$STATE_DIR/state.env"
elif [ ! -d "$WEB_DIR" ] && ! grep -q '^WEBDIR_EXISTED=' "$STATE_DIR/state.env"; then
    echo "WEBDIR_EXISTED=0" >> "$STATE_DIR/state.env"
fi

mkdir -p "$WEB_DIR"
for f in index.php lib.php config.php cron-refresh.php apply.php; do
    install -o "$WEB_USER" -g "$WEB_GROUP" -m 0644 "$SRC_DIR/$f" "$WEB_DIR/$f"
done
# keep the server's REAL data.json; only seed an empty one if none exists
if [ ! -f "$WEB_DIR/data.json" ]; then
    install -o "$WEB_USER" -g "$WEB_GROUP" -m 0644 "$SRC_DIR/data.json" "$WEB_DIR/data.json"
    log "seeded empty data.json"
else
    log "kept existing data.json (your IPs are preserved)"
fi
# .htaccess
if [ -f "$SRC_DIR/htaccess.txt" ]; then
    install -o "$WEB_USER" -g "$WEB_GROUP" -m 0644 "$SRC_DIR/htaccess.txt" "$WEB_DIR/.htaccess"
    sed -i "s#/srv/www/htdocs/iptable#$WEB_DIR#g" "$WEB_DIR/.htaccess"
fi
# point config.php at the chosen web dir paths
sed -i "s#__DIR__ . '/data.json'#'$WEB_DIR/data.json'#; s#__DIR__ . '/good.list'#'$WEB_DIR/good.list'#" "$WEB_DIR/config.php" 2>/dev/null || true

# ---- root helper ------------------------------------------------------------
backup_once "$HELPER"
install -o root -g root -m 0755 "$SRC_DIR/fwgood.sh" "$HELPER"

# ---- /etc/fwgood.conf -------------------------------------------------------
backup_once "$CONF"
cat > "$CONF" <<EOF
# managed by install.sh
BACKEND="$BACKEND"
SETNAME="$SETNAME"
LISTFILE="$LISTFILE"
IPSET_TYPE="hash:ip"
IPSET_MAXELEM="65536"
EOF
chmod 0644 "$CONF"

# ---- sudoers (generated so the user matches) -------------------------------
backup_once "$SUDOERS"
TMP_SUDO="$(mktemp)"
echo "$WEB_USER ALL=(root) NOPASSWD: $HELPER apply" > "$TMP_SUDO"
if visudo -cf "$TMP_SUDO" >/dev/null 2>&1; then
    install -o root -g root -m 0440 "$TMP_SUDO" "$SUDOERS"
    log "sudoers rule installed"
else
    rm -f "$TMP_SUDO"; die "generated sudoers failed validation"
fi
rm -f "$TMP_SUDO"

# ---- systemd unit (boot persistence) ---------------------------------------
backup_once "$UNIT"
install -o root -g root -m 0644 "$SRC_DIR/fwgood.service" "$UNIT"
systemctl daemon-reload
systemctl enable fwgood.service >/dev/null 2>&1 || warn "could not enable fwgood.service"

# ---- backend-specific setup -------------------------------------------------
if [ "$BACKEND" = "xt_recent" ]; then
    backup_once "$MODPROBE"
    echo "options xt_recent ip_list_tot=$IP_LIST_TOT" > "$MODPROBE"
    log "set xt_recent ip_list_tot=$IP_LIST_TOT (takes effect on next module load / reboot)"
    if ! lsmod 2>/dev/null | grep -q '^xt_recent'; then
        warn "xt_recent not currently loaded; load your firewall rule with --name $SETNAME first"
    fi
else
    # ipset backend
    if ! command -v ipset >/dev/null 2>&1; then
        if command -v zypper >/dev/null 2>&1; then
            log "installing ipset"; zypper --non-interactive install ipset >/dev/null || warn "ipset install failed"
        else
            warn "ipset not installed and zypper unavailable; install it manually"
        fi
    fi
    ipset create -exist "$SETNAME" hash:ip maxelem 65536 || warn "ipset create failed"
    # live rule (only if the SuSEfirewall2 chain exists right now)
    if iptables -L input_ext -n >/dev/null 2>&1; then
        if ! iptables -C input_ext -m set --match-set "$SETNAME" src -j ACCEPT >/dev/null 2>&1; then
            iptables -I input_ext 2 -m set --match-set "$SETNAME" src -j ACCEPT \
                && echo "IPSET_RULE_ADDED=1" >> "$STATE_DIR/state.env" \
                && log "inserted live accept rule into input_ext"
        else
            log "live accept rule already present"
        fi
    else
        warn "chain input_ext not found; skipping live rule (will rely on persisted rule)"
    fi
    # persist in SuSEfirewall2 custom file
    if [ -f "$SUSEFW" ]; then
        backup_once "$SUSEFW"
        if ! grep -q 'fwgood-managed' "$SUSEFW"; then
            INSERT=$'\tipset create -exist '"$SETNAME"$' hash:ip maxelem 65536 # fwgood-managed\n\tiptables -I input_ext 2 -m set --match-set '"$SETNAME"$' src -j ACCEPT # fwgood-managed'
            awk -v b="$INSERT" '
                /fw_custom_after_chain_creation\(\)[[:space:]]*\{/ && !d { print; print b; d=1; next } { print }
            ' "$SUSEFW" > "$SUSEFW.fwtmp" && mv "$SUSEFW.fwtmp" "$SUSEFW"
            log "persisted ipset rule in $SUSEFW"
        fi
    else
        warn "$SUSEFW not found; add the ipset rule to your firewall config manually (see SETUP.md)"
    fi
fi

# ---- generate good.list from data.json, then apply -------------------------
gen_list() {
    if command -v php >/dev/null 2>&1; then
        php -r '$d=json_decode(@file_get_contents($argv[1]),true)?:[]; foreach($d as $r){if(filter_var($r[0],FILTER_VALIDATE_IP))echo $r[0]."\n";}' \
            "$WEB_DIR/data.json" > "$LISTFILE" 2>/dev/null || : > "$LISTFILE"
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$WEB_DIR/data.json" "$LISTFILE" <<'PY'
import json,sys,ipaddress
try: d=json.load(open(sys.argv[1]))
except Exception: d={}
vals=d.values() if isinstance(d,dict) else (d or [])
out=[]
for r in vals:
    ip=r[0]
    try: ipaddress.ip_address(ip); out.append(ip); continue
    except Exception: pass
    try: ipaddress.ip_network(ip,strict=False); out.append(ip)
    except Exception: pass
open(sys.argv[2],"w").write("\n".join(out)+("\n" if out else ""))
PY
    else
        : > "$LISTFILE"; warn "neither php nor python3 found; good.list will fill on first web save"
    fi
    chown "$WEB_USER:$WEB_GROUP" "$LISTFILE" 2>/dev/null || true
    chmod 0644 "$LISTFILE" 2>/dev/null || true
}
gen_list

log "applying current list to the firewall"
if "$HELPER" apply; then log "applied OK"; else warn "apply reported a problem (see messages above)"; fi

# ---- basic-auth user --------------------------------------------------------
HTBIN="$(command -v htpasswd || command -v htpasswd2 || true)"
if [ -n "$HTBIN" ] && [ ! -f "$WEB_DIR/.htpasswd" ]; then
    if [ -n "${HTPASSWD_USER:-}" ] && [ -n "${HTPASSWD_PASS:-}" ]; then
        "$HTBIN" -cbB "$WEB_DIR/.htpasswd" "$HTPASSWD_USER" "$HTPASSWD_PASS" >/dev/null
        log "created basic-auth user '$HTPASSWD_USER'"
    elif [ -t 0 ]; then
        read -r -p "Basic-auth username: " HU
        "$HTBIN" -cB "$WEB_DIR/.htpasswd" "$HU"
    else
        warn "no .htpasswd created; run: $HTBIN -cB $WEB_DIR/.htpasswd <user>"
    fi
    [ -f "$WEB_DIR/.htpasswd" ] && chown "$WEB_USER:$WEB_GROUP" "$WEB_DIR/.htpasswd" && chmod 0640 "$WEB_DIR/.htpasswd"
elif [ -z "$HTBIN" ]; then
    warn "htpasswd not found; create $WEB_DIR/.htpasswd manually for auth to work"
fi

echo
log "DONE."
log "  state/backups kept in: $STATE_DIR  (needed by uninstall.sh — keep it)"
if [ "$BACKEND" = "xt_recent" ]; then
    log "  backend xt_recent: your existing '--name $SETNAME' rule is reused; reboot to apply the ip_list_tot bump."
else
    log "  backend ipset: rule '-m set --match-set $SETNAME src -j ACCEPT' is live + persisted."
fi
log "  test:  $HELPER apply  &&  ( ipset list $SETNAME 2>/dev/null || cat /proc/net/xt_recent/$SETNAME )"
