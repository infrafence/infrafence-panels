#!/bin/sh
# Installs the mock agent into a disposable Plesk test container or VM. Never on a production server.
#
#   ./install-mock.sh <container>     copy it into a running Docker container (uses docker cp/exec)
#   sudo ./install-mock.sh --here     install it on this machine
#
# Remove it again with:  rm -rf /usr/local/sbin/infrafence-agent /usr/local/share/infrafence-mock \
#                               /var/lib/infrafence-mock /etc/infrafence-mock
set -eu
cd "$(dirname "$0")"

if [ "${1:-}" != "--here" ]; then
    target=${1:?usage: install-mock.sh <container> | --here}
    docker exec "$target" mkdir -p /usr/local/share/infrafence-mock
    docker cp mock-agent "$target":/usr/local/share/infrafence-mock/mock-agent
    docker cp fixtures "$target":/usr/local/share/infrafence-mock/
    docker cp install-mock.sh "$target":/usr/local/share/infrafence-mock/install-mock.sh
    exec docker exec "$target" sh /usr/local/share/infrafence-mock/install-mock.sh --here
fi

[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required for the mock agent" >&2; exit 1; }

dir=/usr/local/share/infrafence-mock
mkdir -p "$dir" /etc/infrafence-mock
[ "$(pwd)" = "$dir" ] || { cp mock-agent "$dir/"; cp -r fixtures "$dir/"; }
chown -R root:root "$dir"
chmod 755 "$dir" "$dir/fixtures" "$dir/mock-agent"
chmod 644 "$dir"/fixtures/*.json
ln -sf "$dir/mock-agent" /usr/local/sbin/infrafence-agent
[ -f /etc/infrafence-mock/mode ] || echo running > /etc/infrafence-mock/mode
echo "mock agent installed: /usr/local/sbin/infrafence-agent -> $dir/mock-agent"
echo "switch state with: echo stopped|disconnected|running > /etc/infrafence-mock/mode"
