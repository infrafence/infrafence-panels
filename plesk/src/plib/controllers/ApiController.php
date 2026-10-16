<?php
// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

/**
 * JSON endpoints used by the extension UI. Administrator only.
 *
 * Read actions are GET. Actions that change something are POST only, carry Plesk's
 * forgery protection token, and run a preflight before the agent is asked to do anything:
 * the agent must be running, and the target must exist in the agent's current state.
 */
class ApiController extends pm_Controller_Action
{
    protected $_accessLevel = 'admin';

    public function init()
    {
        parent::init();
        $this->_helper->viewRenderer->setNoRender(true);
        $this->_helper->layout()->disableLayout();

        if (!pm_Session::getClient()->isAdmin()) {
            $this->send(Modules_Infrafence_Agent::error('access_denied'), 403);
        }
    }

    public function statusAction()
    {
        $this->requireGet();
        $reply = Modules_Infrafence_Agent::call('status');
        if ($reply['ok']) {
            $reply['dashboard_url'] = Modules_Infrafence_Config::httpsUrl($reply['dashboard_url'] ?? null);
        }
        $this->send($reply);
    }

    public function bansAction()
    {
        $this->requireGet();
        $limit = Modules_Infrafence_Validate::limit($this->getParam('limit'), 500);
        $this->send(Modules_Infrafence_Agent::call('bans', ['--limit', (string)$limit]));
    }

    public function allowlistAction()
    {
        $this->requireGet();
        $this->send(Modules_Infrafence_Agent::call('allowlist'));
    }

    public function findingsAction()
    {
        $this->requireGet();
        $limit = Modules_Infrafence_Validate::limit($this->getParam('limit'), 200);
        $this->send(Modules_Infrafence_Agent::call('findings', ['--limit', (string)$limit]));
    }

    public function eventsAction()
    {
        $this->requireGet();
        $args = ['--limit', (string)Modules_Infrafence_Validate::limit($this->getParam('limit'), 100)];
        $since = $this->getParam('since');
        if (is_string($since) && preg_match('/^\d{1,4}[smhd]$/', $since)) {
            array_push($args, '--since', $since);
        }
        $this->send(Modules_Infrafence_Agent::call('events', $args));
    }

    public function coexistenceAction()
    {
        $this->requireGet();
        $this->send(Modules_Infrafence_Agent::call('coexistence'));
    }

    public function sitesAction()
    {
        $this->requireGet();
        $reply = Modules_Infrafence_Agent::call('sites');
        if (!$reply['ok'] && ($reply['error'] ?? '') !== 'agent_not_running') {
            $this->send($reply);
            return;
        }
        $this->send([
            'ok' => true,
            'agent_running' => $reply['ok'],
            'sites' => $this->mergeSites($reply['ok'] ? ($reply['sites'] ?? []) : [], $reply['ok']),
        ]);
    }

    public function unbanAction()
    {
        $body = $this->requirePost();
        $ip = Modules_Infrafence_Validate::ip($body['ip'] ?? null);
        if ($ip === null) {
            $this->send(Modules_Infrafence_Agent::error('invalid_ip'), 400);
            return;
        }
        $alsoAllow = !empty($body['allow']);
        $note = Modules_Infrafence_Validate::note($body['note'] ?? '');
        if ($note === null) {
            $this->send(Modules_Infrafence_Agent::error('invalid_note'), 400);
            return;
        }

        $bans = $this->preflight('bans', ['--limit', '1000']);
        if ($bans === null) {
            return;
        }
        $listed = false;
        foreach ($bans['bans'] ?? [] as $ban) {
            if (is_string($ban['ip'] ?? null) && Modules_Infrafence_Validate::matches($ip, $ban['ip'])) {
                $listed = true;
                break;
            }
        }
        if (!$listed) {
            $this->send(Modules_Infrafence_Agent::error('not_banned'), 409);
            return;
        }

        $actor = Modules_Infrafence_Agent::actor();
        $reply = Modules_Infrafence_Agent::call('unban', [$ip, '--actor', $actor]);
        if ($reply['ok']) {
            $this->log('ip_unbanned', $ip);
            if ($alsoAllow) {
                $allow = Modules_Infrafence_Agent::call('allow', $this->allowArgs($ip, $note, $actor));
                $reply['allowed'] = $allow['ok'];
                if ($allow['ok']) {
                    $this->log('ip_allowed', $ip);
                } else {
                    $reply['allow_error'] = $allow['error'];
                }
            }
        }
        $this->send($reply);
    }

