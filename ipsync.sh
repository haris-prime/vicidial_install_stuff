#!/bin/bash
#
# ipsync.sh  —  push the whitelist from THIS (master) server to the slaves.
# Runs on the master only. Syncs data.json, then has each slave rebuild and
# apply it with the new apply.php (no temp-purge — slaves mirror the master).
#
# Credentials: put them in /root/ipsync.conf (chmod 600) if you like; otherwise
# fill the slaves=() map below. A value of "key" (or empty) means use SSH key
# auth instead of a password — strongly recommended over storing root passwords.
#
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -uo pipefail

# ---- settings ---------------------------------------------------------------
SSH_PORT="${SSH_PORT:-61140}"
WEB_DIR="${WEB_DIR:-/srv/www/htdocs/iptable}"
WEB_USER="${WEB_USER:-wwwrun:www}"     # owner to restore on the slave after sync
SSH_OPTS="-p ${SSH_PORT} -o StrictHostKeyChecking=no -o ConnectTimeout=10"

# slaves: ["IP"]="root_password"   (or "key" for SSH-key auth)
declare -A slaves
slaves=(
    ["IP_Address"]="root_password"
)

# Optional external secrets file overrides the map above.
# It should define the same `slaves=(...)` array. Keep it: chmod 600 /root/ipsync.conf
[ -r /root/ipsync.conf ] && . /root/ipsync.conf

# ---- run --------------------------------------------------------------------
SRC="$WEB_DIR/data.json"
[ -f "$SRC" ] || { echo "ERROR: $SRC not found on master" >&2; exit 1; }

REMOTE_CMD="php ${WEB_DIR}/apply.php && chown ${WEB_USER} ${WEB_DIR}/data.json ${WEB_DIR}/good.list"

have_sshpass=0; command -v sshpass >/dev/null 2>&1 && have_sshpass=1
ok=0; fail=0

for host in "${!slaves[@]}"; do
    pass="${slaves[$host]}"
    echo "==> $host"

    if [ -n "$pass" ] && [ "$pass" != "key" ]; then
        if [ "$have_sshpass" -ne 1 ]; then
            echo "    SKIP: sshpass not installed and a password was given"; fail=$((fail+1)); continue
        fi
        RSYNC=(sshpass -p "$pass" rsync -q -e "ssh ${SSH_OPTS}" "$SRC" "root@${host}:${SRC}")
        SSHC=(sshpass -p "$pass" ssh ${SSH_OPTS} "root@${host}" "$REMOTE_CMD")
    else
        # SSH key auth (no password stored)
        RSYNC=(rsync -q -e "ssh ${SSH_OPTS}" "$SRC" "root@${host}:${SRC}")
        SSHC=(ssh ${SSH_OPTS} "root@${host}" "$REMOTE_CMD")
    fi

    if ! "${RSYNC[@]}"; then
        echo "    FAIL: rsync of data.json"; fail=$((fail+1)); continue
    fi
    if out="$("${SSHC[@]}" 2>&1)"; then
        echo "    OK: ${out}"; ok=$((ok+1))
    else
        echo "    FAIL: remote apply -> ${out}"; fail=$((fail+1))
    fi
done

echo "---- synced: $ok ok, $fail failed ----"
[ "$fail" -eq 0 ]
