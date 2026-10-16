# InfraFence for cPanel & WHM

A WHM plugin for root: **WHM » Plugins » InfraFence**. It shows what the InfraFence agent on the server
is doing and lets you act on it, inside WHM's own interface.

| Screen | What it shows |
|---|---|
| Overview | Protection status, agent version and heartbeat, plan, AutoMode, link to the server in InfraFence |
| Bans | Active bans; unban, or add the address to the allow list |
| Allow list | Addresses that are never banned, from this server and from the dashboard; add and remove |
| Findings | Malware and file integrity findings |
| Events | Recent security events |
| Coexistence | Other security tools found (CSF, lfd, Imunify360, cPHulk, ModSecurity and its rule sets…) and how InfraFence works with each |
| Sites | Accounts, domains and document roots with malware scan coverage; start a scan |

When the agent is not installed, the plugin says how to add the server in the InfraFence dashboard
(Servers > Add server) and links to https://infrafence.com/add-server.

![Overview](docs/screenshots/en-overview.png)

## How it works

The plugin is a thin interface. Every screen runs one command as root and reads JSON:

    infrafence-agent panel <command> [args] --json

(see [../docs/panel-contract.md](../docs/panel-contract.md); every field is described in
[../docs/panel-json.md](../docs/panel-json.md)). It holds no InfraFence credentials and never
changes the firewall, ModSecurity or any other tool by itself.

- **Access.** Registered with `acls=all`, and the CGI checks `Whostmgr::ACLS::hasroot()` again.
- **Changes.** Unban, allow, remove and scan always show a confirmation page first. The change runs only on
  a POST that carries the session's WHM security token. A request from another site is refused.
- **Input.** IP addresses are validated (IPv4 without leading zeros, IPv6 normalized). Allow-list notes
  are limited to 200 bytes, with no control characters. Scans only accept document roots the agent
  itself listed as `scannable` (inside the account's home and owned by it).
- **Scope.** The agent's replies cover the whole server (all accounts), so the plugin is for root only.
  An unban from the panel lifts the ban on this server only, for at most 30 days; the plugin says so before
  and after.
- **Running the agent.** The command is started from an argv list, never through a shell. It runs with a
  clean environment, no stdin, a 20-second limit (25 seconds in total for the Overview's calls) and capped
  output. The binary is resolved with `realpath`; it and every directory above it must be owned by root and
  not writable by group or others, and the resolved file is what runs.
- **Output.** Everything is escaped in the templates. Messages after an action come from a fixed list; the
  values in them are re-derived (canonical address, re-formatted date), never echoed from the URL. The
  "Open in InfraFence" link is shown only for a strict `https://host/path` URL and sends no referrer, so
  the WHM session token never leaves the server.
- **Files.** Everything installed is owned by root and writable only by root, whatever the build's umask
  (`make umask-test`).
- **Language.** The text follows the WHM user's locale: English, Italian, Spanish, French, German or
  Portuguese (`plugin/locale/*.json`).

## Install

Each method checks the server first. If a check fails, nothing is changed. Services are never restarted.

**Tarball**

    tar xzf infrafence-whm-0.1.0.tar.gz
    cd infrafence-whm-0.1.0
    ./install.sh --check    # optional: only run the checks
    ./install.sh

**RPM** (AlmaLinux 8/9/10, CloudLinux, Rocky): `dnf install ./infrafence-whm-0.1.0-1.noarch.rpm`

**Debian package** (Ubuntu 24.04): `apt install ./infrafence-whm_0.1.0_all.deb`

To remove: `/usr/local/share/infrafence-whm/uninstall.sh` (tarball install), `dnf remove infrafence-whm`
or `apt remove infrafence-whm`. Uninstalling removes only the plugin, never the agent.

### Files

| Path | |
|---|---|
| `/usr/local/cpanel/whostmgr/docroot/cgi/infrafence/index.cgi` | the CGI |
| `/usr/local/cpanel/whostmgr/docroot/templates/infrafence/` | Template Toolkit templates, wrapped in `master_templates/master.tmpl` |
| `/usr/local/cpanel/whostmgr/docroot/addon_plugins/infrafence.png` | icon |
| `/usr/local/share/infrafence-whm/` | Perl modules, translations, AppConfig file, install and uninstall scripts |
| `/var/cpanel/apps/infrafence.conf` | written by `register_appconfig` |

## Development

    make test           # unit, controller and rendering tests (Docker, AlmaLinux 9)
    make install-test   # install.sh/uninstall.sh and the CGI on a fake cPanel tree, AlmaLinux 8, 9, 10
    make packages       # dist/: tar.gz, .rpm, .deb, built in Docker
    make package-test   # installs and removes the .rpm and the .deb in containers
    make screenshots    # renders every screen with the mock agent and captures it

`dev/mock-agent` answers the panel commands like the real agent, from `dev/fixtures/` (copies of the agent's
own outputs). It also has a stopped agent, monitor mode, empty lists, hostile content for escaping tests, and
faults (timeouts, invalid output).
[TESTING.md](TESTING.md) covers the checks on a real cPanel server.

## Layout

    install.sh, uninstall.sh   installer (also used by the packages)
    plugin/cgi/                index.cgi
    plugin/lib/                InfraFence::WHM::{App,Agent,CGI,I18n,Validate,Util}
    plugin/templates/          WHM templates
    plugin/locale/             en, it, es, fr, de, pt
    plugin/appconfig/          AppConfig file
    dev/                       mock agent, fixtures (agent outputs), scenarios, stub master template, renderer
    t/                         Test::More tests
    test/install/              install test on a fake cPanel tree
    packaging/                 RPM spec, Debian control files, build script
