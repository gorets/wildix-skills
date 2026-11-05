#!/bin/bash
# Revokes the current refresh token for <email> and deletes the local token file.
# Usage: bash revoke-token.sh <email>
set -e
source "$(dirname "$0")/config.sh"

EMAIL="${1:?Usage: $0 <email>}"

TOKEN_FILE=$(wildix_token_file "$EMAIL")

if [ ! -f "$TOKEN_FILE" ]; then
  echo "No token file for $EMAIL" >&2
  exit 1
fi

REFRESH_TOKEN=$(jq -r '.RefreshToken' "$TOKEN_FILE")

PAYLOAD=$(jq -n \
  --arg token "$REFRESH_TOKEN" \
  --arg clientId "$WILDIX_CLIENT_ID" \
  '{"Token":$token,"ClientId":$clientId}')

# An error leaves the local file in place: the token is still valid and the call can be repeated.
wildix_cognito RevokeToken "$PAYLOAD" >/dev/null || { echo "The token was NOT revoked. Nothing was deleted." >&2; exit 1; }

rm -f "$TOKEN_FILE"
echo "Token revoked and local session deleted for $EMAIL"
