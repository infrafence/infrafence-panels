#!/bin/sh
# Runs test/install/run.sh in a fresh AlmaLinux container per release.
#   test/install-test.sh [8 9 10]
set -eu
WHM=$(cd "$(dirname "$0")/.." && pwd)
RELEASES=${*:-"8 9 10"}
rc=0
for r in $RELEASES; do
    echo "== AlmaLinux $r"
    docker build -q --build-arg BASE=almalinux:$r -t infrafence-whm-test:alma$r -f "$WHM/dev/Dockerfile.test" "$WHM/dev" >/dev/null
    docker run --rm -v "$WHM":/src/whm:ro infrafence-whm-test:alma$r sh /src/whm/test/install/run.sh || rc=1
done
exit $rc
