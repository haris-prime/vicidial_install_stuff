<?php
/**
 * cron-refresh.php  —  drop all Temporary=Y entries, then re-apply.
 * Replaces your old refresh_ip.php. Run it from cron as the WEB user (wwwrun)
 * so file ownership stays consistent and it can sudo the helper:
 *
 *   # crontab -u wwwrun -e
 *   0 6 * * *  /usr/bin/php /srv/www/htdocs/iptable/cron-refresh.php >/dev/null 2>&1
 *
 * (CLI only — refuses to run over the web.)
 */
if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit("CLI only\n");
}
require_once __DIR__ . '/lib.php';

$data = fw_load();
foreach ($data as $id => $rec) {
    if (($rec[2] ?? 'N') === 'Y') {
        unset($data[$id]);
    }
}
fw_save($data);

$err = null;
if (fw_apply($err)) {
    echo "refreshed: " . count($data) . " permanent entries applied\n";
} else {
    fwrite(STDERR, "apply failed: $err\n");
    exit(1);
}
