#!/bin/sh
# Checks that the root wrapper refuses everything outside the panel commands, with the agent's
# error codes (docs/panel-json.md). Run as root on a test server or container where the extension
# is installed:
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
    code=$?
    case "$out" in
        *"\"error\":\"$want\""*)
            if [ "$code" -eq 1 ]; then
                printf 'ok    %-20s %s\n' "$want" "$*"
            else
                printf 'FAIL  %-20s %s\n      exit status %s, want 1\n' "$want" "$*" "$code"
                fails=$((fails + 1))
            fi
            ;;
        *) printf 'FAIL  %-20s %s\n      got: %s\n' "$want" "$*" "$out"; fails=$((fails + 1)) ;;
    esac
}

expect bad_request
expect unknown_command      rm -rf /
expect unknown_command      'status;id'
expect invalid_ip           unban '1.2.3.4;id' --actor admin
expect invalid_ip           unban '$(id)' --actor admin
expect invalid_ip           unban 1.2.3.4/24 --actor admin
expect invalid_ip           allow 10.0.0.0/8 --actor admin
expect invalid_ip           allow 999.1.1.1 --actor admin
expect invalid_ip           disallow 10.0.0.0/8 --actor admin
expect invalid_actor        unban 1.2.3.4
expect invalid_actor        unban 1.2.3.4 --actor 'x y'
expect invalid_actor        unban 1.2.3.4 --actor plesk:admin
expect invalid_actor        unban 1.2.3.4 --actor -x
expect invalid_actor        unban 1.2.3.4 --actor aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
expect bad_request          unban 1.2.3.4 5.6.7.8 --actor admin
expect bad_request          allow 1.2.3.4 --note '-x' --actor admin
expect bad_request          allow 1.2.3.4 --note "$(printf 'a\nb')" --actor admin
expect bad_request          allow 1.2.3.4 --note "$(printf '%0201d' 0)" --actor admin
expect bad_request          bans --limit 501
expect bad_request          bans --limit 0
expect bad_request          bans --actor admin
expect bad_request          events --since 'yesterday'
expect bad_request          status --json
expect invalid_path         scan relative/path --actor admin
expect invalid_path         scan /var/www/vhosts/../../etc --actor admin
expect invalid_path         scan '/var/www/vhosts/a b' --actor admin
expect not_a_document_root  scan /etc --actor admin
expect not_a_document_root  scan /var/www/vhosts --actor admin
expect not_a_document_root  scan /var/www/vhosts/no-such-domain.example --actor admin
expect bad_request          --timeout 0 status
expect bad_request          --timeout 26 status
expect bad_request          --timeout x status
expect unknown_command      --timeout

# Run directly by anyone but root (here: nobody), the wrapper refuses before doing anything.
if command -v runuser >/dev/null 2>&1 && id nobody >/dev/null 2>&1; then
    out=$(runuser -u nobody -- "$W" status 2>&1)
    case "$out" in
        *'"error":"not_root"'*) printf 'ok    %-20s %s\n' not_root "status (as nobody)" ;;
        *) printf 'FAIL  %-20s %s\n      got: %s\n' not_root "status (as nobody)" "$out"; fails=$((fails + 1)) ;;
    esac
fi

[ "$fails" -eq 0 ] && echo "all checks passed" || { echo "$fails check(s) failed"; exit 1; }
