#!/usr/bin/env bash
# Shared helpers of the wildix-live-monitor skill. Source it from a script:
#   . "$(dirname "$0")/lib.sh"
# Needs: bash 3.2+, jq, Node.js 22+ (its built-in WebSocket; no npm packages).
#
# Authentication belongs to the wildix-auth skill: it loads ID_TOKEN without ever printing it.
# The service: the live stream of Wildix Data Analytics (WDA), wss://wda-ws.wildix.com. The token is only ever sent
# there; WILDIX_WDA_WS_URL overrides the address only together with WILDIX_ALLOW_CUSTOM_URL=1 (tests).
set -euo pipefail

LIVE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v jq >/dev/null || { echo "Error: jq is required (brew install jq)" >&2; exit 1; }
command -v node >/dev/null || { echo "Error: Node.js 22 or newer is needed (https://nodejs.org)" >&2; exit 1; }
_node_major=$(node -p 'process.versions.node.split(".")[0]')
[[ "$_node_major" -ge 22 ]] || { echo "Error: Node.js 22 or newer is needed, found $(node -v)" >&2; exit 1; }

for _d in "$LIVE_LIB_DIR/../.." "${WILDIX_SKILLS_DIR:-}" "$HOME/.agents/skills" "$HOME/.claude/skills"; do
  [ -f "$_d/wildix-auth/scripts/load-token.sh" ] && { . "$_d/wildix-auth/scripts/load-token.sh"; break; } || true
done
command -v wildix_require_token >/dev/null || { echo "Error: the wildix-auth skill is not installed. Ask the user to run: npx skills add gorets/wildix-skills --s wildix-auth" >&2; exit 2; }
wildix_require_token || exit 2

die() { echo "Error: $*" >&2; exit 1; }

check_int() { [[ "$2" =~ ^[0-9]{1,12}$ && "$((10#$2))" -ge "$3" && "$((10#$2))" -le "$4" ]] || die "$1 must be a whole number from $3 to $4: $2"; }

if [[ -n "${WILDIX_WDA_WS_URL:-}" ]]; then
  [[ "${WILDIX_ALLOW_CUSTOM_URL:-}" == 1 ]] || die "WILDIX_WDA_WS_URL is honoured only with WILDIX_ALLOW_CUSTOM_URL=1 (tests)"
  LIVE_WS_URL="${WILDIX_WDA_WS_URL%/}"
else
  LIVE_WS_URL="wss://wda-ws.wildix.com"
fi

# run_live ARGS... : runs live.mjs with the token on stdin (never on a command line or in the environment).
# A watch outlives a token: live.mjs exits with 75 when it needs a fresh one, and is started again here.
run_live() {
  local state rc again=()
  state=$(mktemp)
  while :; do
    rc=0
    printf '%s' "$ID_TOKEN" | LIVE_WS_URL="$LIVE_WS_URL" node "$LIVE_LIB_DIR/live.mjs" "$@" --state "$state" ${again[@]+"${again[@]}"} || rc=$?
    [[ $rc -eq 75 ]] || { rm -f "$state"; return "$rc"; }
    unset ID_TOKEN
    wildix_require_token || { rm -f "$state"; return 2; }
    again=(--reconnected)
  done
}
