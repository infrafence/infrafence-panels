#!/bin/sh
# Installs and removes the built package inside a throwaway container with a
# fake cPanel tree. Run by test/package-test.sh.   package.sh rpm|deb
set -u
[ -f /.dockerenv ] || [ -n "${container:-}" ] || { echo "refusing to run outside a container" >&2; exit 1; }
KIND=$1
HERE=$(cd "$(dirname "$0")" && pwd)
D=/usr/local/cpanel/whostmgr/docroot
APP=/var/cpanel/apps/infrafence.conf
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok $PASS - $*"; }
nok() { FAIL=$((FAIL + 1)); echo "not ok - $*"; }
t()   { desc=$1; shift; if "$@" >/tmp/t.new 2>&1; then ok "$desc"; else nok "$desc"; sed 's/^/#   /' /tmp/t.new; fi; }

if [ "$KIND" = rpm ]; then
    PKG=$(ls /dist/*.noarch.rpm)
    add() { rpm -i "$PKG"; }
    del() { rpm -e infrafence-whm; }
    upg() { rpm -U --replacepkgs "$PKG"; }
else
    PKG=$(ls /dist/*_all.deb)
    add() { dpkg -i "$PKG"; }
    del() { dpkg -r infrafence-whm; }
    upg() { dpkg -i "$PKG"; }
fi

echo "# without cPanel: installs, does not register"
t "install" add
cp /tmp/t.new /tmp/add.out
t "warned" grep -q "not registered" /tmp/add.out
t "no AppConfig" test ! -e $APP
t "remove" del

echo "# with cPanel"
sh "$HERE/fake-cpanel.sh" >/dev/null
t "install"            add
t "registered"         test -f $APP
t "CGI"                test -x $D/cgi/infrafence/index.cgi
t "CGI compiles"       /usr/local/cpanel/3rdparty/bin/perl -c $D/cgi/infrafence/index.cgi
. "$HERE/cgi.sh"
t "CGI runs"           cgi GET ""
t "page rendered"      grep -q 'agent is not installed' /tmp/cgi.out
t "reinstall/upgrade"  upg
t "still registered"   test -f $APP
t "remove"             del
t "unregistered"       test ! -e $APP
t "files removed"      test ! -e $D/cgi/infrafence -a ! -e /usr/local/share/infrafence-whm -a ! -e $D/addon_plugins/infrafence.png
t "no restarts"        test ! -s /var/log/fake-restarts.log
echo "1..$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]
