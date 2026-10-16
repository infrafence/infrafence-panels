# InfraFence for Plesk

A Plesk Obsidian extension (18.0.60 or later, Linux) that shows the InfraFence agent running on the
server, inside Plesk, for the administrator:

| Screen | What it shows | Actions |
|---|---|---|
| Overview | Protection status, agent version and heartbeat, connection, plan, AutoMode (read only), counts | Open in InfraFence |
| Bans | Active bans: address, reason, who banned it, when, expiry | Unban, Unban and allow |
| Allow list | Entries, note, who added them | Add address or network, Remove |
| Findings | Malware and file integrity findings | Manage in InfraFence (link) |
| Events | Recent security events, last 24 hours / 7 / 30 days | |
| Coexistence | fail2ban, Plesk Firewall, ModSecurity and its ruleset, Imunify360, BitNinja, Monarx, CSF/lfd, cPHulk, and what InfraFence does about each | |
| Domains | Plesk domains joined with the agent's scan coverage | Scan now |

When the agent is missing, the extension shows a single screen with the one-line install command.
It also adds a button on the Home page and in the left navigation, a status block on the Home page
(Security section of Customize), and Plesk Action Log events for every change.

Text is in en-US, it-IT, es-ES, fr-FR, de-DE, pt-PT and pt-BR.

![Overview](src/_meta/screenshots/1.png)

## How it works

```
browser ──(Plesk session, admin only, CSRF token)──▶ plib/controllers/ApiController.php   runs as psaadm
                                                          │ pm_ApiCli::callSbin('infrafence-panel', [argv…])
                                                          ▼
                                   /usr/local/psa/admin/sbin/modules/infrafence/infrafence-panel   root
                                                          │ validates, clears the environment, exec (no shell)
                                                          ▼
                                   infrafence-agent panel <command> [args] --json      (docs/panel-contract.md)
```

- **Administrator only.** Every controller has `$_accessLevel = 'admin'` and checks the session again;
  hooks only use administrator places. Customers and resellers are turned away by Plesk.
- **Changes are POST only**, sent with Plesk's forgery protection token (Plesk rejects a POST without
  a valid token before the extension runs) and confirmed by the user in a dialog.
- **Preflight before every change.** The agent must report `agent_running`, and the target must exist in
  the agent's current state: the address must be banned to unban it, an entry must be in the allow list
  to remove it, the document root must belong to a known site and have no scan queued.
- **Input is validated three times**: in the browser, in PHP (addresses with `filter_var`, networks no wider
  than /16 for IPv4 and /48 for IPv6, no loopback/multicast/unspecified), and in the root wrapper.
- **The wrapper** (`src/sbin/infrafence-panel`) accepts only the contract commands and options, checks each
  value against a strict pattern, resolves `scan` paths with `readlink -e` and requires them to be inside the
  Plesk vhosts directory (`HTTPD_VHOSTS_D`), runs the agent only if the binary and its directory are owned by
  root and not writable by others, clears the environment, and applies a 25 second timeout.
- **It changes nothing on the host by itself.** Installing the extension adds files under Plesk's own
  directories only. It never touches iptables, nftables, ModSecurity, fail2ban or other tools; all changes
  go through the agent, which reports them to the dashboard with `source: "panel"` and the actor
  `plesk:<login>`. Removing the extension leaves nothing behind.
- **No credentials.** The extension stores no token. "Open in InfraFence" is a plain https link to the
  server's page on the dashboard; the user signs in there normally.

The UI is React on the Plesk UI library that Plesk itself loads (the `plesk-ui-library` AMD module), so it
follows the panel version and its themes (the default Contrast theme and the dark theme) without any
styling of its own beyond spacing. The bundle is about 45 KB.

## Fields the extension reads

`docs/panel-contract.md` lists the commands. These are the reply fields this extension uses (the fixtures in
`dev/fixtures/` are complete examples). Unknown codes are shown in readable form, so a newer agent with new
reasons, event types or tools does not break the screens.

