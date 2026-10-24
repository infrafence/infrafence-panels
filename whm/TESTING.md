# Testing the WHM plugin

## Without cPanel (Docker)

| Command | What it covers |
|---|---|
| `make test` | `perl -c` of every module, the CGI and the mock agent; input validation; running the agent (argv, timeouts, invalid output, clean environment, owner checks); the controller (pages, confirmation step, security token, every action's argv, validation before any change); rendering every screen in 6 languages with a stub master template; escaping of hostile agent output; translation files. Runs as root and as an unprivileged user. |
| `make install-test` | `install.sh` and `uninstall.sh` on a fake `/usr/local/cpanel` tree on AlmaLinux 8, 9 and 10: checks fail cleanly without cPanel or on an old version, `--check` changes nothing, install, reinstall, repair from the installed copy, conflicts, rollback when registration fails, uninstall and uninstall again, and that no service is restarted. It also runs the installed CGI against the mock agent, with stub `Whostmgr::ACLS`, `Cpanel::Template` and `Cpanel::Locale`. |
| `make packages` | Builds `dist/` (tar.gz, noarch RPM, `.deb`) in Docker. |
| `make package-test` | Installs, upgrades and removes the RPM on AlmaLinux 8/9/10 and the `.deb` on Ubuntu 24.04, with and without the fake cPanel tree. |
| `make lab-up` / `make lab-down` | Starts (or removes) long-running containers with the fake cPanel tree, the plugin installed (tarball on AlmaLinux 8/9/10, `.deb` on Ubuntu 24.04) and the mock agent, for checking things by hand. See the header of `test/lab.sh`. |
| `make umask-test` | Builds the tarball, RPM and `.deb` from a copy of the source where every file is group- and world-writable, with umask 002, then installs each (and the source directly) and checks that nothing installed is writable by group or others or owned by anyone but root. |
| `make screenshots` | Renders every screen with the mock agent and saves PNGs to `docs/screenshots/` (needs Chrome or Chromium). |

The fake tree and the stubs only exist inside throwaway containers. The test scripts refuse to run outside
a container.

## Scope: server-wide data, root only

Every reply from the agent covers the whole server: all accounts' sites, bans, events and findings, and the
server's whitelist. The agent has no notion of resellers or account owners. In v1 the plugin is therefore
for root (and users with the `all` privilege) only, and must never be reachable by resellers or cPanel users:

- AppConfig registers it with `acls=all`, so WHM lists it only for those users.
- The CGI checks `Whostmgr::ACLS::hasroot()` itself and answers 403 otherwise, even when the URL is opened
  directly.
- Nothing is installed for cPanel users (no cPanel plugin, no Jupiter/Meridian entry).

Covered without cPanel by `make install-test` (a non-root ACL gets 403). On a real server, see step 2 below.
A per-reseller view would need filtering by account in the plugin and is not part of v1.

## On a real cPanel & WHM server

Use a test server or VM, never a customer's production server. Use a cPanel trial licence, on
AlmaLinux 9 (also repeat 1–5 on AlmaLinux 8, CloudLinux and Ubuntu 24.04 when possible).

### 0. Before you start

    cat /usr/local/cpanel/version
    ls /var/cpanel/apps/
    iptables-save | md5sum > /root/ifn-before.iptables
    systemctl list-units --state=running --no-legend | md5sum > /root/ifn-before.units
    ls -l --time-style=+%s /usr/local/cpanel/whostmgr/docroot/cgi /usr/local/cpanel/whostmgr/docroot/templates

### 1. Install from the tarball, without the agent

    tar xzf infrafence-whm-0.1.0.tar.gz && cd infrafence-whm-0.1.0
    ./install.sh --check          # every line "ok"; nothing changed
    ./install.sh
    ./install.sh                  # again: same result, no errors

- [ ] `/var/cpanel/apps/infrafence.conf` exists. `/usr/local/cpanel/bin/register_appconfig --list` (if available) lists `infrafence`.
- [ ] WHM » Plugins shows **InfraFence** with its icon. Searching "InfraFence" in the WHM sidebar finds it.
- [ ] The page opens inside WHM's normal frame (header, sidebar, breadcrumb), not as a bare page.
- [ ] It shows "The InfraFence agent is not installed on this server", the instruction to add the server in the dashboard (Servers > Add server), and the Add server button opening https://infrafence.com/add-server.
- [ ] `iptables-save | md5sum` and the list of running units are unchanged; `cpsrvd` was not restarted (`systemctl status cpsrvd`, uptime).

### 2. With the mock agent (before the real agent is ready)

    install -o root -g root -m 0755 dev/mock-agent /usr/local/bin/infrafence-agent
    cp -r dev/fixtures dev/scenarios /usr/local/bin/

- [ ] Every tab renders: Overview, Bans, Whitelist, Findings, Events, Coexistence, Sites.
- [ ] Unban, Allow, Remove and Scan now each open a confirmation page first. Cancel goes back and changes nothing.
- [ ] Confirming shows a green message (the mock does not keep state, so the lists do not change). Allowing `203.0.113.7` (banned) adds the note that the ban stays listed.
- [ ] Unban `192.0.2.99` by editing the URL of a confirmation page: "This address is not banned on this server" appears in red.
- [ ] Whitelist: the dashboard entries (`203.0.113.20`, `10.0.0.0/8`) show "Managed in the dashboard" and no Remove button.
- [ ] Security token: copy the confirmation form, change the `csrf` field (browser dev tools) and submit: "The security check failed" and HTTP 403.
- [ ] Open a confirmation URL with a different `/cpsess…/` token: WHM itself refuses it.
- [ ] `chmod 0777 /usr/local/bin/infrafence-agent` and reload: the page reports the binary is not trusted. Restore `0755`.
- [ ] Change the WHM language (top right: user menu » Change Language) to Italiano, Español, Français, Deutsch and Português: the plugin follows. Check `pt_br` also maps to Portuguese.
- [ ] Log in as a reseller with some privileges (not "all"): the plugin is not listed, and opening `/cgi/infrafence/index.cgi` directly gives "Access denied". Repeat as a reseller that owns accounts: still denied (the data is server-wide).
- [ ] Log in to cPanel as an account user: there is no InfraFence entry anywhere.
- [ ] Remove the mock (`rm -r /usr/local/bin/infrafence-agent /usr/local/bin/fixtures /usr/local/bin/scenarios`).

### 3. With the real agent

Add the server in the dashboard (Servers > Add server) and run the command shown there, then:

- [ ] Overview: version, heartbeat under 3 minutes old, last sync, server ID, hosting panel "cPanel & WHM", plan. "Open in InfraFence" opens the right server on the dashboard. In the dashboard's request log, the Referer does not contain `/cpsess`.
- [ ] Turn monitor mode on in the dashboard: Overview shows "Monitor mode" and Bans says the bans are not enforced. Turn it off again.
- [ ] Ban a test address from another machine (e.g. failed SSH logins), find it under Bans, unban it. The confirmation and the result say the lift is on this server only and until which date (the ban's expiry, at most 30 days). For a network or AutoMode ban, both also say the organization keeps the ban on its other servers. The dashboard shows the `panel_unban` event with actor `root`, and the ban is still in force on the organization's other servers.
- [ ] Allow the server's own public address: the warning says it is one of the server's own addresses. Allow `127.0.0.1`: refused (loopback).
- [ ] Add and remove an whitelist entry, with a note containing accents (e.g. "Ufficio Città").
- [ ] Sites: a document root outside the account's home (or not owned by it) shows "Cannot be scanned" and no Scan now button.
- [ ] Scan now on a site; the dashboard shows the scan. Start a second one at once: "A malware scan is already running".
- [ ] Overview, top to bottom: status row (state, score and grade, one-line verdict), the four figures, critical events and score items, the map, the technical details. With an agent that has `panel map` and `panel score`, the map and score match the server's page in the dashboard; "Fix these in InfraFence" opens the server there.
- [ ] Map: 24 h and 7 days switch with plain links; hovering a country shows its name and count. Browser dev tools » Network: the page loads nothing from other sites. Nothing is reported by WHM's Content Security Policy in the console.
- [ ] Block the dashboard from the server for over 5 minutes (e.g. a temporary firewall rule on the API host): the map and score stay, with "Last updated …". Remove the rule.
- [ ] With an agent older than `panel map`: the Overview says to update the agent, without a red error.
- [ ] Events: the Critical and Warning and above filters, and the Overview's "See them in Events" link, show the same events as the Overview's list.
- [ ] Language: pick Deutsch in the plugin's selector (WHM itself in English): every tab is in German, and WHM's own menus stay English. Log in as another root-level WHM user: the plugin follows that user's WHM language. `ls -l /var/cpanel/infrafence-whm/prefs/`: `root.json`, 0600, owned by root; directory 0700. Choose "Same as WHM": the file is gone.
- [ ] Language and CSRF: change the `csrf` field of the language form (dev tools) and submit: "The security check failed", HTTP 403, choice unchanged.
- [ ] Stop the agent (`systemctl stop infrafence-agent`): the yellow "not running" banner, "Not protected" on Overview, Bans/Findings/Events show the error, Coexistence and Sites still list. Start it again.
- [ ] With CSF installed: Coexistence lists CSF and lfd with the translated explanation, and the plugin changed nothing in `/etc/csf`.

### 4. Upgrade and uninstall

    ./install.sh                                  # newer tarball over the old one
    /usr/local/share/infrafence-whm/uninstall.sh --check
    /usr/local/share/infrafence-whm/uninstall.sh
    /usr/local/share/infrafence-whm/uninstall.sh  # "nothing to remove"; no error

- [ ] The plugin is gone from WHM » Plugins; `/var/cpanel/apps/infrafence.conf` and `/var/cpanel/infrafence-whm` are gone.
- [ ] The agent is still installed and running.
- [ ] `iptables-save | md5sum` matches `/root/ifn-before.iptables` (with the agent's own rules accounted for).

### 5. Packages

    dnf install ./infrafence-whm-0.1.0-1.noarch.rpm    # or: apt install ./infrafence-whm_0.1.0_all.deb
    dnf reinstall ./infrafence-whm-0.1.0-1.noarch.rpm
    dnf remove infrafence-whm

- [ ] Registered after install, still registered after reinstall, unregistered and all files gone after removal.

### 6. Survive a cPanel update

    /scripts/upcp --force

- [ ] The plugin is still listed and works afterwards.

### Things to confirm on the first real server

These depend on cPanel internals that the stubs can only approximate:

- the variables passed to `master_templates/master.tmpl` (`header`, `icon`, `breadcrumbdata`, `theme`) give the expected title, icon and breadcrumb;
- `Cpanel::Template::process_template('whostmgr', { template_file, print, data })` finds `infrafence/main.tmpl`, and accented text is printed correctly (no double encoding);
- `Cpanel::Locale->get_handle->get_language_tag` returns the WHM user's language;
- the `Status: 303` redirect after an action lands back on the right tab with the green message;
- `status.automode`, once the dashboard sends it: check what the Overview shows and adjust `_automode` in `App.pm` to its real fields.
