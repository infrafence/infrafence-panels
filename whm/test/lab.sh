#!/bin/sh
# Long-running test containers, for poking at an installed plugin by hand.
#
#   test/lab.sh up     start them (fake cPanel tree, plugin installed, mock agent)
#   test/lab.sh down   stop and remove them
#   test/lab.sh ls     list them
#
# infrafence-whm-lab-alma8, -alma9, -alma10: installed from the tarball with install.sh
# infrafence-whm-lab-ubuntu2404:             installed from the .deb (run packaging/build.sh first)
#
# Inside, run the CGI as WHM would:
#   docker exec -it infrafence-whm-lab-alma9 sh -c '. /src/whm/test/install/cgi.sh; cgi GET page=bans; cat /tmp/cgi.out'
set -eu
WHM=$(cd "$(dirname "$0")/.." && pwd)
P=infrafence-whm-lab

setup='
  set -e
  sh /src/whm/test/install/fake-cpanel.sh >/dev/null
  mkdir -p /opt/infrafence/bin
  cp /src/whm/dev/mock-agent /opt/infrafence/bin/infrafence-agent
  cp -r /src/whm/dev/fixtures /src/whm/dev/scenarios /opt/infrafence/bin/
  chown -R root:root /opt/infrafence && chmod 0755 /opt/infrafence/bin/infrafence-agent
  true'

case ${1:-} in
  up)
    for r in 8 9 10; do
      docker build -q --build-arg BASE=almalinux:$r -t infrafence-whm-test:alma$r -f "$WHM/dev/Dockerfile.test" "$WHM/dev" >/dev/null
      docker rm -f $P-alma$r >/dev/null 2>&1 || true
      docker run -d --name $P-alma$r -v "$WHM":/src/whm:ro infrafence-whm-test:alma$r sleep infinity >/dev/null
      docker exec $P-alma$r sh -c "$setup; sh /src/whm/install.sh >/dev/null"
      echo "$P-alma$r: plugin installed with install.sh"
    done
    deb=$(ls "$WHM"/dist/*_all.deb 2>/dev/null | head -1)
    if [ -n "$deb" ]; then
      docker rm -f $P-ubuntu2404 >/dev/null 2>&1 || true
      docker run -d --name $P-ubuntu2404 -v "$WHM":/src/whm:ro -v "$WHM/dist":/dist:ro ubuntu:24.04 sleep infinity >/dev/null
      docker exec $P-ubuntu2404 sh -c "apt-get -qq update >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get -qq install -y libtemplate-perl >/dev/null 2>&1; $setup; dpkg -i /dist/$(basename "$deb") >/dev/null"
      echo "$P-ubuntu2404: plugin installed from $(basename "$deb")"
    fi
    ;;
  down)
    docker ps -aq --filter "name=$P-" | xargs -r docker rm -f >/dev/null
    echo "removed"
    ;;
  ls)
    docker ps -a --filter "name=$P-" --format '{{.Names}}\t{{.Status}}'
    ;;
  *)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
