<?php
// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

/**
 * Client for `infrafence-agent panel <command> --json`.
 *
 * The extension runs as psaadm, so every call goes through the root wrapper in
 * sbin/infrafence-panel, with the arguments as an array (never a shell string).
 * Replies are documented in docs/panel-json.md: one JSON object with "ok" true or false, and on
 * failure {"ok": false, "error": <code>, "message": <English, for logs>}.
 */
class Modules_Infrafence_Agent
{
    const WRAPPER = 'infrafence-panel';

    const READ_COMMANDS = ['status', 'bans', 'allowlist', 'findings', 'events', 'coexistence', 'sites'];
    const WRITE_COMMANDS = ['unban', 'allow', 'disallow', 'scan'];

    /**
     * Runs one contract command and returns the decoded reply.
     * Never throws: failures come back as ['ok' => false, 'error' => <code>].
     */
    public static function call(string $command, array $args = []): array
    {
        if (!in_array($command, array_merge(self::READ_COMMANDS, self::WRITE_COMMANDS), true)) {
            return self::error('unknown_command');
        }
        foreach ($args as $arg) {
            if (!is_string($arg) || strpbrk($arg, "\0\r\n") !== false) {
                return self::error('invalid_arguments');
            }
        }

        try {
            $result = pm_ApiCli::callSbin(self::WRAPPER, array_merge([$command], $args), pm_ApiCli::RESULT_FULL);
        } catch (Exception $e) {
            pm_Log::err('InfraFence wrapper call failed: ' . $e->getMessage());
            return self::error('wrapper_failed');
        }

        $code = (int)($result['code'] ?? -1);
        $stdout = trim((string)($result['stdout'] ?? ''));

        if ($stdout === '') {
            // timeout(1) exits with 124 when the agent does not answer in time.
            return self::error($code === 124 || $code === 137 ? 'agent_timeout' : 'bad_reply');
        }

        $reply = json_decode($stdout, true);
        if (!is_array($reply) || !array_key_exists('ok', $reply)) {
            pm_Log::err("InfraFence agent returned a reply that is not contract JSON (exit $code)");
            return self::error('bad_reply');
        }
        if ($reply['ok'] !== true) {
            $reply['ok'] = false;
            $reply['error'] = is_string($reply['error'] ?? null) ? $reply['error'] : 'internal_error';
            if (is_string($reply['message'] ?? null)) {
                pm_Log::info("InfraFence agent: $command: {$reply['error']}: {$reply['message']}");
            }
        }

        return $reply;
    }

    public static function error(string $code): array
    {
        return ['ok' => false, 'error' => $code];
    }

    /**
     * The Plesk login passed to the agent as --actor (1-64 of A-Z a-z 0-9 . _ @ - +).
     */
    public static function actor(): string
    {
        $login = preg_replace('/[^A-Za-z0-9._@+-]/', '_', (string)pm_Session::getClient()->getLogin());
        $login = substr(ltrim($login, '-'), 0, 64);

        return $login !== '' ? $login : 'admin';
    }
}
