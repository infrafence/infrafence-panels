<?php
// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

class Modules_Infrafence_ActionLog extends pm_Hook_ActionLog
{
    public function getEvents()
    {
        return [
            'ip_unbanned' => pm_Locale::lmsg('actionLogUnbanned'),
            'ip_allowed' => pm_Locale::lmsg('actionLogAllowed'),
            'ip_disallowed' => pm_Locale::lmsg('actionLogDisallowed'),
            'scan_queued' => pm_Locale::lmsg('actionLogScanQueued'),
        ];
    }
}
