# Development files

- `mock-agent`: answers `infrafence-agent panel <command> … --json` from `fixtures/`. It checks arguments
  the way the agent should (required `--actor`, `--limit` values, unknown options) and can log every argv.
  The header of the script lists its environment variables.
- `fixtures/`: replies per scenario: `default`, `stopped`, `empty`, `hostile` (markup and quotes in every
  field, for escaping tests).
- `stub/master_templates/master.tmpl`: a stand-in for WHM's master template, for rendering outside cPanel.
- `render`: renders every screen to static HTML. `screenshots.sh` also captures them.
- `Dockerfile.test`: AlmaLinux image with the Perl modules used by the tests.

## Reply fields the plugin reads

[docs/panel-contract.md](../../docs/panel-contract.md) sets the commands. These are the field names the plugin
uses, as in `fixtures/default/`. Times are ISO 8601 in UTC. Unknown fields are ignored. Unknown values
(a new severity, event type or source) are shown as they are.

| Command | Fields |
|---|---|
| `status` | `agent_version`, `agent_running` (bool), `last_heartbeat`, `connected` (bool), `agent_id`, `hostname`, `plan`, `automode` (`on`/`off`/`paused`), `dashboard_url` (only `https://` links are shown) |
| `bans` | `bans[]`: `ip`, `reason`, `source` (`local`/`network`/`automode`/`manual`), `created`, `expires` (null = permanent); optional `total` when `--limit` cut the list |
| `allowlist` | `entries[]`: `ip`, `note`, `actor`, `created` |
| `findings` | `findings[]`: `id`, `path`, `kind` (`malware`/`integrity`), `signature`, `severity` (`critical`/`high`/`medium`/`low`/`info`), `status` (`open`/`quarantined`/`resolved`/`ignored`), `detected` |
| `events` | `events[]`: `id`, `type` (e.g. `ssh_bruteforce`, `waf_block`, `malware_found`, `ban`), `severity`, `source_ip` (may be null), `time`; optional `detail` |
| `coexistence` | `mode` (`coexist`/`primary`); `tools[]`: `id`, `name`, `detected`, `running`, `version`, `handling` (`observe`/`feed`/`defer`/`complement`/`manage`); `modsecurity`: `installed`, `engine` (`on`/`detection_only`/`off`), `vendors[]`: `name`, `version`, `enabled` |
| `sites` | `sites[]`: `account`, `owner`, `domain`, `type` (`main`/`addon`/`sub`/`parked`), `docroot`, `coverage` (`full`/`partial`/`none`), `last_scan`, `files`, `findings_open`, `scan` (null/`queued`/`running`) |
| `unban`, `allow`, `disallow`, `scan` | `{"ok": true}` is enough; the plugin redirects with a confirmation message |

Error codes with their own text: `agent_not_running`, `not_found`, `already_allowed`, `invalid_args`,
`invalid_ip`, `unknown_path`, `not_connected`. Any other code shows a generic message with the agent's
`message`.
