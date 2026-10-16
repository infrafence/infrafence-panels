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
%license LICENSE
%doc README.md
/usr/local/cpanel/whostmgr/docroot/cgi/infrafence
/usr/local/cpanel/whostmgr/docroot/templates/infrafence
/usr/local/cpanel/whostmgr/docroot/addon_plugins/infrafence.png
/usr/local/share/infrafence-whm

%changelog
* Fri Oct 16 2026 Infrafence <info@infrafence.com> - 0.1.0-1
- First version: overview, bans, allow list, findings, events, coexistence, sites.
