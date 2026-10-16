<?php
// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

class Modules_Infrafence_Navigation extends pm_Hook_Navigation
{
    public function getNavigation()
    {
        return [
            [
                'controller' => 'index',
                'action' => 'index',
                'label' => pm_Locale::lmsg('pageTitle'),
                'pages' => [],
            ],
        ];
    }
}
