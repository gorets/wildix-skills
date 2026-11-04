#!/bin/bash
# Library for scripts of other skills. Source it, then call `wildix_require_token`:
# it puts a valid IdToken into ID_TOKEN (exported) and never prints it, so the agent that runs
# a script never sees or passes a token: authentication stays inside the wildix-auth skill.
#
#   . "<skills dir>/wildix-auth/scripts/load-token.sh"
#   wildix_require_token || exit 2
#
# Which account:
#   1. ID_TOKEN already in the environment: kept as it is (tests, CI, a script run by hand).
#   2. WILDIX_EMAIL in the environment: that account.
#   3. exactly one authenticated session in the tokens directory: that one.
# Otherwise it prints a message and returns 2:
#   no session        -> the user has to log in with the wildix-auth skill (Mode 2)
#   several sessions  -> set WILDIX_EMAIL to one of them
# An expired token is refreshed by get-token.sh. The token is never part of a message.

_WILDIX_LOAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$_WILDIX_LOAD_DIR/config.sh"

# Prints the e-mails of the authenticated sessions, one per line.
wildix_session_emails() {
  local dir f
  dir=$(wildix_tokens_dir)
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.prod.json; do
    [ -f "$f" ] || continue
    jq -r '.email // empty' "$f" 2>/dev/null
  done
}

wildix_require_token() {
  if [ -n "${ID_TOKEN:-}" ]; then
    export ID_TOKEN
    return 0
  fi

  local email="${WILDIX_EMAIL:-}" emails count
  if [ -z "$email" ]; then
    emails=$(wildix_session_emails)
    count=$(printf '%s' "$emails" | grep -c . || true)
    if [ "$count" -eq 0 ]; then
      echo "Error: not logged in to Wildix. Log in with the wildix-auth skill, then run this again." >&2
      return 2
    elif [ "$count" -gt 1 ]; then
      echo "Error: several Wildix accounts are logged in. Set WILDIX_EMAIL to one of them and run this again:" >&2
      printf '%s\n' "$emails" | sed 's/^/  /' >&2
      return 2
    fi
    email="$emails"
  fi

  local token rc=0
  token=$(bash "$_WILDIX_LOAD_DIR/get-token.sh" "$email" 2>/dev/null) || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$token" ]; then
    echo "Error: could not get a valid Wildix token for the account (exit $rc). Log in again with the wildix-auth skill." >&2
    return 2
  fi
  ID_TOKEN="$token"
  export ID_TOKEN
}

# The e-mail of the user, read from the claims of the loaded IdToken (no network, no argument).
wildix_token_email() {
  : "${ID_TOKEN:?no token loaded}"
  python3 - <<'PY'
import base64, json, os
p = os.environ["ID_TOKEN"].split(".")[1]
p += "=" * (-len(p) % 4)
print(json.loads(base64.urlsafe_b64decode(p)).get("email", "").lower())
PY
}