    public function allowAction()
    {
        $body = $this->requirePost();
        $target = Modules_Infrafence_Validate::allowTarget($body['ip'] ?? null, $reason);
        if ($target === null) {
            $this->send(Modules_Infrafence_Agent::error($reason), 400);
            return;
        }
        $note = Modules_Infrafence_Validate::note($body['note'] ?? '');
        if ($note === null) {
            $this->send(Modules_Infrafence_Agent::error('invalid_note'), 400);
            return;
        }

        $list = $this->preflight('allowlist');
        if ($list === null) {
            return;
        }
        foreach ($list['entries'] ?? [] as $entry) {
            if (is_string($entry['ip'] ?? null) && Modules_Infrafence_Validate::matches($target, $entry['ip'])) {
                $this->send(Modules_Infrafence_Agent::error('already_allowed') + ['entry' => $entry['ip']], 409);
                return;
            }
        }

        $reply = Modules_Infrafence_Agent::call('allow', $this->allowArgs($target, $note, Modules_Infrafence_Agent::actor()));
        if ($reply['ok']) {
            $this->log('ip_allowed', $target);
        }
        $this->send($reply);
    }

    public function disallowAction()
    {
        $body = $this->requirePost();
        $target = is_string($body['ip'] ?? null) ? trim($body['ip']) : '';

        $list = $this->preflight('allowlist');
        if ($list === null) {
            return;
        }
        // Only an exact entry of the current list can be removed.
        $found = null;
        foreach ($list['entries'] ?? [] as $entry) {
            if (($entry['ip'] ?? null) === $target) {
                $found = $target;
                break;
            }
        }
        if ($found === null || !Modules_Infrafence_Validate::isAddressOrNetwork($found)) {
            $this->send(Modules_Infrafence_Agent::error('not_allowed'), 409);
            return;
        }

        $reply = Modules_Infrafence_Agent::call('disallow', [$found, '--actor', Modules_Infrafence_Agent::actor()]);
        if ($reply['ok']) {
            $this->log('ip_disallowed', $found);
        }
        $this->send($reply);
    }

    public function scanAction()
    {
        $body = $this->requirePost();
        $docroot = is_string($body['docroot'] ?? null) ? $body['docroot'] : '';

        $sites = $this->preflight('sites');
        if ($sites === null) {
            return;
        }
        $known = null;
        foreach ($this->mergeSites($sites['sites'] ?? []) as $site) {
            if ($site['docroot'] === $docroot) {
                $known = $site;
                break;
            }
        }
        if ($known === null) {
            $this->send(Modules_Infrafence_Agent::error('unknown_docroot'), 409);
            return;
        }
        if (in_array($known['scan_status'], ['queued', 'scanning'], true)) {
            $this->send(Modules_Infrafence_Agent::error('scan_in_progress'), 409);
            return;
        }

        $reply = Modules_Infrafence_Agent::call('scan', [$docroot, '--actor', Modules_Infrafence_Agent::actor()]);
        if ($reply['ok']) {
            $this->log('scan_queued', $known['domain'] ?: $docroot);
        }
        $this->send($reply);
    }

    /**
     * Checks that the agent is running and connected enough to act, and returns a fresh
     * reply of $command to check the target against. Sends the error and returns null otherwise.
     */
    private function preflight(string $command, array $args = []): ?array
    {
        $status = Modules_Infrafence_Agent::call('status');
        if (!$status['ok']) {
            $this->send($status, 503);
            return null;
        }
        if (empty($status['agent_running'])) {
            $this->send(Modules_Infrafence_Agent::error('agent_not_running'), 503);
            return null;
        }
        $reply = Modules_Infrafence_Agent::call($command, $args);
        if (!$reply['ok']) {
            $this->send($reply, 503);
            return null;
        }

        return $reply;
    }

