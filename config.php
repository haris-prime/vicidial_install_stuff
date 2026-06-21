<?php
/**
 * config.php  —  per-server settings.
 * Edit this file on each server; nothing else needs changing.
 */

// Branding shown in the table header (your screenshot says "DialEdge Telecom").
define('FW_TITLE', 'PRIME BPO Telecom');

// Where the rich records live (same format as your old data.json).
define('FW_DATA_FILE', __DIR__ . '/data.json');

// Flat, validated "one IP per line" file the root helper consumes.
// MUST match LISTFILE in /etc/fwgood.conf (see SETUP.md).
define('FW_LIST_FILE', __DIR__ . '/good.list');

// Full path to the root helper invoked via sudo.
define('FW_HELPER', '/usr/local/sbin/fwgood.sh');

// Allow whole subnets in CIDR form (e.g. 10.0.0.0/24) in addition to single IPs.
// Note: xt_recent does NOT support CIDR — leave this false unless you use the
// ipset backend with a hash:net set. See SETUP.md.
define('FW_ALLOW_CIDR', false);