| Command | Fields |
|---|---|
| `status` | `agent_version`, `agent_running`, `connected`, `last_heartbeat`, `agent_id`, `hostname`, `plan`, `automode` (`enforce`, `observe`, `off`), `dashboard_url` (https only) |
| `bans` | `total`, `bans[]`: `ip`, `reason`, `source` (`local`, `network`, `automode`, `manual`), `created`, `expires` (null = permanent) |
| `allowlist` | `entries[]`: `ip` (address or CIDR), `note`, `actor`, `created` |
| `findings` | `total`, `findings[]`: `id`, `path`, `kind` (`malware`, `integrity`), `signature`, `severity`, `status`, `domain`, `detected` |
| `events` | `events[]`: `id`, `type`, `severity`, `source_ip`, `time`, `source`, `actor` |
| `coexistence` | `mode` (`coexist`, `primary`), `firewall_owner`, `tools[]`: `id`, `name`, `detected`, `running`, `version`, `ruleset`, `actions[]` (codes such as `import_bans`, `no_iptables`, `leave_firewall`, `own_chain`, `read_audit_log`, `no_rule_changes`, `defer_firewall`, `defer_malware`) |
| `sites` | `sites[]`: `account`, `domain`, `docroot`, `coverage` (`full`, `partial`, `none`), `scan_status`, `last_scan`, `files` |
| `unban`, `allow`, `disallow` | `ok`, `ip` |
| `scan` | `ok`, `queued`, `path`, `job_id` |

Times are RFC 3339 in UTC. Errors are `{"ok": false, "error": "<code>", "message": "…"}`; the extension
translates the codes it knows (`agent_not_running`, `not_banned`, `invalid_ip`, …) and shows the others as
"The action failed (<code>)".

## Layout

```
plesk/
  build.sh                 builds dist/infrafence-plesk-<version>-<release>.zip in Docker
  extension.config.js      build settings for plesk-ext-sdk (entry point, no generated index.php)
  package.json, yarn.lock  build dependencies (the zip contains no node modules)
  src/                     the extension: everything here except frontend/ goes into the zip
    meta.xml
    _meta/icons/           32x32, 64x64, 128x128
    _meta/screenshots/
    htdocs/                index.php, css/, images/, dist/main.js (built)
    plib/controllers/      IndexController (the page), ApiController (JSON endpoints)
    plib/hooks/            Navigation, CustomButtons, Home (status block), ActionLog
    plib/library/          Agent (calls the wrapper), Validate, Config, Messages, HomeBlock
    plib/resources/locales/
    plib/views/
    sbin/infrafence-panel  root wrapper
    frontend/              React sources (not shipped)
  dev/
    mock-agent             stand-in for infrafence-agent that answers from fixtures
    fixtures/              one JSON reply per read command
    install-mock.sh        puts the mock on a test container or VM
    test-wrapper.sh        checks that the wrapper refuses everything outside the contract
    check-locales.php      every locale has every key (run by build.sh)
    icon.svg               source of the icons
```

## Build

```sh
./build.sh
```

Needs only Docker: PHP lint and the locale check run in `php:8.3-cli`, the UI is built in `node:20`
with `plesk-ext-sdk`. Output: `dist/infrafence-plesk-1.0.0-1.zip`.

## Install

```sh
plesk bin extension -i infrafence-plesk-1.0.0-1.zip     # install or upgrade
plesk bin extension -u infrafence                       # remove
```

Optional settings in `/usr/local/psa/admin/conf/panel.ini`:

```ini
[ext-infrafence]
; shown on the "agent not installed" screen
installCommand = "curl -fsSL https://get.infrafence.com | sudo bash"
; dashboard link on the same screen ("Open in InfraFence" uses dashboard_url from the agent)
dashboardUrl = "https://app.infrafence.com"
```

Testing: see [TESTING.md](TESTING.md).
