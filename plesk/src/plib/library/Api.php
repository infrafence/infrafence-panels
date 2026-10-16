<?php
// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

/**
 * The JSON API behind the extension UI, served by htdocs/api.php after Plesk's SDK middleware has
 * checked the session, the administrator role and, for POST, the forgery protection token.
 *
 * Read actions are GET and return the agent's reply as it is (docs/panel-json.md). Actions that
 * change something are POST only and run a preflight before the agent is asked to do anything:
 * the agent must be running, and the target must exist in the agent's current state.
 */
class Modules_Infrafence_Api
{
    /** The agent lists at most this many bans, findings or events per reply. */
    const MAX_LIMIT = 500;

    const READ = ['status', 'bans', 'allowlist', 'findings', 'events', 'coexistence', 'sites'];
    const WRITE = ['unban', 'allow', 'disallow', 'scan'];

    /**
     * Returns [HTTP status, JSON body].
     */
    public function handle(string $method, string $action, array $query, array $body): array
    {
        try {
            if (!pm_Session::getClient()->isAdmin()) {
                throw Modules_Infrafence_ApiError::code(403, 'access_denied');
            }
            if (in_array($action, self::READ, true)) {
                if ($method !== 'GET') {
                    throw Modules_Infrafence_ApiError::code(405, 'method_not_allowed');
                }
                return [200, $this->{$action}($query)];
            }
            if (in_array($action, self::WRITE, true)) {
                if ($method !== 'POST') {
                    throw Modules_Infrafence_ApiError::code(405, 'method_not_allowed');
                }
                return [200, $this->{$action}($body)];
            }
            throw Modules_Infrafence_ApiError::code(404, 'unknown_command');
        } catch (Modules_Infrafence_ApiError $e) {
            return [$e->getCode(), $e->data];
        }
    }

    private function status(array $query): array
    {
        $reply = Modules_Infrafence_Agent::call('status');
        if ($reply['ok']) {
            $reply['dashboard_url'] = Modules_Infrafence_Config::httpsUrl($reply['dashboard_url'] ?? null);
        }

        return $reply;
    }

    private function bans(array $query): array
    {
        $limit = Modules_Infrafence_Validate::limit($query['limit'] ?? null, self::MAX_LIMIT);

        return Modules_Infrafence_Agent::call('bans', ['--limit', (string)$limit]);
    }

    private function allowlist(array $query): array
    {
        return Modules_Infrafence_Agent::call('allowlist');
    }

    private function findings(array $query): array
    {
        $limit = Modules_Infrafence_Validate::limit($query['limit'] ?? null, self::MAX_LIMIT);

        return Modules_Infrafence_Agent::call('findings', ['--limit', (string)$limit]);
    }

    private function events(array $query): array
    {
        $args = ['--limit', (string)Modules_Infrafence_Validate::limit($query['limit'] ?? null, self::MAX_LIMIT)];
        $since = $query['since'] ?? null;
        if (is_string($since) && in_array($since, ['24h', '7d', '30d'], true)) {
            array_push($args, '--since', $since);
        }

        return Modules_Infrafence_Agent::call('events', $args);
    }

    private function coexistence(array $query): array
    {
        return Modules_Infrafence_Agent::call('coexistence');
    }

    private function sites(array $query): array
    {
        return Modules_Infrafence_Agent::call('sites');
    }

    private function unban(array $body): array
    {
        $ip = $this->ip($body);
        $alsoAllow = !empty($body['allow']);
        $note = $this->note($body);

        $bans = $this->preflight('bans', ['--limit', (string)self::MAX_LIMIT]);
        $listed = false;
        foreach ($bans['bans'] ?? [] as $ban) {
            if (Modules_Infrafence_Validate::ip($ban['ip'] ?? null) === $ip) {
                $listed = true;
                break;
            }
        }
        // Only the first 500 bans are listed; beyond that the agent decides.
        if (!$listed && (int)($bans['total'] ?? 0) <= count($bans['bans'] ?? [])) {
            throw Modules_Infrafence_ApiError::code(409, 'not_banned');
        }

        $actor = Modules_Infrafence_Agent::actor();
        $reply = Modules_Infrafence_Agent::call('unban', [$ip, '--actor', $actor]);
        if ($reply['ok']) {
            $this->log('ip_unbanned', $ip);
            if ($alsoAllow) {
                $reply['allow'] = Modules_Infrafence_Agent::call('allow', $this->allowArgs($ip, $note, $actor));
                if ($reply['allow']['ok'] && empty($reply['allow']['already'])) {
                    $this->log('ip_allowed', $ip);
                }
            }
        }

        return $reply;
    }

