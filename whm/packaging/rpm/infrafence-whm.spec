# RPM for AlmaLinux 8/9/10, CloudLinux, Rocky and RHEL with cPanel & WHM.
# Built by packaging/build.sh; the version comes from the VERSION file.

%global debug_package %{nil}

Name:           infrafence-whm
Version:        %{ifn_version}
Release:        1%{?dist}
Summary:        InfraFence plugin for cPanel & WHM
License:        BUSL-1.1
URL:            https://infrafence.com
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch
# The plugin runs with cPanel's own Perl, which is not an RPM dependency, and
# loads cPanel modules at run time. Do not let rpm turn those into requirements.
AutoReqProv:    no

%description
WHM » Plugins » InfraFence: protection status, bans, allow list, findings,
events, coexistence with other security tools, and site scan coverage, read
from the InfraFence agent installed on the server. The plugin stores no
credentials and never changes the firewall or ModSecurity by itself.

%prep
%setup -q

%build

%install
sh ./install.sh --files-only --destdir %{buildroot}
# Only root may write what cpsrvd runs as root, whatever the build's umask.
chmod -R u+rwX,go-w %{buildroot}

%post
# Register with WHM. No service is restarted.
if [ -x /usr/local/cpanel/bin/register_appconfig ]; then
    /usr/local/share/infrafence-whm/install.sh --register-only || :
else
    echo "infrafence-whm: cPanel & WHM not found; the plugin is installed but not registered" >&2
fi

%preun
# Only on removal, not on upgrade.
if [ "$1" -eq 0 ]; then
    /usr/local/share/infrafence-whm/uninstall.sh --unregister-only || :
fi

%files
%defattr(-,root,root,-)
%license LICENSE
%doc README.md
/usr/local/cpanel/whostmgr/docroot/cgi/infrafence
/usr/local/cpanel/whostmgr/docroot/templates/infrafence
/usr/local/cpanel/whostmgr/docroot/addon_plugins/infrafence.png
/usr/local/share/infrafence-whm

%changelog
* Wed Nov 04 2026 Infrafence <info@infrafence.com> - 1.1.0-1
- Event details, as in the dashboard: the mailbox, mail protocol, login
  method and failures of a mail attack; the CVE (with a link to the
  Exploitation page), attack type, rule set and site of a WAF block; the
  addresses an exposed database listens on. Also on the Overview's list.
- SSH logins: the known SSH logins of the last 30 days (users, country,
  first and last login, read from the logs or seen live), whether
  InfraFence never bans the address or not (SSH service users), with Add
  to whitelist.
- Database clients: the regular clients of the database, cache and admin
  ports (seen on 3 of the last 7 days, first and last seen) and the
  Additional MySQL Access Hosts, with Add to whitelist.
- Both lists and the details need agent 1.0.41 or later; with an older
  agent the pages say so and the rest works as before.

* Mon Oct 26 2026 Infrafence <info@infrafence.com> - 1.0.3-1
- Technical details show the agent version and the plugin version as two
  rows. With agent 1.0.35 and later, when a newer plugin is released, every
  page says so, with a link to Panel plugins in the InfraFence dashboard,
  where the plugin is updated (updating the agent never updates it). Nothing
  is shown when the organization is not entitled, or with an older agent.

* Sun Oct 25 2026 Infrafence <info@infrafence.com> - 1.0.2-1
- Open or resolved: problems the agent (1.0.34 and later) reports as resolved,
  such as a database port closed or a file quarantined, no longer count as
  critical events or findings to review. The Overview lists the latest ones
  with how and when they were resolved; the Events page has a State column
  and an Open / Resolved / All filter. Older agents: every event is open.

* Sun Oct 25 2026 Infrafence <info@infrafence.com> - 1.0.1-1
- Included in the Basic, Pro and AutoMode plans. On Starter, while the
  subscription is not active, or before the plan is known, every page says so,
  shows no data and the actions are refused; the agent is asked for nothing
  but its status.

* Sat Oct 24 2026 Infrafence <info@infrafence.com> - 1.0.0-1
- First available release.

* Fri Oct 16 2026 Infrafence <info@infrafence.com> - 0.1.0-1
- First version: overview, bans, allow list, findings, events, coexistence, sites.
