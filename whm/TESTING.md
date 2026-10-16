# Testing the WHM plugin

## Without cPanel (Docker)

| Command | What it covers |
|---|---|
| `make test` | `perl -c` of every module, the CGI and the mock agent; input validation; running the agent (argv, timeouts, invalid output, clean environment, owner checks); the controller (pages, confirmation step, security token, every action's argv, validation before any change); rendering every screen in 6 languages with a stub master template; escaping of hostile agent output; translation files. Runs as root and as an unprivileged user. |
| `make install-test` | `install.sh` and `uninstall.sh` on a fake `/usr/local/cpanel` tree on AlmaLinux 8, 9 and 10: checks fail cleanly without cPanel or on an old version, `--check` changes nothing, install, reinstall, repair from the installed copy, conflicts, rollback when registration fails, uninstall and uninstall again, and that no service is restarted. It also runs the installed CGI against the mock agent, with stub `Whostmgr::ACLS`, `Cpanel::Template` and `Cpanel::Locale`. |
| `make packages` | Builds `dist/` (tar.gz, noarch RPM, `.deb`) in Docker. |
| `make package-test` | Installs, upgrades and removes the RPM on AlmaLinux 8/9/10 and the `.deb` on Ubuntu 24.04, with and without the fake cPanel tree. |
| `make screenshots` | Renders every screen with the mock agent and saves PNGs to `docs/screenshots/` (needs Chrome or Chromium). |

The fake tree and the stubs only exist inside throwaway containers. The test scripts refuse to run outside
a container.

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
- [ ] It shows "The InfraFence agent is not installed on this server", the install command, the Copy button and the link to infrafence.com.
- [ ] `iptables-save | md5sum` and the list of running units are unchanged; `cpsrvd` was not restarted (`systemctl status cpsrvd`, uptime).

### 2. With the mock agent (before the real agent is ready)

    install -o root -g root -m 0755 dev/mock-agent /usr/local/bin/infrafence-agent
    cp -r dev/fixtures /usr/local/bin/fixtures

- [ ] Every tab renders: Overview, Bans, Allow list, Findings, Events, Coexistence, Sites.
- [ ] Unban, Allow, Remove and Scan now each open a confirmation page first. Cancel goes back and changes nothing.
- [ ] Confirming shows a green message (the mock does not keep state, so the lists do not change).
- [ ] Unban `192.0.2.99` by editing the URL of a confirmation page: the agent's "not found" error appears in red.
- [ ] Security token: copy the confirmation form, change the `csrf` field (browser dev tools) and submit: "The security check failed" and HTTP 403.
- [ ] Open a confirmation URL with a different `/cpsess…/` token: WHM itself refuses it.
- [ ] `chmod 0777 /usr/local/bin/infrafence-agent` and reload: the page reports the binary is not trusted. Restore `0755`.
- [ ] Change the WHM language (top right: user menu » Change Language) to Italiano, Español, Français, Deutsch and Português: the plugin follows. Check `pt_br` also maps to Portuguese.
- [ ] Log in as a reseller with some privileges (not "all"): the plugin is not listed, and opening `/cgi/infrafence/index.cgi` directly gives "Access denied".
- [ ] Remove the mock (`rm -r /usr/local/bin/infrafence-agent /usr/local/bin/fixtures`).

### 3. With the real agent

Install the agent following infrafence.com, then:

- [ ] Overview: version, heartbeat a few seconds old, plan, AutoMode, "Open in InfraFence" opens the right server on the dashboard. In the dashboard's request log, the Referer does not contain `/cpsess`.
- [ ] Ban a test address from another machine (e.g. failed SSH logins), find it under Bans, unban it, and confirm it is not banned again and that the dashboard shows the event with `source: panel` and actor `root`.
- [ ] Add and remove an allow-list entry, with a note containing accents (e.g. "Ufficio Città").
- [ ] Scan now on a site; the dashboard shows the queued scan.
- [ ] Stop the agent (`systemctl stop infrafence-agent`): the yellow "not running" banner, "Not protected" on Overview, lists show the error. Start it again.
- [ ] With CSF installed: Coexistence lists CSF/lfd and the plugin changed nothing in `/etc/csf`.

### 4. Upgrade and uninstall

    ./install.sh                                  # newer tarball over the old one
    /usr/local/share/infrafence-whm/uninstall.sh --check
    /usr/local/share/infrafence-whm/uninstall.sh
    /usr/local/share/infrafence-whm/uninstall.sh  # "nothing to remove"; no error

- [ ] The plugin is gone from WHM » Plugins; `/var/cpanel/apps/infrafence.conf` is gone.
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
- the `Status: 303` redirect after an action lands back on the right tab with the green message.
