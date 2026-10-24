#!/bin/sh
# Lists the event types the agent sends to the dashboard, from its source.
#   dev/agent-event-types.sh AGENT_REPO [REF] > dev/event-types.txt
# REF defaults to origin/main (fetch first). The patterns follow how the agent
# builds its events today; review the diff, and add a name for every new type
# to plugin/locale/*.json (t/50-i18n.t fails until all six languages have one).
set -eu
REPO=${1:?usage: dev/agent-event-types.sh AGENT_REPO [REF]}
REF=${2:-origin/main}

# src PATTERN [EXCLUDED PATHS...]: matching lines of the agent's non-test Go code.
src() {
  pat=$1
  shift
  git -C "$REPO" grep -h -E "$pat" "$REF" -- '*.go' ':!*_test.go' "$@" || true
}

{
  echo '# Event types the InfraFence agent sends to the dashboard.'
  echo "# Made by dev/agent-event-types.sh from the agent's $REF; one per line."
  {
    # api.EventRequest{Type: "..."} and the monitors' events
    # (malware findings, firewall rules and session commands have a Type of their own)
    src '(^|[^A-Za-z])Type:[[:space:]]*"[a-z0-9_]+"' ':!internal/malware' ':!internal/firewall' ':!internal/session' |
      perl -ne 'print "$1\n" while /(?<![A-Za-z])Type:\s*"([a-z0-9_]+)"/g'
    # helpers that take the type first: reportEvent, report, trustReport, panelEventFor, event, onEvent
    src '(reportEvent|report|trustReport|panelEventFor|event|onEvent)\(' |
      perl -ne 'print "$2\n" while /\b(reportEvent|report|trustReport|panelEventFor|event|onEvent)\((?:client, |ip, |ipAddr, |"0\.0\.0\.0", )?"([a-z0-9_]+)"/g'
    # web watcher: scored types, threshold rules, instant-ban patterns, WAF catalog
    src '(addScore|thresholdRule|EventType:|^[[:space:]]*"[a-z0-9_]+":[[:space:]]+[0-9]+,$|^\}, "[a-z0-9_]+"\},)' |
      perl -ne 'print "$1\n" if /addScore\(ip, "([a-z0-9_]+)"/ || /thresholdRule\{"[^"]+", "([a-z0-9_]+)"/ || /EventType:\s*"([a-z0-9_]+)"/ || /^\s*"([a-z0-9_]+_[a-z0-9_]+)":\s+\d+,$/ || /^\}, "([a-z0-9_]+)"\},/'
    # mail, database and FTP watchers send the matched pattern's reason
    git -C "$REPO" grep -h -E 'Reason:[[:space:]]*"' "$REF" -- internal/watcher/maillog.go internal/watcher/dblog.go internal/watcher/ftplog.go |
      perl -ne 'print "$1\n" while /Reason:\s*"([a-z0-9_]+)"/g'
    # ModSecurity attack categories map to a type
    git -C "$REPO" grep -h -W 'func MapAttackToEventType' "$REF" -- internal/modsecurity ':!*_test.go' |
      perl -ne 'print "$1\n" while /return "([a-z0-9_]+)"/g'
    # firewall actions and virtual patches return their type with a severity
    git -C "$REPO" grep -h -E 'return "[a-z0-9_]+", "' "$REF" -- cmd/infrafence-agent/fwactions.go cmd/infrafence-agent/vpatch.go |
      perl -ne 'print "$1\n" if /return "([a-z0-9_]+)", "(?:info|warning|critical)"/'
  } | grep -v -x -E "critical|high|warning|info|low" | sort -u
} 
