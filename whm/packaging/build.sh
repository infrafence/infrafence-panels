#!/bin/sh
# Builds the release files into whm/dist/, using Docker only:
#   infrafence-whm-VERSION.tar.gz       (install.sh inside)
#   infrafence-whm-VERSION-1.noarch.rpm (AlmaLinux 8/9/10, CloudLinux)
#   infrafence-whm_VERSION_all.deb      (Ubuntu 24.04)
#
# File modes are normalised at every step (only the owner may write), so the
# result is the same whatever the umask or the modes of the checkout.
# BUILD_UMASK (default 022) is the umask inside the build containers; the
# tests build with 002 to prove the normalisation. DIST overrides whm/dist.
set -eu
WHM=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(cat "$WHM/VERSION")
DIST=${DIST:-$WHM/dist}
BUILD_UMASK=${BUILD_UMASK:-022}
mkdir -p "$DIST"
DIST=$(cd "$DIST" && pwd)

echo "== tar.gz and rpm (AlmaLinux 9)"
docker run --rm -v "$WHM/..":/repo:ro -v "$DIST":/dist -e VERSION="$VERSION" -e BUILD_UMASK="$BUILD_UMASK" almalinux:9 sh -euc '
  umask "$BUILD_UMASK"
  dnf -y -q install rpm-build tar gzip >/dev/null
  N=infrafence-whm-$VERSION
  mkdir -p /tmp/$N /root/rpmbuild/SOURCES
  cd /repo/whm
  cp -r install.sh uninstall.sh VERSION README.md plugin /tmp/$N/
  cp /repo/LICENSE /tmp/$N/LICENSE
  chmod -R u=rwX,go=rX /tmp/$N
  cd /tmp
  tar --owner=0 --group=0 --numeric-owner --mode=u=rwX,go=rX --sort=name --mtime="@0" -czf /dist/$N.tar.gz $N
  cp /dist/$N.tar.gz /root/rpmbuild/SOURCES/
  rpmbuild -bb --quiet --define "ifn_version $VERSION" --define "dist %{nil}" /repo/whm/packaging/rpm/infrafence-whm.spec
  cp /root/rpmbuild/RPMS/noarch/*.rpm /dist/
'

echo "== deb (Ubuntu 24.04)"
docker run --rm -v "$WHM":/src:ro -v "$DIST":/dist -e VERSION="$VERSION" -e BUILD_UMASK="$BUILD_UMASK" ubuntu:24.04 sh -euc '
  umask "$BUILD_UMASK"
  R=/tmp/root
  cd /tmp && tar xzf /dist/infrafence-whm-$VERSION.tar.gz
  sh /tmp/infrafence-whm-$VERSION/install.sh --files-only --destdir $R
  mkdir -p $R/DEBIAN $R/usr/share/doc/infrafence-whm
  sed "s/@VERSION@/$VERSION/" /src/packaging/deb/control.in > $R/DEBIAN/control
  install -m 0755 /src/packaging/deb/postinst /src/packaging/deb/prerm $R/DEBIAN/
  install -m 0644 /tmp/infrafence-whm-$VERSION/LICENSE /tmp/infrafence-whm-$VERSION/README.md $R/usr/share/doc/infrafence-whm/
  chmod -R u+rwX,go-w $R
  dpkg-deb --root-owner-group --build $R /dist/infrafence-whm_${VERSION}_all.deb >/dev/null
'
ls -l "$DIST"
