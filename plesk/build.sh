#!/bin/sh
# Builds the installable extension zip: dist/infrafence-plesk-<version>-<release>.zip
#
#   ./build.sh            build in Docker (php:8.3-cli for the checks, node:20 for the UI);
#                         nothing is needed on the host but Docker
#   ./build.sh --local    build with the host's PHP, Node.js and Yarn
#
# Install it with:  plesk bin extension -i dist/infrafence-plesk-<version>-<release>.zip
set -eu

cd "$(dirname "$0")"
# Build images pinned by digest (multi-arch index), so a build always uses the same toolchain.
# To update: docker buildx imagetools inspect node:20-bookworm (and php:8.3-cli), take the Digest.
NODE_IMAGE=${NODE_IMAGE:-node:20-bookworm@sha256:8f693eaa7e0a8e71560c9a82b55fd54c2ae920a2ba5d2cde28bac7d1c01c9ba5}

PHP_IMAGE=${PHP_IMAGE:-php:8.3-cli@sha256:aafe21201943a8a6e497ddfb471e2ce68ada76adede38c7d61fede8918b24319}

check_php() {
    for f in $(find src/plib src/htdocs -name '*.php' -o -name '*.phtml'); do
        php -l "$f" >/dev/null || exit 1
    done
    php dev/check-locales.php
    bash -n src/sbin/infrafence-panel
}

if [ "${1:-}" = "--check-php" ]; then
    check_php
    exit 0
fi

if [ "${1:-}" != "--local" ] && [ "${1:-}" != "--in-container" ]; then
    docker run --rm -v "$PWD":/ext -w /ext "$PHP_IMAGE" sh ./build.sh --check-php
    exec docker run --rm \
        -v "$PWD":/ext -w /ext \
        -e HOME=/tmp -u "$(id -u):$(id -g)" \
        "$NODE_IMAGE" sh ./build.sh --in-container
fi

if [ "${1:-}" = "--local" ]; then
    check_php
fi

python3 dev/check-mock.py >/dev/null || { python3 dev/check-mock.py; exit 1; }

if [ -f yarn.lock ]; then
    yarn install --frozen-lockfile --non-interactive --ignore-scripts
else
    yarn install --non-interactive --ignore-scripts
fi
yarn build

version=$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' src/meta.xml | head -1)
release=$(sed -n 's:.*<release>\(.*\)</release>.*:\1:p' src/meta.xml | head -1)
out="dist/infrafence-plesk-${version}-${release}.zip"
mkdir -p dist
rm -f "$out"

python3 - "$out" <<'PY'
import os, sys, zipfile

out = sys.argv[1]
src = "src"
skip_dirs = {os.path.join(src, "frontend")}
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(src):
        dirs[:] = sorted(d for d in dirs if os.path.join(root, d) not in skip_dirs)
        for name in sorted(files):
            if name.endswith(".map") or name == ".DS_Store":
                continue
            path = os.path.join(root, name)
            arc = os.path.relpath(path, src)
            info = zipfile.ZipInfo(arc, date_time=(2026, 1, 1, 0, 0, 0))
            # Plesk installs sbin files as 0755 root:root whatever the zip says; see sbin/infrafence-panel.
            mode = 0o755 if arc.startswith("sbin/") else 0o644
            info.external_attr = (0o100000 | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(path, "rb") as f:
                z.writestr(info, f.read())
print(out)
PY
