# InfraFence Panel Integrations

Plugins that bring [InfraFence](https://infrafence.com) server protection into the hosting control panels:

| Folder | Panel | Status | Docs |
|---|---|---|---|
| [`whm/`](whm/) | cPanel & WHM (WHM » Plugins) | early access | [WHM plugin](https://infrafence.com/docs/whm-plugin) |
| [`plesk/`](plesk/) | Plesk Obsidian extension | in development | [Plesk extension](https://infrafence.com/docs/plesk-extension) |

**Early access (WHM):** the WHM plugin is built and tested against the InfraFence agent, but not yet on live
cPanel servers. To join, write to info@infrafence.com with how many servers you run.

**In development (Plesk):** the Plesk extension is not ready for production servers yet.
Overview for hosting providers: [InfraFence for cPanel & WHM](https://infrafence.com/integrations/cpanel-whm);
what the plugins show and need: [Hosting panels](https://infrafence.com/docs/hosting-panels).

The plugins are a thin interface. They talk to the InfraFence agent already installed on the server,
through `infrafence-agent panel …` (see [docs/panel-contract.md](docs/panel-contract.md)). They store no
InfraFence credentials, and they never change the firewall or ModSecurity by themselves.

## License

[Business Source License 1.1](LICENSE), like the agent: free for production use on any number of servers,
including your customers' servers, except to offer a competing product. Each version becomes Apache 2.0
four years after its first public release.
