#!/bin/bash
# Signs out from ALL devices by invalidating all tokens via Cognito GlobalSignOut.
# Deletes the local token file afterwards.
# Usage: bash global-signout.sh <email>
set -e
source "$(dirname "$0")/config.sh"

EMAIL="${1:?Usage: $0 <email>}"

TOKEN_FILE=$(wildix_token_file "$EMAIL")

if [ ! -f "$TOKEN_FILE" ]; then
  echo "No token file for $EMAIL" >&2
  exit 1
fi

ACCESS_TOKEN=$(jq -r '.AccessToken' "$TOKEN_FILE")

PAYLOAD=$(jq -n \
  --arg token "$ACCESS_TOKEN" \
  '{"AccessToken":$token}')

# An error leaves the local file in place: the sessions are still valid. GlobalSignOut needs an AccessToken
# that has not expired: run get-token.sh first when the local one is older than an hour.
wildix_cognito GlobalSignOut "$PAYLOAD" >/dev/null || { echo "The sessions were NOT signed out. Nothing was deleted." >&2; exit 1; }

rm -f "$TOKEN_FILE"
echo "Global sign-out successful. All sessions invalidated for $EMAIL"
