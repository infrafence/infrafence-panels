#!/bin/sh
# Inside a throwaway container: installs the plugin built from a loose source
# (umask 002, group- and world-writable files) and checks that nothing it
# installed can be written by anyone but its owner. Run by test/umask-test.sh.
#   modes.sh source|tarball|rpm|deb
set -u
[ -f /.dockerenv ] || [ -n "${container:-}" ] || { echo "refusing to run outside a container" >&2; exit 1; }
KIND=$1
HERE=$(cd "$(dirname "$0")" && pwd)
D=/usr/local/cpanel/whostmgr/docroot
PATHS="$D/cgi/infrafence $D/templates/infrafence $D/addon_plugins/infrafence.png /usr/local/share/infrafence-whm /var/cpanel/apps/infrafence.conf"

umask 002
sh "$HERE/fake-cpanel.sh" >/dev/null
case $KIND in
  source)  sh /loose/whm/install.sh >/dev/null ;;
  tarball) mkdir -p /tmp/x && tar xzf /dist/infrafence-whm-*.tar.gz -C /tmp/x && sh /tmp/x/infrafence-whm-*/install.sh >/dev/null ;;
  rpm)     rpm -i /dist/*.noarch.rpm ;;
  deb)     dpkg -i /dist/*_all.deb >/dev/null ;;
esac || { echo "not ok - $KIND: install failed"; exit 1; }

for p in $PATHS; do
  [ -e "$p" ] || { echo "not ok - $KIND: $p missing"; exit 1; }
done
bad=$(find $PATHS ! -type l -perm /022 2>/dev/null)
notroot=$(find $PATHS ! -user root 2>/dev/null)
if [ -n "$bad" ] || [ -n "$notroot" ]; then
  echo "not ok - $KIND: writable by group/others or not owned by root:"
  echo "$bad $notroot" | tr ' ' '\n' | sed '/^$/d; s/^/#   /' | head -20
  exit 1
fi
echo "ok - $KIND: $(find $PATHS | wc -l) installed paths, none writable by group or others, all owned by root"
