<?php
// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

/**
 * UI strings for the browser: the "ui" section of the locale files, flattened to dotted keys.
 *
 * Read through pm_Locale only. Plesk loads the locale files itself, once per request, so
 * including them here would leave the extension without its strings for the rest of the request.
 * Every locale file has every key (dev/check-locales.php checks this at build time).
 */
class Modules_Infrafence_Messages
{
    public static function forUi(): array
    {
        $section = pm_Locale::getSection('ui');

        return is_array($section) ? self::flatten($section) : [];
    }

    private static function flatten(array $tree, string $prefix = ''): array
    {
        $flat = [];
        foreach ($tree as $key => $value) {
            if (is_array($value)) {
                $flat += self::flatten($value, $prefix . $key . '.');
            } else {
                $flat[$prefix . $key] = (string)$value;
            }
        }

        return $flat;
    }
}
