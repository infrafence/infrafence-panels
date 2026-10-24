#!/bin/sh
#
# Installs the InfraFence plugin for cPanel & WHM (WHM » Plugins » InfraFence).
#
#   ./install.sh                 check the server, install the files, register the plugin
#   ./install.sh --check         only run the checks; change nothing
#   ./install.sh --register-only register the installed plugin with WHM (package scripts)
#   ./install.sh --files-only --destdir DIR
#                                copy the files under DIR (package builds); no checks
#
# Safe to run again: an existing InfraFence install is replaced in place.
# It does not restart any service, and it does not touch the firewall,
# ModSecurity or any other security tool. If a check fails, nothing is changed.

set -eu
umask 022
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

SRC=$(cd "$(dirname "$0")" && pwd)

CPANEL=/usr/local/cpanel
WHM_DOCROOT=$CPANEL/whostmgr/docroot
CGI_DIR=$WHM_DOCROOT/cgi/infrafence
TPL_DIR=$WHM_DOCROOT/templates/infrafence
ICON=$WHM_DOCROOT/addon_plugins/infrafence.png
SHARE=/usr/local/share/infrafence-whm
APPCONF=/var/cpanel/apps/infrafence.conf
CPANEL_PERL=$CPANEL/3rdparty/bin/perl
MARKER=.infrafence-whm
MIN_CPANEL=110

MODE=install
DESTDIR=

say()  { printf '%s\n' "$*"; }
warn() { printf 'infrafence-whm: %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

usage() {
    sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case $1 in
        --check)         MODE=check ;;
        --register-only) MODE=register ;;
        --files-only)    MODE=files ;;
        --destdir)       [ $# -ge 2 ] || usage 2; DESTDIR=$2; shift ;;
        --destdir=*)     DESTDIR=${1#--destdir=} ;;
        -h|--help)       usage 0 ;;
        *)               warn "unknown option: $1"; usage 2 ;;
    esac
    shift
done

# The source layout: either this repository (plugin/...) or an installed copy
# in $SHARE, which keeps install.sh next to lib/, locale/, map/ and the rest.
if [ -d "$SRC/plugin" ]; then
    P=$SRC/plugin
else
    P=$SRC/payload
fi
VERSION=$(cat "$SRC/VERSION" 2>/dev/null || echo unknown)

# ------------------------------------------------------------------ checks

FAILED=0
fail_check() { warn "check failed: $*"; FAILED=1; }
ok_check()   { say  "  ok  $*"; }

# A path is ours if it does not exist or carries our marker file.
ours() {
    [ ! -e "$1" ] || [ -f "$1/$MARKER" ]
}

preflight() {
    say "Checking this server (InfraFence WHM plugin $VERSION)"

    [ "$(id -u)" -eq 0 ] && ok_check "running as root" || fail_check "run this script as root"
    [ "$(uname -s)" = Linux ] && ok_check "Linux" || fail_check "this is not a Linux server"

    if [ -x "$CPANEL/cpanel" ] && [ -r "$CPANEL/version" ]; then
        cpv=$(cat "$CPANEL/version")
        major=$(printf '%s' "$cpv" | cut -d. -f2)
        case $major in
            ''|*[!0-9]*) fail_check "cannot read the cPanel version ($cpv)" ;;
            *) if [ "$major" -ge "$MIN_CPANEL" ]; then ok_check "cPanel & WHM $cpv"
               else fail_check "cPanel & WHM $cpv is too old (needs 11.$MIN_CPANEL or later)"; fi ;;
        esac
    else
        fail_check "cPanel & WHM is not installed ($CPANEL not found)"
    fi

    [ -x "$CPANEL/bin/register_appconfig" ] && ok_check "register_appconfig available" \
        || fail_check "$CPANEL/bin/register_appconfig not found"

    if [ -x "$CPANEL_PERL" ] && "$CPANEL_PERL" -MTemplate -MJSON::PP -MIO::Select -MTime::Local -MTime::HiRes -MCwd -e 1 >/dev/null 2>&1; then
        ok_check "cPanel Perl with Template Toolkit"
    else
        fail_check "$CPANEL_PERL with Template Toolkit and JSON::PP is required"
    fi

    for d in "$WHM_DOCROOT/cgi" "$WHM_DOCROOT/templates" "$WHM_DOCROOT/addon_plugins"; do
        [ -d "$d" ] || fail_check "$d is missing"
    done

    if ours "$CGI_DIR" && ours "$TPL_DIR" && ours "$SHARE"; then
        ok_check "no conflicting files"
    else
        fail_check "$CGI_DIR, $TPL_DIR or $SHARE exists but was not installed by this plugin; remove it first"
    fi
    if [ -e "$APPCONF" ] && [ ! -f "$SHARE/$MARKER" ]; then
        fail_check "$APPCONF exists but was not installed by this plugin; remove it first"
    fi

    free_kb=$(df -Pk /usr/local 2>/dev/null | awk 'NR==2 {print $4}')
    case ${free_kb:-} in
        ''|*[!0-9]*) fail_check "cannot read free disk space on /usr/local" ;;
        *) [ "$free_kb" -ge 10240 ] && ok_check "disk space" || fail_check "less than 10 MB free on /usr/local" ;;
    esac

    for f in cgi/index.cgi appconfig/infrafence.conf icons/infrafence.png locale/en.json map/world.json \
             templates/infrafence/main.tmpl lib/InfraFence/WHM/App.pm; do
        [ -f "$P/$f" ] || fail_check "package file missing: $f"
    done

    agent=
    for a in /usr/local/bin/infrafence-agent /usr/bin/infrafence-agent /usr/sbin/infrafence-agent /opt/infrafence/bin/infrafence-agent; do
        if [ -x "$a" ]; then agent=$a; break; fi
    done
    if [ -n "$agent" ]; then
        ok_check "InfraFence agent found at $agent"
    else
        say "  --  InfraFence agent not found; the plugin will show how to install it"
    fi

    [ "$FAILED" -eq 0 ]
}

