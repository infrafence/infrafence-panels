#!/bin/sh
# Installs and removes dist/*.rpm on AlmaLinux 8, 9, 10 and CentOS 7, and
# dist/*.deb on Ubuntu 24.04, each in a fresh container. Run packaging/build.sh first.
set -eu
WHM=$(cd "$(dirname "$0")/.." && pwd)
rc=0
for r in 8 9 10; do
    echo "== rpm on AlmaLinux $r"
    docker build -q --build-arg BASE=almalinux:$r -t infrafence-whm-test:alma$r -f "$WHM/dev/Dockerfile.test" "$WHM/dev" >/dev/null
    docker run --rm -v "$WHM":/src/whm:ro -v "$WHM/dist":/dist:ro infrafence-whm-test:alma$r sh /src/whm/test/install/package.sh rpm || rc=1
done
# CentOS 7 (cPanel 110): rpm 4.11 must read the package. Its repositories are
# archived, so no Perl here: the package is checked, the CGI runs with cPanel's
# own Perl on a real server and is tested on AlmaLinux above.
echo "== rpm on CentOS 7"
docker run --rm -v "$WHM":/src/whm:ro -v "$WHM/dist":/dist:ro -e NO_CGI=1 -e FAKE_CPANEL_VERSION=11.110.0.158 centos:7 \
    sh /src/whm/test/install/package.sh rpm || rc=1
echo "== deb on Ubuntu 24.04"
docker run --rm -v "$WHM":/src/whm:ro -v "$WHM/dist":/dist:ro ubuntu:24.04 sh -c '
  apt-get -qq update >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get -qq install -y libtemplate-perl >/dev/null &&
  sh /src/whm/test/install/package.sh deb' || rc=1
exit $rc
