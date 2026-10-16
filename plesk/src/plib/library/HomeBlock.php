<?php
// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

/**
 * Block on the administrator's Home page: protection status at a glance and a link to the extension.
 * Loaded asynchronously, so a slow or stopped agent never delays the Home page.
 */
class Modules_Infrafence_HomeBlock extends \Plesk\SDK\Hook\Home\Block
{
    public function getId(): string
    {
        return 'infrafence-status';
    }

    public function getName(): string
    {
        return 'InfraFence';
    }

    public function getTitle(): string
    {
        return 'InfraFence';
    }

    public function getSection(): string
    {
        return self::SECTION_SECURITY;
    }

    public function getIcon(): string
    {
        return pm_Context::getBaseUrl() . 'images/icon-32.png';
    }

    public function getSkeletonSize(): int
    {
        return 2;
    }

    public function getContent(): string
    {
        $status = Modules_Infrafence_Agent::call('status');

        if (!$status['ok']) {
            $key = $status['error'] === 'agent_not_installed' ? 'homeNotInstalled' : 'homeUnavailable';
            return $this->line('warning', pm_Locale::lmsg($key));
        }
        if (empty($status['agent_running'])) {
            return $this->line('danger', pm_Locale::lmsg('homeAgentStopped'));
        }
        if (!empty($status['suspended'])) {
            return $this->line('danger', pm_Locale::lmsg('homeSuspended'));
        }
        if (empty($status['connected'])) {
            return $this->line('warning', pm_Locale::lmsg('homeNotConnected'));
        }

        $html = !empty($status['monitor_mode'])
            ? $this->line('warning', pm_Locale::lmsg('homeMonitorMode'))
            : $this->line('success', pm_Locale::lmsg('homeProtected'));
        $bans = Modules_Infrafence_Agent::call('bans', ['--limit', '1']);
        if ($bans['ok'] && is_int($bans['total'] ?? null)) {
            $html .= '<div class="pul-text pul-text--muted">'
                . $this->escape(pm_Locale::lmsg('homeActiveBans', ['count' => (int)$bans['total']]))
                . '</div>';
        }

        return $html;
    }

    public function getFooter(): string
    {
        return '<a class="pul-link" href="' . $this->escape(pm_Context::getActionUrl('index', 'index')) . '">'
            . $this->escape(pm_Locale::lmsg('homeOpen')) . '</a>';
    }

    private function line(string $intent, string $text): string
    {
        return '<div class="pul-status pul-status--' . $intent . '">' . $this->escape($text) . '</div>';
    }

    private function escape(string $value): string
    {
        return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }
}
