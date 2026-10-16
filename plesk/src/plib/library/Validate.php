<?php
// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

/**
 * Input checks run before anything is sent to the agent. The wrapper and the agent check again.
 */
class Modules_Infrafence_Validate
{
    const MIN_PREFIX_V4 = 16;
    const MIN_PREFIX_V6 = 48;
    const NOTE_MAX = 200;

    /**
     * Returns the normalized address, or null if it is not a single public-format IPv4/IPv6 address.
     */
    public static function ip($value): ?string
    {
        if (!is_string($value)) {
            return null;
        }
        $value = trim($value);
        if ($value === '' || strlen($value) > 45 || filter_var($value, FILTER_VALIDATE_IP) === false) {
            return null;
        }

        return inet_ntop(inet_pton($value));
    }

    /**
     * Returns the normalized address or network for the allow list, or null.
     * Networks wider than /16 (IPv4) or /48 (IPv6) are refused, as are unusable addresses.
     */
    public static function allowTarget($value, ?string &$reason = null): ?string
    {
        $reason = 'invalid_ip';
        if (!is_string($value)) {
            return null;
        }
        $value = trim($value);
        $prefix = null;
        if (strpos($value, '/') !== false) {
            [$value, $prefix] = explode('/', $value, 2);
            if (!preg_match('/^\d{1,3}$/', $prefix)) {
                return null;
            }
            $prefix = (int)$prefix;
        }
        $ip = self::ip($value);
        if ($ip === null) {
            return null;
        }
        $v6 = strpos($ip, ':') !== false;
        $bits = $v6 ? 128 : 32;

        if (self::isUnusable($ip)) {
            $reason = 'unusable_ip';
            return null;
        }
        if ($prefix === null || $prefix === $bits) {
            return $ip;
        }
        if ($prefix > $bits) {
            return null;
        }
        if ($prefix < ($v6 ? self::MIN_PREFIX_V6 : self::MIN_PREFIX_V4)) {
            $reason = 'network_too_wide';
            return null;
        }

        return self::networkAddress($ip, $prefix) . '/' . $prefix;
    }

    /**
     * Unspecified, loopback and multicast addresses never belong in an allow list.
     */
    public static function isUnusable(string $ip): bool
    {
        $bin = inet_pton($ip);
        if (strlen($bin) === 4) {
            $first = ord($bin[0]);
            return $first === 0 || $first === 127 || $first >= 224;
        }

        return $ip === '::' || $ip === '::1' || ord($bin[0]) === 0xff;
    }

    public static function networkAddress(string $ip, int $prefix): string
    {
        $bin = inet_pton($ip);
        $out = '';
        for ($i = 0; $i < strlen($bin); $i++) {
            $keep = max(0, min(8, $prefix - $i * 8));
            $mask = $keep === 0 ? 0 : (0xff << (8 - $keep)) & 0xff;
            $out .= chr(ord($bin[$i]) & $mask);
        }

        return inet_ntop($out);
    }

    /**
     * True if $ip is $entry, or falls inside it when $entry is a network.
     */
    public static function matches(string $ip, string $entry): bool
    {
        if (strpos($entry, '/') === false) {
            $a = self::ip($ip);
            $b = self::ip($entry);
            return $a !== null && $a === $b;
        }
        [$net, $prefix] = explode('/', $entry, 2);
        $ipBin = @inet_pton(strpos($ip, '/') === false ? $ip : explode('/', $ip, 2)[0]);
        $netBin = @inet_pton($net);
        if ($ipBin === false || $netBin === false || strlen($ipBin) !== strlen($netBin)) {
            return false;
        }

        return self::networkAddress(inet_ntop($ipBin), (int)$prefix) === self::networkAddress($net, (int)$prefix);
    }

    /**
     * Shape check for an existing allow-list entry: an address, or an address with a prefix length.
     */
    public static function isAddressOrNetwork(string $value): bool
    {
        $parts = explode('/', $value, 2);
        $ip = self::ip($parts[0]);
        if ($ip === null) {
            return false;
        }
        if (count($parts) === 1) {
            return true;
        }

        return preg_match('/^\d{1,3}$/', $parts[1]) && (int)$parts[1] <= (strpos($ip, ':') === false ? 32 : 128);
    }

    public static function note($value): ?string
    {
        if ($value === null || $value === '') {
            return '';
        }
        if (!is_string($value)) {
            return null;
        }
        $value = trim(preg_replace('/\s+/u', ' ', $value));
        if (!mb_check_encoding($value, 'UTF-8') || mb_strlen($value) > self::NOTE_MAX || preg_match('/[\p{Cc}]/u', $value)) {
            return null;
        }

        return ltrim($value, '-');
    }

    public static function limit($value, int $default, int $max = 1000): int
    {
        $n = filter_var($value, FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => $max]]);

        return $n === false ? $default : $n;
    }
}
