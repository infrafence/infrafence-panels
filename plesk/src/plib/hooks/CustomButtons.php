<?php
// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

class Modules_Infrafence_CustomButtons extends pm_Hook_CustomButtons
{
    public function getButtons()
    {
        $common = [
            'title' => pm_Locale::lmsg('buttonTitle'),
            'description' => pm_Locale::lmsg('buttonDescription'),
            'link' => pm_Context::getActionUrl('index', 'index'),
            'newWindow' => false,
            'visibility' => [$this, 'isVisible'],
        ];

        return [
            $common + [
                'place' => self::PLACE_ADMIN_HOME,
                'icon' => pm_Context::getBaseUrl() . 'images/icon-64.png',
            ],
            $common + [
                'place' => self::PLACE_ADMIN_NAVIGATION,
                'section' => self::SECTION_NAV_SERVER_MANAGEMENT,
                'icon' => pm_Context::getBaseUrl() . 'images/icon-16.png',
            ],
        ];
    }

    public function isVisible()
    {
        return pm_Session::isExist() && pm_Session::getClient()->isAdmin();
    }
}
