#!/usr/bin/env bash
# Live events of the logged-in user's chats: new, edited and deleted messages, reactions, who read what,
# members, channel changes. One line per event, `<event> <json>`, until stopped, for a while or for a number of
# events. Read only: it sends nothing to any chat. Needs Node.js 22+ (no npm packages).
# Usage: watch.sh [options]
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: watch.sh [--channel C]... [--from USERID]... [--type TYPE]... [--mine] [--count N] [--for SECONDS] [--raw]
  --channel C      only these channels (an id or an inbox link); repeat for more
  --from USERID    only what these people did: their messages, their reading, their typing; repeat for more
  --type TYPE      only these events: a group (messages, reactions, reads, members, channels, typing) or one
                   event (message.new, read.receipt.updated, …); repeat for more
  --mine           also what the user did themselves (left out by default: their own messages and reading)
  --count N        stop after N events
  --for SECONDS    stop after this long
  --raw            print each event as the service sends it, not the short form
Lines: READY, then one per event (message.new {…}, reaction.new {…}, read.receipt.updated {…}, …),
RECONNECTING / RECONNECTED when the connection is renewed, END at the end.
U
  exit 1; }

nargs=(); count=0; secs=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) [[ $# -ge 2 ]] || usage; nargs+=(--channel "$(norm_channel "$2")"); shift 2 ;;
    --from) [[ $# -ge 2 ]] || usage; check_id "user id" "$2"; nargs+=(--from "$2"); shift 2 ;;
    --type)
      [[ $# -ge 2 ]] || usage
      [[ "$2" =~ ^(messages|reactions|reads|members|channels|typing|message\.(new|updated|deleted)|reaction\.(new|updated|deleted)|read\.(cursor|receipt)\.updated|member\.(added|updated|removed)|channel\.(created|updated|truncated|added|removed|hidden|visible|muted|unmuted|pinned|unpinned)|typing\.(start|stop))$ ]] || die "unknown event type: $2"
      nargs+=(--type "$2"); shift 2 ;;
    --mine) nargs+=(--mine); shift ;;
    --raw) nargs+=(--raw); shift ;;
    --count) [[ $# -ge 2 ]] || usage; check_int "--count" "$2" 1 100000; count=$((10#$2)); shift 2 ;;
    --for) [[ $# -ge 2 ]] || usage; check_int "--for" "$2" 1 604800; secs=$((10#$2)); shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

command -v node >/dev/null || die "Node.js 22 or newer is needed for watch.sh (https://nodejs.org)"
node_major=$(node -p 'process.versions.node.split(".")[0]')
[[ "$node_major" -ge 22 ]] || die "Node.js 22 or newer is needed for watch.sh, found $(node -v)"

# The websocket of a region: https://eu-1.stream.wildix.com -> wss://eu-1-ws.stream.wildix.com
if [[ -n "${WILDIX_STREAM_WS_URL:-}" ]]; then
  [[ "${WILDIX_ALLOW_CUSTOM_URL:-}" == 1 ]] || die "WILDIX_STREAM_WS_URL is honoured only with WILDIX_ALLOW_CUSTOM_URL=1 (tests)"
  WS_URL="${WILDIX_STREAM_WS_URL%/}"
else
  _host="${STREAM_BASE#https://}"
  WS_URL="wss://${_host%%.*}-ws.${_host#*.}"
  [[ "$WS_URL" =~ ^wss://[a-z0-9-]+(\.[a-z0-9-]+)*\.wildix\.com(:[0-9]+)?$ ]] || die "the websocket address must be wss://<host>.wildix.com, got: $WS_URL"
fi

ME=$(me_id)
deadline=0; [[ $secs -eq 0 ]] || deadline=$(( $(date +%s) + secs ))
state=$(mktemp); trap 'rm -f "$state"' EXIT
again=()

# A connection lasts at most two hours and the token is checked only when it opens: when the token is about to
# end, watch.mjs exits with 75 and is started again here with a fresh one, where it left off.
while :; do
  rc=0
  printf '%s' "$ID_TOKEN" | CHATS_WS_URL="$WS_URL" CHATS_API="$STREAM_API" CHATS_ME="$ME" \
    node "$STREAM_LIB_DIR/watch.mjs" ${nargs[@]+"${nargs[@]}"} --count "$count" --deadline "$deadline" --state "$state" ${again[@]+"${again[@]}"} || rc=$?
  [[ $rc -eq 75 ]] || exit "$rc"
  count=$(jq -r '.left // 0' "$state" 2>/dev/null || echo 0)
  unset ID_TOKEN
  wildix_require_token || exit 2
  again=(--reconnected)
done