    private function allow(array $body): array
    {
        $ip = $this->ip($body);
        $note = $this->note($body);
        $this->preflight();

        // The agent answers "already": true, and changes nothing, if the address is allowed already.
        $reply = Modules_Infrafence_Agent::call('allow', $this->allowArgs($ip, $note, Modules_Infrafence_Agent::actor()));
        if ($reply['ok'] && empty($reply['already'])) {
            $this->log('ip_allowed', $ip);
        }

        return $reply;
    }

    private function disallow(array $body): array
    {
        $ip = $this->ip($body);

        $list = $this->preflight('allowlist');
        $entry = null;
        foreach ($list['allowlist'] ?? [] as $candidate) {
            if (($candidate['address'] ?? null) === $ip) {
                $entry = $candidate;
                break;
            }
        }
        if ($entry === null) {
            throw Modules_Infrafence_ApiError::code(409, 'not_in_allowlist');
        }
        if (($entry['source'] ?? null) !== 'panel') {
            throw Modules_Infrafence_ApiError::code(409, 'managed_by_dashboard');
        }

        $reply = Modules_Infrafence_Agent::call('disallow', [$ip, '--actor', Modules_Infrafence_Agent::actor()]);
        if ($reply['ok']) {
            $this->log('ip_disallowed', $ip);
        }

        return $reply;
    }

    private function scan(array $body): array
    {
        $root = is_string($body['document_root'] ?? null) ? $body['document_root'] : '';

        $sites = $this->preflight('sites');
        $site = null;
        foreach ($sites['sites'] ?? [] as $candidate) {
            if ($root !== '' && ($candidate['document_root'] ?? null) === $root) {
                $site = $candidate;
                break;
            }
        }
        if ($site === null) {
            throw Modules_Infrafence_ApiError::code(409, 'not_a_document_root');
        }
        if (empty($site['scannable'])) {
            throw Modules_Infrafence_ApiError::code(409, 'not_scannable');
        }

        $reply = Modules_Infrafence_Agent::call('scan', [$root, '--actor', Modules_Infrafence_Agent::actor()]);
        if ($reply['ok']) {
            $this->log('scan_queued', (string)($site['domain'] ?? $root));
        }

        return $reply;
    }

    /**
     * Checks that the agent is running, and returns a fresh reply of $command to check the target
     * against (or the status reply).
     */
    private function preflight(?string $command = null, array $args = []): array
    {
        $status = Modules_Infrafence_Agent::call('status');
        if (!$status['ok']) {
            throw new Modules_Infrafence_ApiError(503, $status);
        }
        if (empty($status['agent_running'])) {
            throw new Modules_Infrafence_ApiError(503, ['agent_running' => false] + Modules_Infrafence_Agent::error('agent_not_running'));
        }
        if ($command === null) {
            return $status;
        }
        $reply = Modules_Infrafence_Agent::call($command, $args);
        if (!$reply['ok']) {
            throw new Modules_Infrafence_ApiError(503, $reply);
        }

        return $reply;
    }

    private function ip(array $body): string
    {
        $ip = Modules_Infrafence_Validate::ip($body['ip'] ?? null);
        if ($ip === null) {
            throw Modules_Infrafence_ApiError::code(400, 'invalid_ip');
        }

        return $ip;
    }

    private function note(array $body): string
    {
        $note = Modules_Infrafence_Validate::note($body['note'] ?? '');
        if ($note === null) {
            throw Modules_Infrafence_ApiError::code(400, 'invalid_note');
        }

        return $note;
    }

    private function allowArgs(string $ip, string $note, string $actor): array
    {
        $args = [$ip];
        if ($note !== '') {
            array_push($args, '--note', $note);
        }
        array_push($args, '--actor', $actor);

        return $args;
    }

    private function log(string $event, string $target): void
    {
        try {
            pm_ActionLog::submit($event, 0, [], ['target' => $target]);
        } catch (Exception $e) {
            pm_Log::warn('InfraFence: could not write to the Plesk action log: ' . $e->getMessage());
        }
    }
}
