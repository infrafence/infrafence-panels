# Panel ⇄ agent contract (v1)

The WHM and Plesk plugins never talk to the InfraFence API themselves and hold no token. They run one
command, as root, and read JSON from stdout:

    infrafence-agent panel <command> [args] --json

- **WHM:** the CGI runs as root and calls the binary directly.
- **Plesk:** the extension runs as `psaadm`. It calls a root wrapper in `/usr/local/psa/admin/sbin/modules/infrafence/`
  through `pm_ApiCli::callSbin`.
- The command talks to the running agent over its local socket `/run/infrafence/panel.sock`
  (root only, mode 0600). If the agent is not running, the command still answers with `"agent_running": false`.
- Every reply is one JSON object, `{"ok": true, ...}` or `{"ok": false, "error": "<code>", "message": "..."}`.
  The exit code is 0 when `ok` is true. The plugins never parse human text.
- Every command that changes something is logged by the agent and reported to the dashboard as an event
  with `source: "panel"` and the panel user (`--actor`).

## Commands

| Command | What it returns or does |
|---|---|
| `status` | Agent version, running, last heartbeat, connected to InfraFence, agent id, org plan, AutoMode state (read only), dashboard URL for this server; from agent 1.0.35 also the installed plugin's version and the latest plugin release (`plugin_installed`, `plugin_latest`) |
| `bans [--limit N]` | Active bans: ip, reason, source (local, network, automode, manual), created, expires |
| `unban <ip> --actor <user>` | Lifts a ban on the server and reports it, so it is not reapplied |
| `allow <ip> [--note …] --actor <user>` | Adds the address to the server's allow list (never banned again) and reports it |
| `allowlist` / `disallow <ip> --actor <user>` | Lists or removes allow-list entries |
| `findings [--limit N]` | Recent malware and file-integrity findings: path, kind, severity, status, detected; from agent 1.0.34 also subject and state (open, resolved, with when and how) |
| `events [--limit N] [--since …]` | Recent security events (type, severity, source ip, time); from agent 1.0.34 also the subject and, for problem events, the state (open, resolved, with when and how); from agent 1.0.41 also `details` (mailbox, protocol, login method and attempts of mail attacks, CVE, attack type, rule set and site of WAF blocks, database and bind address of an exposed database) |
| `coexistence` | Other security tools found, and what the agent does about each: CSF/lfd, Imunify360, cPHulk, fail2ban, Plesk Firewall, the ModSecurity vendors and rulesets in use, BitNinja, Monarx. `mode` is `coexist` (observe, never fight over iptables) or `primary` |
| `sites` | Hosting accounts and domains seen on the server, with their document roots and scan coverage |
| `scan <path> --actor <user>` | Queues a malware scan of one document root |
| `map [--hours 24\|168]`, `score` | This server's attack map and security score, fetched by the agent from the dashboard and cached (agent 1.0.33) |
| `ssh-logins [--limit N]` | The SSH logins of the last 30 days: users, country, first and last login, imported from the logs and/or seen live, and whether the address is on this server's allow list (agent 1.0.41, answered from the agent's own login history) |
| `db-clients` | The regular clients of the database, cache and admin ports (seen on 3 of the last 7 days) and the declared ones (cPanel Additional MySQL Access Hosts), with first and last seen and whether each is on the allow list (agent 1.0.41, answered from the agent's own client log) |

## Rules for the plugins

- Root/admin only in v1. WHM uses `acls=all`. Plesk uses the administrator only.
- Every action asks for confirmation. Addresses are validated before the command runs, and arguments are
  passed as an argv array, never through a shell string.
- "Open in InfraFence" is a plain link to the server's page on the dashboard. The user logs in normally,
  with 2FA. Single sign-on is phase 2.
- Text in en, it, es, fr, de, pt, matching the dashboard's wording.