    private function allowArgs(string $target, string $note, string $actor): array
    {
        $args = [$target];
        if ($note !== '') {
            array_push($args, '--note', $note);
        }
        array_push($args, '--actor', $actor);

        return $args;
    }

    /**
     * Joins the agent's view of sites with the domains Plesk hosts, so that domains the agent
     * does not cover yet are visible too.
     */
    private function mergeSites(array $agentSites, bool $agentAnswered = true): array
    {
        $byRoot = [];
        foreach ($agentSites as $site) {
            if (!is_array($site) || !is_string($site['docroot'] ?? null)) {
                continue;
            }
            $byRoot[rtrim($site['docroot'], '/')] = [
                'domain' => (string)($site['domain'] ?? ''),
                'account' => (string)($site['account'] ?? ''),
                'docroot' => rtrim($site['docroot'], '/'),
                'coverage' => (string)($site['coverage'] ?? 'none'),
                'scan_status' => (string)($site['scan_status'] ?? 'never'),
                'last_scan' => $site['last_scan'] ?? null,
                'files' => $site['files'] ?? null,
                'in_plesk' => false,
                'seen_by_agent' => true,
            ];
        }

        try {
            $domains = pm_Domain::getAllDomains();
        } catch (Exception $e) {
            $domains = [];
        }
        foreach ($domains as $domain) {
            try {
                if (!$domain->hasHosting()) {
                    continue;
                }
                $root = rtrim((string)$domain->getDocumentRoot(), '/');
                $name = (string)$domain->getDisplayName();
                $account = (string)$domain->getSysUserLogin();
            } catch (Exception $e) {
                continue;
            }
            if ($root === '') {
                continue;
            }
            if (isset($byRoot[$root])) {
                $byRoot[$root]['in_plesk'] = true;
                $byRoot[$root]['domain'] = $byRoot[$root]['domain'] ?: $name;
                continue;
            }
            $byRoot[$root] = [
                'domain' => $name,
                'account' => $account,
                'docroot' => $root,
                'coverage' => $agentAnswered ? 'not_seen' : 'unknown',
                'scan_status' => 'never',
                'last_scan' => null,
                'files' => null,
                'in_plesk' => true,
                'seen_by_agent' => false,
            ];
        }

        $sites = array_values($byRoot);
        usort($sites, function ($a, $b) {
            return strcmp($a['domain'], $b['domain']);
        });

        return $sites;
    }

    private function log(string $event, string $target): void
    {
        try {
            pm_ActionLog::submit($event, 0, [], ['target' => $target]);
        } catch (Exception $e) {
            pm_Log::warn('InfraFence: could not write to the Plesk action log: ' . $e->getMessage());
        }
    }

    private function requireGet(): void
    {
        if (!$this->getRequest()->isGet()) {
            $this->send(Modules_Infrafence_Agent::error('method_not_allowed'), 405);
        }
    }

    /**
     * Changes are accepted only as POST from the extension's own page: an XHR with Plesk's
     * forgery protection token, which Plesk checks for every POST to the panel.
     */
    private function requirePost(): array
    {
        $request = $this->getRequest();
        if (!$request->isPost() || !$request->isXmlHttpRequest()) {
            $this->send(Modules_Infrafence_Agent::error('method_not_allowed'), 405);
        }
        $token = (string)$request->getHeader('X-Forgery-Protection-Token');
        if ($token === '') {
            $this->send(Modules_Infrafence_Agent::error('csrf_token_missing'), 403);
        }
        $body = json_decode((string)$request->getRawBody(), true);

        return is_array($body) ? $body : [];
    }

    private function send(array $data, int $status = 200): void
    {
        $response = $this->getResponse();
        $response->setHttpResponseCode($status);
        $response->setHeader('Content-Type', 'application/json; charset=utf-8', true);
        $response->setHeader('Cache-Control', 'no-store', true);
        $response->setBody(json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));
        $response->sendResponse();
        exit;
    }
}
