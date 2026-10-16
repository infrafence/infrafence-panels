<?php
// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

/**
 * Settings that can be overridden in panel.ini, section [ext-infrafence]:
 *
 *     [ext-infrafence]
 *     addServerUrl = "https://infrafence.com/add-server"
 */
class Modules_Infrafence_Config
{
    const DEFAULT_ADD_SERVER_URL = 'https://infrafence.com/add-server';

    /**
     * Where the "agent not installed" screen sends the administrator to add this server.
     */
    public static function addServerUrl(): string
    {
        return self::httpsUrl(pm_Config::get('addServerUrl', self::DEFAULT_ADD_SERVER_URL))
            ?? self::DEFAULT_ADD_SERVER_URL;
    }

    /**
     * Only plain https links are ever rendered.
     */
    public static function httpsUrl($url): ?string
    {
        if (!is_string($url) || strlen($url) > 2048 || !preg_match('#^https://[A-Za-z0-9.-]+(:\d+)?(/[^\s"\'<>]*)?\z#', $url)) {
            return null;
        }

        return $url;
    }
}
