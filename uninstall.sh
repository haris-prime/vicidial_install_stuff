#!/bin/bash
#
# uninstall.sh  —  revert everything install.sh did, back to the previous state.
#
# Run as root from the same /root/iptable folder:   ./uninstall.sh
# Reads the backups/state written by install.sh under <src>/.fwgood-install/.
#
# Restores each touched file if it existed before, removes it if it didn't,
# restores the original web directory, and undoes the ipset firewall changes.
#
# Re-exec under bash if started with sh/dash.
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

SRC_DIR="${SRC_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
STATE_DIR="${STATE_DIR:-$SRC_DIR/.fwgood-install}"
ETC_BAK="$STATE_DIR/etc-backup"

log()  { echo "[uninstall] $*"; }
warn() { echo "[uninstall][warn] $*" >&2; }
die()  { echo "[uninstall][ERROR] $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must be run as root"
[ -f "$STATE_DIR/state.env" ] || die "no install state in $STATE_DIR — nothing to revert"

# shellcheck disable=SC1090
. "$STATE_DIR/state.env"
WEBDIR_EXISTED="${WEBDIR_EXISTED:-0}"
IPSET_RULE_ADDED="${IPSET_RULE_ADDED:-0}"

log "reverting (backend=$BACKEND, web=$WEB_DIR)"

slug() { echo "$1" | sed 's#[/.]#_#g'; }
# restore_path PATH : put a managed file back exactly as it was before install
restore_path() {
    local p="$1" s; s="$(slug "$p")"
    if [ -e "$ETC_BAK/$s.orig" ]; then
        cp -a "$ETC_BAK/$s.orig" "$p"; log "restored original $p"
    elif [ -e "$ETC_BAK/$s.absent" ]; then
        rm -f "$p"; log "removed $p (did not exist before)"
    else
        warn "no backup record for $p — leaving as-is"
    fi
}

# ---- save the CURRENT data.json aside (revert rolls it back to install-time) -
if [ -f "$WEB_DIR/data.json" ]; then
    cp -a "$WEB_DIR/data.json" "$SRC_DIR/data.json.before-revert" 2>/dev/null || true
    warn "current data.json saved to $SRC_DIR/data.json.before-revert"
    warn "(revert restores the data.json that existed at install time)"
fi

# ---- undo ipset firewall changes (ipset backend only) ----------------------
if [ "$BACKEND" = "ipset" ]; then
    if iptables -L input_ext -n >/dev/null 2>&1; then
        while iptables -C input_ext -m set --match-set "$SETNAME" src -j ACCEPT >/dev/null 2>&1; do
            iptables -D input_ext -m set --match-set "$SETNAME" src -j ACCEPT || break
            log "removed live accept rule"
        done
    fi
    # restore_path on SUSEFW below removes our persisted lines by restoring the original
    if command -v ipset >/dev/null 2>&1 && ipset list "$SETNAME" >/dev/null 2>&1; then
        ipset destroy "$SETNAME" 2>/dev/null && log "destroyed ipset $SETNAME" \
            || warn "could not destroy ipset $SETNAME (still referenced?)"
    fi
fi

# ---- systemd ----------------------------------------------------------------
if systemctl list-unit-files 2>/dev/null | grep -q '^fwgood.service'; then
    systemctl disable --now fwgood.service >/dev/null 2>&1 || true
    log "disabled fwgood.service"
fi

# ---- restore all managed /etc + sbin paths ---------------------------------
for p in "$HELPER" "$SUDOERS" "$UNIT" "$CONF" "$MODPROBE" "$SUSEFW"; do
    [ -n "${p:-}" ] && restore_path "$p"
done
systemctl daemon-reload 2>/dev/null || true

# ---- restore the web directory ---------------------------------------------
if [ "$WEBDIR_EXISTED" = "1" ] && [ -f "$STATE_DIR/webdir-backup.tar.gz" ]; then
    log "restoring original web directory contents"
    rm -rf "${WEB_DIR:?}/"* "${WEB_DIR:?}"/.htaccess "${WEB_DIR:?}"/.htpasswd 2>/dev/null || true
    tar -C "$WEB_DIR" -xzf "$STATE_DIR/webdir-backup.tar.gz"
else
    log "web directory did not exist before; removing $WEB_DIR"
    rm -rf "${WEB_DIR:?}"
fi

# ---- note about xt_recent runtime cap --------------------------------------
if [ "$BACKEND" = "xt_recent" ]; then
    warn "the running xt_recent ip_list_tot value is unchanged until the next module reload/reboot (cosmetic)."
fi

# ---- clean up state ---------------------------------------------------------
rm -rf "$STATE_DIR"
echo
log "DONE — system reverted to the pre-install state."
[ -f "$SRC_DIR/data.json.before-revert" ] && log "your most recent IP list is saved at $SRC_DIR/data.json.before-revert"
