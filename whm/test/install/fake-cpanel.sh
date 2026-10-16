#!/bin/sh
# Builds a fake cPanel & WHM tree inside a throwaway container, with just
# enough for install.sh, uninstall.sh and the CGI to run:
#   - /usr/local/cpanel/{cpanel,version,bin/register_appconfig,bin/unregister_appconfig}
#   - /usr/local/cpanel/3rdparty/bin/perl (the system perl)
#   - stub Whostmgr::ACLS, Cpanel::Template and Cpanel::Locale
#   - the stub master template under whostmgr/docroot/templates
# Never run this on a real server.
set -eu
[ -f /.dockerenv ] || [ -n "${container:-}" ] || { echo "refusing to run outside a container" >&2; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
WHM=$(cd "$HERE/../.." && pwd)
C=/usr/local/cpanel

mkdir -p $C/bin $C/3rdparty/bin $C/Whostmgr $C/Cpanel /var/cpanel/apps \
         $C/whostmgr/docroot/cgi $C/whostmgr/docroot/templates/master_templates $C/whostmgr/docroot/addon_plugins
printf '#!/bin/sh\nexit 0\n' > $C/cpanel
echo "${FAKE_CPANEL_VERSION:-11.138.0.5}" > $C/version
ln -sf /usr/bin/perl $C/3rdparty/bin/perl

cat > $C/bin/register_appconfig <<'EOS'
#!/bin/sh
# Fake: validates the file like WHM would need it and copies it in place.
set -eu
[ "${FAKE_REGISTER_FAIL:-}" = 1 ] && { echo "fake failure" >&2; exit 1; }
f=$1
for k in name service url acls displayname entryurl; do
  grep -q "^$k=" "$f" || { echo "missing $k" >&2; exit 1; }
done
name=$(sed -n 's/^name=//p' "$f")
cp "$f" "/var/cpanel/apps/$name.conf"
echo "$(date +%s) register $name" >> /var/log/fake-appconfig.log
EOS
cat > $C/bin/unregister_appconfig <<'EOS'
#!/bin/sh
set -eu
rm -f "/var/cpanel/apps/$1.conf"
echo "$(date +%s) unregister $1" >> /var/log/fake-appconfig.log
EOS
chmod 0755 $C/bin/* $C/cpanel

cat > $C/Whostmgr/ACLS.pm <<'EOS'
package Whostmgr::ACLS;
sub init_acls { 1 }
sub hasroot { ( $ENV{FAKE_ACL} || 'all' ) eq 'all' ? 1 : 0 }
1;
EOS
cat > $C/Cpanel/Locale.pm <<'EOS'
package Cpanel::Locale;
sub get_handle { bless {}, shift }
sub get_language_tag { $ENV{FAKE_LOCALE} || 'en' }
1;
EOS
cat > $C/Cpanel/Template.pm <<'EOS'
package Cpanel::Template;
use Template;
sub process_template {
    my ( $service, $args ) = @_;
    my %vars = %$args;
    my $file  = delete $vars{template_file};
    my $print = delete $vars{print};
    my $tt = Template->new( INCLUDE_PATH => ['/usr/local/cpanel/whostmgr/docroot/templates'] ) or die Template->error;
    my $out = '';
    $tt->process( $file, \%vars, \$out ) or die $tt->error;
    print $out if $print;
    return 1;
}
1;
EOS
cp "$WHM/dev/stub/master_templates/master.tmpl" $C/whostmgr/docroot/templates/master_templates/master.tmpl

# Anything that would restart a service logs the call instead.
for s in systemctl service; do
  printf '#!/bin/sh\necho "%s $*" >> /var/log/fake-restarts.log\n' "$s" > /usr/local/sbin/$s
  chmod 0755 /usr/local/sbin/$s
done
mkdir -p /scripts
for s in restartsrv_cpsrvd restartsrv_httpd restartsrv_apache; do
  printf '#!/bin/sh\necho "%s $*" >> /var/log/fake-restarts.log\n' "$s" > /scripts/$s
  chmod 0755 /scripts/$s
done
echo "fake cPanel tree ready"
