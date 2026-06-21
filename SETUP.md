# Whitelisted IP Management — hardened rebuild

A drop-in replacement for the old `iptable/` web tool. Same UI, same
`data.json` format (your existing data works unchanged), but it fixes the
reasons the old one failed on some servers.

## Files

| File                | Goes where                                   | Owner / mode        |
|---------------------|----------------------------------------------|---------------------|
| `index.php`         | `/srv/www/htdocs/iptable/`                   | `wwwrun` 0644       |
| `lib.php`           | `/srv/www/htdocs/iptable/`                   | `wwwrun` 0644       |
| `config.php`        | `/srv/www/htdocs/iptable/` (edit per server) | `wwwrun` 0644       |
| `cron-refresh.php`  | `/srv/www/htdocs/iptable/`                   | `wwwrun` 0644       |
| `data.json`         | `/srv/www/htdocs/iptable/` (your existing one)| `wwwrun` 0644      |
| `htaccess.txt`      | rename to `.htaccess` in the web dir         | `wwwrun` 0644       |
| `fwgood.sh`         | `/usr/local/sbin/fwgood.sh`                  | **root:root 0755**  |
| `sudoers-fwgood`    | `/etc/sudoers.d/fwgood`                      | root 0440           |
| `fwgood.service`    | `/etc/systemd/system/fwgood.service`         | root 0644           |
| `fwgood.conf`       | `/etc/fwgood.conf` (you create it, see below)| root 0644           |

The helper being **root-owned and not writable by wwwrun** is what makes the
sudo rule safe. Don't put `fwgood.sh` inside the web directory.

## Install (common to both backends)

```bash
# 1. Web files
cp index.php lib.php config.php cron-refresh.php /srv/www/htdocs/iptable/
cp htaccess.txt /srv/www/htdocs/iptable/.htaccess
chown wwwrun:www /srv/www/htdocs/iptable/*.php

# 2. Basic-auth user (the old .htaccess relied on this)
htpasswd -c /srv/www/htdocs/iptable/.htpasswd admin

# 3. Root helper
cp fwgood.sh /usr/local/sbin/fwgood.sh
chown root:root /usr/local/sbin/fwgood.sh
chmod 0755 /usr/local/sbin/fwgood.sh

# 4. Sudo rule (validate before saving!)
visudo -cf sudoers-fwgood && cp sudoers-fwgood /etc/sudoers.d/fwgood && chmod 0440 /etc/sudoers.d/fwgood

# 5. Boot persistence (no more empty list after a reboot)
cp fwgood.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable fwgood.service
```

Create `/etc/fwgood.conf` (read by the helper):

```bash
BACKEND="xt_recent"          # or "ipset"
SETNAME="GOOD"
LISTFILE="/srv/www/htdocs/iptable/good.list"
# ipset only:
IPSET_TYPE="hash:ip"         # hash:net if you whitelist CIDR ranges
IPSET_MAXELEM="65536"
```

Then prime it once: open the web page and add/save anything, or run
`sudo -u wwwrun php /srv/www/htdocs/iptable/cron-refresh.php`.

---

## Choose a backend

### Option A — keep xt_recent (no firewall rule change)

Your current rule stays:

```
iptables -I input_ext 2 -m recent --rcheck --name GOOD -j ACCEPT
```

But fix the two things that broke "some servers":

1. **Raise the 100-IP cap.** Default `ip_list_tot=100` silently drops your
   oldest entries. Set it permanently:

   ```bash
   echo 'options xt_recent ip_list_tot=4096' > /etc/modprobe.d/xt_recent.conf
   # then reload the module (or reboot) so it takes effect:
   modprobe -r xt_recent 2>/dev/null; modprobe xt_recent
   ```
   (After reloading the module the proc file is recreated empty — the
   `fwgood.service` / a manual `sudo fwgood.sh apply` refills it.)

2. **Permissions are already solved** — PHP no longer writes to `/proc`;
   `fwgood.sh` does, as root via sudo.

Set `BACKEND="xt_recent"` in `/etc/fwgood.conf`.

> One caveat with xt_recent: rebuilds flush-then-refill, so there's a
> sub-second window where the list is empty. That's the main reason to prefer:

### Option B — switch to ipset (recommended)

No 100-entry cap, rebuilds **atomically** (live set never empties), and it
persists cleanly. Install ipset and change one firewall line.

```bash
zypper install -y ipset
```

Set `BACKEND="ipset"` in `/etc/fwgood.conf`, then replace your rule:

```
# old:
iptables -I input_ext 2 -m recent --rcheck --name GOOD -j ACCEPT
# new:
iptables -I input_ext 2 -m set --match-set GOOD src -j ACCEPT
```

In SuSEfirewall2, put both the *set creation* and the *rule* in the custom
rules file so they survive a firewall reload (this is the fix for "the rule
disappears sometimes"): edit `/etc/sysconfig/scripts/SuSEfirewall2-custom`,
function `fw_custom_after_chain_creation`:

```sh
fw_custom_after_chain_creation() {
    ipset create -exist GOOD hash:ip maxelem 65536
    iptables -I input_ext 2 -m set --match-set GOOD src -j ACCEPT
    true
}
```

The `GOOD` set must exist *before* the rule loads — `ipset create -exist` above
handles that. `fwgood.service` then fills it at boot from `good.list`.

---

## Why the old one failed on some servers (summary)

- **Permissions:** PHP (wwwrun) couldn't write the root-owned `/proc/net/xt_recent/GOOD`; the `echo` failed silently. → now done by root via sudo.
- **100-IP cap:** `ip_list_tot=100` dropped the oldest IPs. → raised, or removed entirely by ipset.
- **Missing proc file / rule:** if the `--name GOOD` rule wasn't loaded, the file didn't exist. → rule moved into SuSEfirewall2 custom rules; helper reports clearly if it's missing.
- **Reboot wiped the in-kernel list:** nothing refilled it. → `fwgood.service` refills at boot.
- **(Security) command injection + no file locking:** unvalidated `$_GET['ip']` went into `system()`. → strict `filter_var` validation + `escapeshellarg` + `flock`.

## Multi-server sync (master → slaves)

Run `install.sh` on **every** server (master and slaves) — that puts `apply.php`
and the helper on each. Then edit only the master via the web UI; `ipsync.sh`
(master only) pushes `data.json` to the slaves and has each one rebuild and apply:

1. rsync `data.json` to the slave
2. `php apply.php` on the slave → regenerates `good.list` and applies (no purge,
   so the slave mirrors the master exactly)
3. chown the files back to the web user

Old flow ran `refresh_ip.php` remotely, which *purged* temporary IPs on every
sync. The new flow doesn't — the master's daily `cron-refresh.php` does the
purge, and that result reaches the slaves through the normal sync.

Put credentials in `/root/ipsync.conf` (`chmod 600`) instead of inline, and
prefer SSH keys over stored root passwords (set a slave's value to `key`):

```bash
ssh-keygen -t ed25519                              # once on the master
ssh-copy-id -p 61140 root@<slave-ip>               # per slave
```

Schedule it on the master, e.g. every 5 min:

```
*/5 * * * *  /root/ipsync.sh >> /var/log/ipsync.log 2>&1
```

> Note: `uninstall.sh` reverts a single server. On a slave it restores the old
> web tool; on the master, remove `ipsync.sh`/`ipsync.conf` yourself if you no
> longer want syncing.

## Quick test

```bash
# add an IP in the web UI, then:
sudo fwgood.sh apply
ipset list GOOD            # (ipset backend)
cat /proc/net/xt_recent/GOOD   # (xt_recent backend)
```
