<?php
// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

/**
 * The extension page. The screens are rendered by the bundled UI (htdocs/dist/main.js), built on the
 * Plesk UI library that Plesk itself provides, so they follow the panel's theme.
 */
class IndexController extends pm_Controller_Action
{
    protected $_accessLevel = 'admin';

    const SCREENS = ['overview', 'bans', 'allowlist', 'findings', 'events', 'coexistence', 'domains'];

    public function init()
    {
        parent::init();
        $this->view->pageTitle = 'InfraFence';
    }

    public function indexAction()
    {
        $screen = $this->getParam('screen');
        $baseUrl = pm_Context::getBaseUrl();

        $this->view->mountId = 'infrafence-app';
        $this->view->scriptUrl = $baseUrl . 'dist/main.js?v=' . rawurlencode(pm_Context::getModuleInfo()->version ?? '1');
        $this->view->stylesheetUrl = $baseUrl . 'css/infrafence.css?v=' . rawurlencode(pm_Context::getModuleInfo()->version ?? '1');
        $this->view->params = [
            'mountId' => 'infrafence-app',
            'apiUrl' => $baseUrl . 'api.php',
            'screen' => in_array($screen, self::SCREENS, true) ? $screen : 'overview',
            'locale' => pm_Locale::getCode(),
            'messages' => Modules_Infrafence_Messages::forUi(),
            'addServerUrl' => Modules_Infrafence_Config::addServerUrl(),
            'actor' => Modules_Infrafence_Agent::actor(),
        ];
    }
}
