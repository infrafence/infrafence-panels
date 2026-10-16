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

    /** The wrapper's own limit for one agent call, in seconds. */
    const CALL_TIMEOUT = 25;
    /** Below this many seconds left, a call is not started. */
    const MIN_CALL_TIME = 2;

    /** @var float|null Shared deadline (microtime) for all the calls of the current request. */
    private static $deadline = null;

    /**
     * Sets one deadline for every following call: each call gets the time that is left (at most
     * 25 seconds), so a request that makes several calls still ends before PHP's time limit.
     */
    public static function setDeadline(float $deadline): void
    {
        self::$deadline = $deadline;
    }

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

        $timeout = self::CALL_TIMEOUT;
        if (self::$deadline !== null) {
            $timeout = (int)min(self::CALL_TIMEOUT, floor(self::$deadline - microtime(true)));
            if ($timeout < self::MIN_CALL_TIME) {
                return self::error('agent_timeout');
            }
        }

        try {
            $result = pm_ApiCli::callSbin(
                self::WRAPPER,
                array_merge(['--timeout', (string)$timeout, $command], $args),
                pm_ApiCli::RESULT_FULL
            );
        } catch (Exception $e) {
            pm_Log::err('InfraFence wrapper call failed: ' . self::forLog($e->getMessage()));
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
                pm_Log::info('InfraFence agent: ' . $command . ': ' . self::forLog($reply['error']) . ': ' . self::forLog($reply['message']));
            }
        }

        return $reply;
    }

    /**
     * Text from the agent for the Plesk log: control characters (newlines included) are replaced,
     * so a reply can never forge or split log lines; capped in length.
     */
    private static function forLog(string $text): string
    {
        $text = preg_replace('/[\x00-\x1F\x7F]|\xC2[\x80-\x9F]/', ' ', $text);

        return mb_strimwidth((string)$text, 0, 300, '...', 'UTF-8');
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
