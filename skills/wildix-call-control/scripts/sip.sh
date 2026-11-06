#!/usr/bin/env bash
# Live view of the logged-in user's calls over SIP, and the call commands only SIP has (recording, conference
# transfer). A headless SIP user of the extension: it carries no media and turns every incoming call down, so the
# user's real phones keep ringing as before. Needs Node.js 24+ and npm.
# Usage: sip.sh <command> [args]
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: sip.sh <command> [args]
  watch [--calls-only] [--for SECONDS]
                        one line per event until stopped (or for SECONDS): READY (calls, devices, presence,
                        ringing mode), CALL_START, CALL_UPDATE, CALL_END, DEVICES, PRESENCE, ACTIVE_DEVICE,
                        RECONNECTING, RECONNECTED, ERROR. Each line is `<EVENT> <json>`
  calls                 the user's current calls as SIP sees them (direction, state ringing|answered|held,
                        remote party, recording), then exit
  record <callId> on|off|pause|unpause
                        start, stop, pause or resume the recording of a call (needs the user's right to record)
  conference-transfer <callId> <number>
                        join the call and <number> in a conference; when the user hangs up the other two stay
<callId> is the call's id from `sip.sh calls` or `calls.sh list`.
The first run installs the two pinned npm packages it needs (from sip/package-lock.json) into a cache folder.
U
  exit 1; }

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift
case "$cmd" in
  watch|calls) ;;
  record) [[ $# -eq 2 ]] || usage; check_call_id "$1" ;;
  conference-transfer) [[ $# -eq 2 ]] || usage; check_call_id "$1"; set -- "$1" "$(norm_number "$2")" ;;
  *) usage ;;
esac

command -v node >/dev/null || die "Node.js 24 or newer is needed for the live view (https://nodejs.org)"
command -v npm >/dev/null || die "npm is needed for the live view (it comes with Node.js)"
node_major=$(node -p 'process.versions.node.split(".")[0]')
[[ "$node_major" -ge 24 ]] || die "Node.js 24 or newer is needed for the live view, found $(node -v)"

ext=$(claim custom:pbx_user_extension)
[[ "$ext" =~ ^[0-9]+$ ]] || die "this login has no PBX extension (custom:pbx_user_extension)"

# The packages go to a cache folder (the skill folder may be read-only or shared) and are installed exactly as the
# lockfile pins them, without install scripts. They are reinstalled when the lockfile of the skill changes.
SIP_SRC="$CC_LIB_DIR/sip"
SIP_RUN="${XDG_CACHE_HOME:-$HOME/.cache}/wildix-call-control/sip"
if ! cmp -s "$SIP_SRC/package-lock.json" "$SIP_RUN/package-lock.json" || [[ ! -d "$SIP_RUN/node_modules/@gorets/wildix-callcontrol" ]]; then
  echo "Installing the packages of the live view into $SIP_RUN (once)…" >&2
  mkdir -p "$SIP_RUN"
  cp "$SIP_SRC/package.json" "$SIP_SRC/package-lock.json" "$SIP_RUN/"
  ( cd "$SIP_RUN" && npm ci --omit=dev --ignore-scripts --no-audit --no-fund --loglevel=error >&2 ) || die "npm could not install the packages of the live view"
fi
cp "$SIP_SRC/sip.mjs" "$SIP_RUN/sip.mjs"

# The token goes to node on stdin, never on a command line or in the environment.
printf '%s' "$ID_TOKEN" | CC_PBX_BASE="$CC_BASE" CC_EXTENSION="$ext" exec node "$SIP_RUN/sip.mjs" "$cmd" "$@"
