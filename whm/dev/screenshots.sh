#!/bin/sh
# Renders every screen (dev/render) and takes screenshots with headless Chrome.
#   dev/screenshots.sh OUTDIR [LANG]
# WIDTH and HEIGHT set the window (default 1280x900).
# Needs Docker (for Template Toolkit) and Google Chrome or Chromium.
set -eu
OUT=${1:?usage: dev/screenshots.sh OUTDIR [LANG]}
LANG_=${2:-en}
HERE=$(cd "$(dirname "$0")/.." && pwd)
CHROME=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
[ -x "$CHROME" ] || CHROME=$(command -v chromium || command -v google-chrome)
PORT=${PORT:-8765}

mkdir -p "$OUT/html" "$OUT/png"
OUT=$(cd "$OUT" && pwd)
docker build -q -t infrafence-whm-test:alma9 -f "$HERE/dev/Dockerfile.test" "$HERE/dev" >/dev/null
docker run --rm -v "$HERE/..":/src:ro -v "$OUT/html":/out infrafence-whm-test:alma9 perl dev/render /out "$LANG_"

python3 -m http.server "$PORT" --bind 127.0.0.1 -d "$OUT/html" >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
sleep 1

for f in "$OUT/html/$LANG_"/*.html; do
  name=$(basename "$f" .html)
  [ "$name" = index ] && continue
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --user-data-dir="$OUT/.chrome" \
    --window-size=${WIDTH:-1280},${HEIGHT:-900} --screenshot="$OUT/png/$LANG_-$name.png" \
    "http://127.0.0.1:$PORT/$LANG_/$name.html" >/dev/null 2>&1
  echo "$OUT/png/$LANG_-$name.png"
done
