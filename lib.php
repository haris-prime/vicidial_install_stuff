<?php
/**
 * lib.php  —  shared helpers. No HTML here.
 */
require_once __DIR__ . '/config.php';

/**
 * Strict server-side IP validation. Returns the normalised IP string, or false.
 * This is the gate that closes the old command-injection hole: anything that
 * isn't a clean IPv4/IPv6 (or CIDR, if enabled) never reaches the shell.
 */
function fw_valid_ip($ip)
{
    $ip = trim((string)$ip);
    if ($ip === '') {
        return false;
    }

    // Optional CIDR support (ipset hash:net only — see config).
    if (FW_ALLOW_CIDR && strpos($ip, '/') !== false) {
        list($addr, $mask) = explode('/', $ip, 2);
        if (!ctype_digit($mask)) {
            return false;
        }
        $mask = (int)$mask;
        if (filter_var($addr, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) && $mask >= 0 && $mask <= 32) {
            return $addr . '/' . $mask;
        }
        if (filter_var($addr, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6) && $mask >= 0 && $mask <= 128) {
            return $addr . '/' . $mask;
        }
        return false;
    }

    $clean = filter_var($ip, FILTER_VALIDATE_IP);
    return $clean === false ? false : $clean;
}

/** Name/label sanitiser — keep it printable, no control chars, capped length. */
function fw_clean_name($name)
{
    $name = preg_replace('/[\x00-\x1F\x7F]/u', '', (string)$name);
    $name = trim($name);
    return mb_substr($name, 0, 64);
}

/** Temporary flag is strictly Y or N. */
function fw_clean_temp($t)
{
    return ($t === 'Y') ? 'Y' : 'N';
}

/**
 * Load records under a shared lock. Tolerates the old "[]" empty-array form.
 * Returns an associative array keyed by integer id.
 */
function fw_load()
{
    if (!file_exists(FW_DATA_FILE)) {
        return array();
    }
    $fh = fopen(FW_DATA_FILE, 'r');
    if (!$fh) {
        return array();
    }
    flock($fh, LOCK_SH);
    $raw = stream_get_contents($fh);
    flock($fh, LOCK_UN);
    fclose($fh);

    $data = json_decode($raw, true);
    if (!is_array($data)) {
        $data = array();
    }
    return $data;
}

/**
 * Persist records AND regenerate the flat good.list (validated IPs only),
 * all under an exclusive lock so concurrent edits can't corrupt either file.
 */
function fw_save(array $data)
{
    ksort($data, SORT_NUMERIC);

    $fh = fopen(FW_DATA_FILE, 'c+');
    if (!$fh) {
        return false;
    }
    flock($fh, LOCK_EX);

    ftruncate($fh, 0);
    rewind($fh);
    fwrite($fh, json_encode($data, JSON_PRETTY_PRINT));
    fflush($fh);

    // Rebuild the flat list the root helper reads. Re-validate as we go.
    $lines = array();
    foreach ($data as $rec) {
        $ip = fw_valid_ip($rec[0]);
        if ($ip !== false) {
            $lines[] = $ip;
        }
    }
    file_put_contents(FW_LIST_FILE, implode("\n", $lines) . "\n", LOCK_EX);

    flock($fh, LOCK_UN);
    fclose($fh);
    return true;
}

/** Next integer id, robust against gaps/empty. */
function fw_next_id(array $data)
{
    if (empty($data)) {
        return 0;
    }
    return max(array_map('intval', array_keys($data))) + 1;
}

/** Is this IP already present under a *different* id? */
function fw_ip_exists(array $data, $ip, $ignore_id = null)
{
    foreach ($data as $id => $rec) {
        if ($ignore_id !== null && (string)$id === (string)$ignore_id) {
            continue;
        }
        if ($rec[0] === $ip) {
            return true;
        }
    }
    return false;
}

/**
 * Push the current list into the firewall via the root helper.
 * Returns true on success. Captures the helper's stderr for diagnostics.
 */
function fw_apply(&$err = null)
{
    $cmd = 'sudo -n ' . escapeshellarg(FW_HELPER) . ' apply 2>&1';
    exec($cmd, $out, $code);
    $err = implode("\n", $out);
    return $code === 0;
}
