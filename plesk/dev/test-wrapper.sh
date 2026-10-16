#!/bin/sh
# Checks that the root wrapper refuses everything outside the panel contract.
# Run as root on a test server or container where the extension is installed:
#
#   sh test-wrapper.sh [path to infrafence-panel]
#
# Only invalid input is sent, so the agent (real or mock) is never asked to change anything.
W=${1:-/usr/local/psa/admin/sbin/modules/infrafence/infrafence-panel}
fails=0

expect() {
    want=$1
    shift
    out=$("$W" "$@" 2>&1)
    case "$out" in
        *"\"error\":\"$want\""*) printf 'ok    %-22s %s\n' "$want" "$*" ;;
        *) printf 'FAIL  %-22s %s\n      got: %s\n' "$want" "$*" "$out"; fails=$((fails + 1)) ;;
    esac
}

expect invalid_arguments
expect unknown_command      rm -rf /
expect unknown_command      'status;id'
expect invalid_ip           unban '1.2.3.4;id' --actor plesk:admin
expect invalid_ip           unban '$(id)' --actor plesk:admin
expect invalid_ip           unban 1.2.3.4/24 --actor plesk:admin
expect invalid_ip           allow 10.0.0.0/8 --actor plesk:admin
expect invalid_ip           allow 2001:db8::/32 --actor plesk:admin
expect invalid_ip           allow 999.1.1.1 --actor plesk:admin
expect invalid_arguments    unban 1.2.3.4
expect invalid_arguments    unban 1.2.3.4 --actor 'x y'
expect invalid_arguments    unban 1.2.3.4 --actor -x
expect invalid_arguments    unban 1.2.3.4 5.6.7.8 --actor plesk:admin
expect invalid_arguments    allow 1.2.3.4 --note '-x' --actor plesk:admin
expect invalid_arguments    allow 1.2.3.4 --note "$(printf 'a\nb')" --actor plesk:admin
expect invalid_arguments    bans --limit 5000
expect invalid_arguments    bans --limit 0
expect invalid_arguments    bans --actor plesk:admin
expect invalid_arguments    events --since 'yesterday'
expect invalid_arguments    status --json
expect invalid_path         scan /etc --actor plesk:admin
expect invalid_path         scan /var/www/vhosts/../../etc --actor plesk:admin
expect invalid_path         scan /var/www/vhosts --actor plesk:admin
expect invalid_path         scan relative/path --actor plesk:admin

[ "$fails" -eq 0 ] && echo "all checks passed" || { echo "$fails check(s) failed"; exit 1; }
