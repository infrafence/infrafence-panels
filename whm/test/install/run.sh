#!/bin/sh
# install.sh / uninstall.sh / CGI test, run as root inside a throwaway
# AlmaLinux container by test/install-test.sh. Never run it on a real server.
set -u
[ -f /.dockerenv ] || [ -n "${container:-}" ] || { echo "refusing to run outside a container" >&2; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
WHM=${WHM_SRC:-$(cd "$HERE/../.." && pwd)}
C=/usr/local/cpanel
D=$C/whostmgr/docroot
SHARE=/usr/local/share/infrafence-whm
APP=/var/cpanel/apps/infrafence.conf
PASS=0 FAIL=0

ok()   { PASS=$((PASS + 1)); echo "ok $PASS - $*"; }
nok()  { FAIL=$((FAIL + 1)); echo "not ok - $*"; }
# The output of the last command run by t/tnot is kept in /tmp/t.out.
t()    { desc=$1; shift; if "$@" >/tmp/t.new 2>&1; then ok "$desc"; else nok "$desc"; sed 's/^/#   /' /tmp/t.new; fi; mv /tmp/t.new /tmp/t.out; }
tnot() { desc=$1; shift; if "$@" >/tmp/t.new 2>&1; then nok "$desc"; sed 's/^/#   /' /tmp/t.new; else ok "$desc"; fi; mv /tmp/t.new /tmp/t.out; }
has()  { grep -q -- "$2" "$1"; }

snapshot() { find /usr/local /var/cpanel -xdev 2>/dev/null | grep -v '^/usr/local/share/man' | sort; }

. "$HERE/cgi.sh"

echo "# 1. without cPanel the checks fail and nothing changes"
before=$(snapshot)
tnot "install.sh refuses a server without cPanel" sh "$WHM/install.sh"
t "error names cPanel" has /tmp/t.out "cPanel & WHM is not installed"
t "nothing was changed" test "$before" = "$(snapshot)"

echo "# 2. fake cPanel tree"
t "fake tree" sh "$HERE/fake-cpanel.sh"

echo "# 3. --check changes nothing"
before=$(snapshot)
t "install.sh --check passes" sh "$WHM/install.sh" --check
t "nothing was changed" test "$before" = "$(snapshot)"

echo "# 4. old cPanel is refused"
echo 11.98.0.1 > $C/version
tnot "cPanel 98 refused" sh "$WHM/install.sh" --check
echo 11.138.0.5 > $C/version

echo "# 5. install"
t "install.sh" sh "$WHM/install.sh"
t "CGI installed"          test -x $D/cgi/infrafence/index.cgi
t "templates installed"    test -f $D/templates/infrafence/main.tmpl
t "icon installed"         test -f $D/addon_plugins/infrafence.png
t "modules installed"      test -f $SHARE/lib/InfraFence/WHM/App.pm
t "locales installed"      test -f $SHARE/locale/pt.json
t "map installed"          test -f $SHARE/map/world.json -a -f $SHARE/map/countries.json -a -f $SHARE/map/NOTICE
t "AppConfig registered"   test -f $APP
t "AppConfig acls=all"     has $APP '^acls=all$'
t "AppConfig url"          has $APP '^url=/cgi/infrafence/index.cgi$'
t "markers"                test -f $D/cgi/infrafence/.infrafence-whm -a -f $SHARE/.infrafence-whm
t "owned by root"          test "$(stat -c %U $D/cgi/infrafence/index.cgi)" = root
t "CGI compiles with cPanel perl" $C/3rdparty/bin/perl -c $D/cgi/infrafence/index.cgi

echo "# 6. install again (idempotent)"
first=$(snapshot)
t "install.sh again" sh "$WHM/install.sh"
t "same files" test "$first" = "$(snapshot)"
tnot "no temporary directories left" sh -c "ls -a $D/cgi $D/templates /usr/local/share | grep -q infrafence-new"

echo "# 7. repair from the installed copy"
t "$SHARE/install.sh" sh $SHARE/install.sh
t "same files" test "$first" = "$(snapshot)"

echo "# 8. CGI without the agent"
t "GET overview" cgi GET ""
t "status 200" has /tmp/cgi.out '^Status: 200'
t "not installed page" has /tmp/cgi.out 'agent is not installed'
t "wrapped in the master template" has /tmp/cgi.out 'class="whm-title"'

echo "# 9. CGI with the (mock) agent"
mkdir -p /opt/infrafence/bin
cp "$WHM/dev/mock-agent" /opt/infrafence/bin/infrafence-agent
cp -r "$WHM/dev/fixtures" /opt/infrafence/bin/fixtures
chown -R root:root /opt/infrafence; chmod 0755 /opt/infrafence/bin/infrafence-agent
t "overview"       cgi GET ""
t "protected"      has /tmp/cgi.out 'Protected'
t "bans"           cgi GET "page=bans"
t "ban listed"     has /tmp/cgi.out '203.0.113.7'
t "italian"        env FAKE_LOCALE=it_it sh -c ". $HERE/cgi.sh; cgi GET page=bans"
t "italian text"   has /tmp/cgi.out 'lang="it"'
t "confirm page"   cgi GET "page=bans&action=unban&ip=203.0.113.7"
t "confirm form"   has /tmp/cgi.out 'name="csrf" value="/cpsess7777777777"'
t "bad token"      cgi POST "" "page=bans&action=unban&ip=203.0.113.7&confirm=1&csrf=/cpsess0000000000"
t "403"            has /tmp/cgi.out '^Status: 403'
t "map on overview" cgi GET ""
t "map drawn"      has /tmp/cgi.out 'class="ifn-map-svg"'
t "language"       cgi POST "" "page=bans&action=language&lang=it&csrf=%2Fcpsess7777777777"
t "303"            has /tmp/cgi.out '^Status: 303'
t "prefs file"     test -f /var/cpanel/infrafence-whm/prefs/root.json
t "prefs 0600"     test "$(stat -c %a /var/cpanel/infrafence-whm/prefs/root.json)" = 600
t "prefs dir 0700" test "$(stat -c %a /var/cpanel/infrafence-whm/prefs)" = 700
t "now italian"    cgi GET "page=bans"
t "italian text"   has /tmp/cgi.out 'lang="it"'
t "other user"     env CGI_USER=reseller1 sh -c ". $HERE/cgi.sh; cgi GET page=bans"
t "keeps the WHM language" has /tmp/cgi.out 'lang="en"'
t "language bad token" cgi POST "" "page=bans&action=language&lang=de&csrf=/cpsess0000000000"
t "403"            has /tmp/cgi.out '^Status: 403'
t "language back to WHM" cgi POST "" "page=bans&action=language&lang=whm&csrf=%2Fcpsess7777777777"
t "unban"          cgi POST "" "page=bans&action=unban&ip=203.0.113.7&confirm=1&csrf=%2Fcpsess7777777777"
t "303"            has /tmp/cgi.out '^Status: 303'
t "location"       has /tmp/cgi.out '^Location: index.cgi?page=bans&notice=unban_ok&ip=203.0.113.7'
echo "# 9b. a plan without the plugin: no data asked, a forged action never reaches the agent"
printf 'MOCK_AGENT_SCENARIO=starter\nMOCK_AGENT_LOG=/tmp/mock-argv.log\n' > /opt/infrafence/bin/mock.conf
rm -f /tmp/mock-argv.log
t "starter overview" cgi GET ""
t "plan banner"    has /tmp/cgi.out 'included in the Basic, Pro and AutoMode plans'
t "forged unban"   cgi POST "" "page=bans&action=unban&ip=203.0.113.7&confirm=1&csrf=%2Fcpsess7777777777"
t "403"            has /tmp/cgi.out '^Status: 403'
t "agent asked"    test -s /tmp/mock-argv.log
tnot "only status asked" grep -v '"status"' /tmp/mock-argv.log
printf 'MOCK_AGENT_SCENARIO=unpaid\n' > /opt/infrafence/bin/mock.conf
t "unpaid overview" cgi GET ""
t "unpaid banner"  has /tmp/cgi.out 'subscription is not active'
echo "# 9c. a newer plugin release (agent 1.0.35+): a notice on every page, never when gated"
t "installed VERSION" test "$(cat $SHARE/VERSION)" = "$(cat "$WHM/VERSION")"
printf 'MOCK_AGENT_PLUGIN_LATEST=9.0.0\n' > /opt/infrafence/bin/mock.conf
t "update overview" cgi GET ""
t "update notice"  has /tmp/cgi.out 'A new version of the plugin is available (9.0.0)'
t "to Panel plugins" has /tmp/cgi.out 'href="https://infrafence.com/panels"'
t "both versions"  has /tmp/cgi.out 'Plugin version'
t "update bans"    cgi GET "page=bans"
t "notice on bans" has /tmp/cgi.out 'class="alert alert-info ifn-update"'
printf 'MOCK_AGENT_PLUGIN_LATEST=9.0.0\nMOCK_AGENT_SCENARIO=starter\n' > /opt/infrafence/bin/mock.conf
t "starter with a release" cgi GET ""
tnot "no notice when gated" grep -q 'ifn-update' /tmp/cgi.out
rm -f /opt/infrafence/bin/mock.conf /tmp/mock-argv.log
(FAKE_ACL=reseller; cgi GET "")
t "non-root user gets 403" has /tmp/cgi.out '^Status: 403'
chmod 0777 /opt/infrafence/bin/infrafence-agent
t "world-writable agent" cgi GET "page=bans"
t "refused"        has /tmp/cgi.out 'agent_untrusted'
chmod 0755 /opt/infrafence/bin/infrafence-agent
t "no stderr from the CGI" test ! -s /tmp/cgi.err

echo "# 10. conflicts are refused"
sh "$WHM/uninstall.sh" >/dev/null
mkdir -p $D/cgi/infrafence; echo foreign > $D/cgi/infrafence/index.cgi
before=$(snapshot)
tnot "foreign directory refused" sh "$WHM/install.sh"
t "nothing was changed" test "$before" = "$(snapshot)"
t "foreign file kept" has $D/cgi/infrafence/index.cgi foreign
rm -rf $D/cgi/infrafence

echo "# 11. a failed registration on a fresh install is rolled back"
tnot "register fails" env FAKE_REGISTER_FAIL=1 sh "$WHM/install.sh"
t "files removed" test ! -e $D/cgi/infrafence -a ! -e $SHARE -a ! -e $D/templates/infrafence

echo "# 12. uninstall"
sh "$WHM/install.sh" >/dev/null
t "uninstall --check" sh "$WHM/uninstall.sh" --check
cp /tmp/t.out /tmp/check.out
t "lists the CGI"     has /tmp/check.out "remove $D/cgi/infrafence"
t "still installed"   test -f $APP
t "uninstall.sh"      sh $SHARE/uninstall.sh
t "CGI removed"       test ! -e $D/cgi/infrafence
t "templates removed" test ! -e $D/templates/infrafence
t "icon removed"      test ! -e $D/addon_plugins/infrafence.png
t "share removed"     test ! -e $SHARE
t "prefs removed"     test ! -e /var/cpanel/infrafence-whm
t "unregistered"      test ! -e $APP
t "agent untouched"   test -x /opt/infrafence/bin/infrafence-agent
t "master template untouched" test -f $D/templates/master_templates/master.tmpl
t "uninstall again"   sh "$WHM/uninstall.sh"
t "says nothing to remove" sh "$WHM/uninstall.sh" --check
sh "$WHM/uninstall.sh" --check > /tmp/check.out
t "nothing to remove" has /tmp/check.out "nothing to remove"

echo "# 13. no service was restarted at any point"
t "no restarts" test ! -s /var/log/fake-restarts.log

echo "1..$((PASS + FAIL))"
echo "# passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
