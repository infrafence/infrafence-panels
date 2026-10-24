#!/bin/sh
#
# Removes the InfraFence plugin from WHM.
#
#   ./uninstall.sh                   unregister the plugin and remove its files
#   ./uninstall.sh --check           show what would be removed; change nothing
#   ./uninstall.sh --unregister-only only unregister from WHM (package scripts)
#
# Safe to run again. Only files installed by this plugin are removed (they
# carry a .infrafence-whm marker). The InfraFence agent is not touched, and no
# service is restarted.

set -eu
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

CPANEL=/usr/local/cpanel
WHM_DOCROOT=$CPANEL/whostmgr/docroot
CGI_DIR=$WHM_DOCROOT/cgi/infrafence
TPL_DIR=$WHM_DOCROOT/templates/infrafence
ICON=$WHM_DOCROOT/addon_plugins/infrafence.png
SHARE=/usr/local/share/infrafence-whm
APPCONF=/var/cpanel/apps/infrafence.conf
# Each WHM user's language choice (created by the plugin, with the marker).
STATE=/var/cpanel/infrafence-whm
MARKER=.infrafence-whm

MODE=uninstall
case ${1:-} in
    '')                MODE=uninstall ;;
    --check)           MODE=check ;;
    --unregister-only) MODE=unregister ;;
    -h|--help)         sed -n '3,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                 echo "unknown option: $1" >&2; exit 2 ;;
esac

say()  { printf '%s\n' "$*"; }
warn() { printf 'infrafence-whm: %s\n' "$*" >&2; }

[ "$(id -u)" -eq 0 ] || { warn "run this script as root"; exit 1; }

# The icon and the AppConfig file have no room for a marker: they are ours
# when the shared directory is.
OWNED=0
[ -f "$SHARE/$MARKER" ] && OWNED=1

ACTIONS=0
plan() { say "  $*"; ACTIONS=$((ACTIONS + 1)); }

unregister() {
    if [ -e "$APPCONF" ]; then
        if [ "$OWNED" -eq 0 ] && [ "$MODE" != unregister ]; then
            warn "$APPCONF was not installed by this plugin; leaving it"
            return 0
        fi
        if [ "$MODE" = check ]; then plan "unregister from WHM ($APPCONF)"; return 0; fi
        if [ -x "$CPANEL/bin/unregister_appconfig" ]; then
            "$CPANEL/bin/unregister_appconfig" infrafence >/dev/null || warn "unregister_appconfig failed"
        else
            rm -f "$APPCONF"
        fi
        say "Unregistered from WHM"
    fi
}

remove_dir() {
    [ -e "$1" ] || return 0
    if [ ! -f "$1/$MARKER" ]; then
        warn "$1 was not installed by this plugin; leaving it"
        return 0
    fi
    if [ "$MODE" = check ]; then plan "remove $1"; return 0; fi
    rm -rf "$1"
}

unregister
[ "$MODE" = unregister ] && exit 0

remove_dir "$CGI_DIR"
remove_dir "$TPL_DIR"
if [ -e "$ICON" ] && [ "$OWNED" -eq 1 ]; then
    if [ "$MODE" = check ]; then plan "remove $ICON"; else rm -f "$ICON"; fi
fi
remove_dir "$STATE"
# The shared directory goes last: its marker is what proves the rest is ours.
remove_dir "$SHARE"

if [ "$MODE" = check ]; then
    [ "$ACTIONS" -gt 0 ] || say "  nothing to remove"
    say "Nothing was changed."
else
    say "InfraFence WHM plugin removed. No services were restarted."
fi
