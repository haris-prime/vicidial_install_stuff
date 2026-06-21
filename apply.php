<?php
/**
 * apply.php  —  rebuild good.list from the current data.json and push it to the
 * firewall. Does NOT remove anything (unlike cron-refresh.php). This is what the
 * sync runs on each slave after data.json is rsynced in, so the slave mirrors
 * the master exactly.
 *
 *   php /srv/www/htdocs/iptable/apply.php
 *
 * CLI only.
 */
if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit("CLI only\n");
}
require_once __DIR__ . '/lib.php';

$data = fw_load();      // read whatever was synced in
fw_save($data);         // rewrites data.json (same content) + regenerates good.list

$err = null;
if (fw_apply($err)) {
    echo "applied: " . count($data) . " entries\n";
    exit(0);
}
fwrite(STDERR, "apply failed: $err\n");
exit(1);
