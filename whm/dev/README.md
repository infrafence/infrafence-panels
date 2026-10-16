# Development files

- `fixtures/`: copies of the agent's own outputs (`panel-api/testdata/panel/` in the agent repository),
  byte for byte. Do not edit them; copy them again when the agent's output changes.
  [docs/panel-json.md](../../docs/panel-json.md) describes every field.
- `scenarios/`: test-only variants with the same shapes: `empty`, `monitor`, `restricted` and `hostile` (markup and
  quotes in every text field, for the escaping tests).
- `mock-agent`: answers `infrafence-agent panel <command> … --json` from those files, the way the agent
  does: `--limit` 1–500, `--since`, `--actor` and `--note` checks, the agent's error codes and shapes, and a
  stopped agent (`status`, `coexistence` and `sites` still answer). The header of the script lists its
  environment variables.
- `stub/master_templates/master.tmpl`: a stand-in for WHM's master template, for rendering outside cPanel.
- `render`: renders every screen to static HTML. `screenshots.sh` also captures them.
- `Dockerfile.test`: AlmaLinux image with the Perl modules used by the tests.

## How the plugin reads the replies

- Field names, enum values and null handling follow [docs/panel-json.md](../../docs/panel-json.md).
  Values the plugin has no text for (a new event type, severity, control panel or tool) are shown as sent.
- Error codes from the agent are translated by `error`. The English `message` (meant for logs) is shown only
  for a code the plugin has no text for.
  The plugin adds its own codes for problems on its side: `not_installed`, `agent_untrusted`, `timeout`,
  `exec_failed`, `bad_reply`, `invalid_note`, `csrf`, `unknown_action`.
- `coexistence` texts are translated by `action_id`; an unknown id shows the agent's English `action`.
- `status.automode` is passed through from the dashboard without a fixed shape: the plugin shows On/Off
  from an `enabled` field, or the value of `state`, `mode` or `status`, and "Not reported" when it is
  `null`.
