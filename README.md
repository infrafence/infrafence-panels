# InfraFence Panel Integrations

Plugins that bring [InfraFence](https://infrafence.com) server protection into the hosting control panels:

| Folder | Panel | Status |
|---|---|---|
| [`whm/`](whm/) | cPanel & WHM (WHM » Plugins) | in development |
| [`plesk/`](plesk/) | Plesk Obsidian extension | in development |

The plugins are a thin interface. They talk to the InfraFence agent already installed on the server,
through `infrafence-agent panel …` (see [docs/panel-contract.md](docs/panel-contract.md)). They store no
InfraFence credentials, and they never change the firewall or ModSecurity by themselves.

## License

[Business Source License 1.1](LICENSE), like the agent: free for production use on any number of servers,
including your customers' servers, except to offer a competing product. Each version becomes Apache 2.0
four years after its first public release.
