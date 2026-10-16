#!/bin/sh
# Builds the release files from a deliberately loose copy of the source
# (every file group- and world-writable, build umask 002) and checks that what
# install.sh, the tarball, the RPM and the .deb install is writable only by root.
set -eu
WHM=$(cd "$(dirname "$0")/.." && pwd)
LOOSE=$WHM/.umask-build
rm -rf "$LOOSE"
mkdir -p "$LOOSE/whm"
cp "$WHM/../LICENSE" "$LOOSE/"
(cd "$WHM" && tar cf - --exclude=./dist --exclude=./.umask-build --exclude=./docs/screenshots .) | (cd "$LOOSE/whm" && tar xf -)
chmod -R g+w,o+w "$LOOSE"

echo "== build with umask 002 from group/world-writable files"
DIST="$LOOSE/dist" BUILD_UMASK=002 sh "$LOOSE/whm/packaging/build.sh" >/dev/null 2>&1
if tar tvzf "$LOOSE"/dist/*.tar.gz | awk '{print $1}' | grep -q '^.....w\|^........w'; then
  echo "not ok - tarball has group- or world-writable entries"; rc=1
else
  echo "ok - tarball entries writable by owner only"; rc=0
fi

docker build -q --build-arg BASE=almalinux:9 -t infrafence-whm-test:alma9 -f "$WHM/dev/Dockerfile.test" "$WHM/dev" >/dev/null
for kind in source tarball rpm; do
  docker run --rm -v "$WHM":/src/whm:ro -v "$LOOSE":/loose:ro -v "$LOOSE/dist":/dist:ro \
    infrafence-whm-test:alma9 sh /src/whm/test/install/modes.sh $kind || rc=1
done
docker run --rm -v "$WHM":/src/whm:ro -v "$LOOSE/dist":/dist:ro ubuntu:24.04 sh -c '
  apt-get -qq update >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get -qq install -y libtemplate-perl >/dev/null 2>&1 &&
  sh /src/whm/test/install/modes.sh deb' || rc=1
rm -rf "$LOOSE"
exit $rc
