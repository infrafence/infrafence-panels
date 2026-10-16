<?php
// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

/**
 * Settings that can be overridden in panel.ini, section [ext-infrafence]:
 *
 *     [ext-infrafence]
 *     installCommand = "curl -fsSL https://get.infrafence.com | sudo bash"
 *     dashboardUrl = "https://app.infrafence.com"
 */
class Modules_Infrafence_Config
{
    const DEFAULT_INSTALL_COMMAND = 'curl -fsSL https://get.infrafence.com | sudo bash';
    const DEFAULT_DASHBOARD_URL = 'https://app.infrafence.com';

    public static function installCommand(): string
    {
        return (string)pm_Config::get('installCommand', self::DEFAULT_INSTALL_COMMAND);
    }

    public static function dashboardUrl(): string
    {
        return self::httpsUrl((string)pm_Config::get('dashboardUrl', self::DEFAULT_DASHBOARD_URL))
            ?? self::DEFAULT_DASHBOARD_URL;
    }

    /**
     * Only plain https links are ever rendered as "Open in InfraFence".
     */
    public static function httpsUrl($url): ?string
    {
        if (!is_string($url) || strlen($url) > 2048 || !preg_match('#^https://[A-Za-z0-9.-]+(:\d+)?(/[^\s"\'<>]*)?$#', $url)) {
            return null;
        }

        return $url;
    }
}
