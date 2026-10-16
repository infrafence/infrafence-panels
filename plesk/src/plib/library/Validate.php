<?php
// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

/**
 * Input checks run before anything is sent to the agent. The wrapper and the agent check again.
 */
class Modules_Infrafence_Validate
{
    const NOTE_MAX_BYTES = 200;

    /**
     * Returns the canonical form of one IPv4 or IPv6 address, or null. Refused like the agent does:
     * ranges, ports, zones, the unspecified addresses, broadcast and multicast.
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
        $bin = inet_pton($value);
        if (strlen($bin) === 16 && substr($bin, 0, 12) === "\0\0\0\0\0\0\0\0\0\0\xff\xff") {
            $bin = substr($bin, 12);
        }
        $ip = inet_ntop($bin);
        if ($ip === '0.0.0.0' || $ip === '::' || $ip === '255.255.255.255') {
            return null;
        }
        if (strlen($bin) === 4 ? (ord($bin[0]) & 0xf0) === 0xe0 : ord($bin[0]) === 0xff) {
            return null;
        }

        return $ip;
    }

    /**
     * Returns the note to send ('' for none), or null if it is not up to 200 bytes of printable text.
     */
    public static function note($value): ?string
    {
        if ($value === null || $value === '') {
            return '';
        }
        if (!is_string($value) || !mb_check_encoding($value, 'UTF-8')) {
            return null;
        }
        $value = ltrim(trim(preg_replace('/[ \t]+/u', ' ', $value)), '-');
        if (strlen($value) > self::NOTE_MAX_BYTES || preg_match('/[\p{Cc}]/u', $value)) {
            return null;
        }

        return $value;
    }

    public static function limit($value, int $default, int $max = 500): int
    {
        $n = filter_var($value, FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => $max]]);

        return $n === false ? $default : $n;
    }
}