# ------------------------------------------------------------------ files

# Builds DIR in a temporary sibling and swaps it in, so a page is never served
# from a half-copied directory. Only files are swapped: no service is
# restarted (cpsrvd picks up the new CGI and templates on the next request).
put_dir() {
    target=$1; shift
    parent=$(dirname "$target")
    mkdir -p "$parent"
    tmp=$(mktemp -d "$parent/.infrafence-new.XXXXXX")
    "$@" "$tmp" || { rm -rf "$tmp"; die "could not prepare $target"; }
    printf '%s\n' "$VERSION" > "$tmp/$MARKER"
    chmod 0755 "$tmp"
    if [ -e "$target" ]; then
        old=$(mktemp -d "$parent/.infrafence-old.XXXXXX")
        rmdir "$old"
        mv "$target" "$old"
        mv "$tmp" "$target"
        rm -rf "$old"
    else
        mv "$tmp" "$target"
    fi
}

fill_cgi() {
    install -m 0755 "$P/cgi/index.cgi" "$1/index.cgi"
}

fill_templates() {
    for f in "$P"/templates/infrafence/*.tmpl; do
        install -m 0644 "$f" "$1/$(basename "$f")"
    done
}

fill_share() {
    mkdir -p "$1/lib/InfraFence/WHM" "$1/locale" "$1/map" "$1/payload"
    for f in "$P"/lib/InfraFence/WHM/*.pm; do
        install -m 0644 "$f" "$1/lib/InfraFence/WHM/$(basename "$f")"
    done
    for f in "$P"/locale/*.json; do
        install -m 0644 "$f" "$1/locale/$(basename "$f")"
    done
    for f in "$P"/map/world.json "$P"/map/countries.json "$P"/map/NOTICE; do
        install -m 0644 "$f" "$1/map/$(basename "$f")"
    done
    install -m 0644 "$P/appconfig/infrafence.conf" "$1/infrafence.conf"
    install -m 0755 "$SRC/install.sh" "$1/install.sh"
    install -m 0755 "$SRC/uninstall.sh" "$1/uninstall.sh"
    install -m 0644 "$SRC/VERSION" "$1/VERSION"
    # A copy of the payload, so `install.sh` in $SHARE can repair the install.
    # As root, tar would keep the source's modes and owners (a checkout or
    # tarball made with umask 002 has group-writable files), so take neither
    # and normalise: only root may write anything that cpsrvd runs as root.
    if [ "$P" != "$1/payload" ]; then
        (cd "$P" && tar cf - .) | (cd "$1/payload" && tar xf - --no-same-permissions --no-same-owner)
    fi
    chmod -R go-w,u+rwX "$1/payload"
}

install_files() {
    root=${1:-}
    CGI_DIR=$root$CGI_DIR TPL_DIR=$root$TPL_DIR SHARE=$root$SHARE ICON=$root$ICON
    # When install.sh runs from $SHARE itself, keep a copy of the source first.
    if [ "$P" = "$SHARE/payload" ]; then
        stage=$(mktemp -d)
        trap 'rm -rf "$stage"' EXIT
        cp -a "$SHARE/." "$stage/"
        P=$stage/payload SRC=$stage
    fi
    put_dir "$SHARE" fill_share
    put_dir "$TPL_DIR" fill_templates
    put_dir "$CGI_DIR" fill_cgi
    mkdir -p "$(dirname "$ICON")"
    install -m 0644 "$P/icons/infrafence.png" "$ICON.infrafence-new"
    mv -f "$ICON.infrafence-new" "$ICON"
    if [ -z "$root" ]; then
        chown -R root:root "$SHARE" "$TPL_DIR" "$CGI_DIR" "$ICON"
    fi
}

register() {
    if [ ! -x "$CPANEL/bin/register_appconfig" ]; then
        warn "cPanel & WHM not found; files are installed but the plugin is not registered"
        return 0
    fi
    if ! "$CPANEL/bin/register_appconfig" "$SHARE/infrafence.conf" >/dev/null; then
        warn "register_appconfig failed"
        return 1
    fi
    say "Registered with WHM: WHM » Plugins » InfraFence"
}

# ------------------------------------------------------------------ main

case $MODE in
    files)
        [ -n "$DESTDIR" ] || die "--files-only needs --destdir DIR"
        install_files "$DESTDIR"
        say "Files installed under $DESTDIR"
        ;;
    register)
        [ "$(id -u)" -eq 0 ] || die "run this script as root"
        register || exit 1
        ;;
    check)
        if preflight; then say "All checks passed. Nothing was changed."; else exit 1; fi
        ;;
    install)
        preflight || die "nothing was changed"
        fresh=1
        [ -f "$SHARE/$MARKER" ] && fresh=0
        install_files
        if ! register; then
            if [ "$fresh" -eq 1 ]; then
                rm -rf "$CGI_DIR" "$TPL_DIR" "$SHARE" "$ICON"
                warn "the new files were removed"
            fi
            exit 1
        fi
        say "InfraFence WHM plugin $VERSION installed. No services were restarted."
        ;;
esac
