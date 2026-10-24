# InfraFence Panel Integrations

Plugins that bring [InfraFence](https://infrafence.com) server protection into the hosting control panels:

| Folder | Panel | Status | Docs |
|---|---|---|---|
| [`whm/`](whm/) | cPanel & WHM (WHM » Plugins) | available | [WHM plugin](https://infrafence.com/docs/whm-plugin) |
| [`plesk/`](plesk/) | Plesk Obsidian extension | in development | [Plesk extension](https://infrafence.com/docs/plesk-extension) |

**Available (WHM):** install it from your InfraFence dashboard (Panels › cPanel & WHM) after creating an
account at https://infrafence.com. Developers can build the packages from source (see [whm/README.md](whm/README.md)).

**In development (Plesk):** the Plesk extension is not ready for production servers yet.

**WHM Overview:** the WHM plugin opens on an Overview with the protection status, the security score and
grade, the last 24 hours' critical events, a map of where the server's attacks came from (24 hours or
7 days) and the key figures, in the language each WHM user picks; the Events screen filters by severity.
The score and the map come from the InfraFence dashboard through the agent's `panel score` and `panel map`
commands, which need agent 1.0.33 or later. See [whm/README.md](whm/README.md).
Overview for hosting providers: [InfraFence for cPanel & WHM](https://infrafence.com/integrations/cpanel-whm);
what the plugins show and need: [Hosting panels](https://infrafence.com/docs/hosting-panels).

The plugins are a thin interface. They talk to the InfraFence agent already installed on the server,
through `infrafence-agent panel …` (see [docs/panel-contract.md](docs/panel-contract.md); every field of every
reply is in [docs/panel-json.md](docs/panel-json.md)). They store no
InfraFence credentials, and they never change the firewall or ModSecurity by themselves.

## License

[Business Source License 1.1](LICENSE), like the agent: free for production use on any number of servers,
including your customers' servers, except to offer a competing product. Each version becomes Apache 2.0
four years after its first public release.
