#!/bin/bash
# Refreshes IdToken/AccessToken using the stored RefreshToken.
# Cognito refresh responses don't include a new RefreshToken — existing one is preserved.
# Usage: bash refresh-tokens.sh <email>
set -e
source "$(dirname "$0")/config.sh"

EMAIL="${1:?Usage: $0 <email>}"

TOKEN_FILE=$(wildix_token_file "$EMAIL")

if [ ! -f "$TOKEN_FILE" ]; then
  echo "No token file: $TOKEN_FILE" >&2
  exit 1
fi

REFRESH_TOKEN=$(jq -r '.RefreshToken' "$TOKEN_FILE")
EXISTING_EXPIRES_IN=$(jq -r '.ExpiresIn' "$TOKEN_FILE")

PAYLOAD=$(jq -n \
  --arg rt "$REFRESH_TOKEN" \
  --arg clientId "$WILDIX_CLIENT_ID" \
  '{"AuthFlow":"REFRESH_TOKEN_AUTH","ClientId":$clientId,"AuthParameters":{"REFRESH_TOKEN":$rt},"ClientMetadata":{}}')

RESPONSE=$(wildix_cognito InitiateAuth "$PAYLOAD")

if ! jq -e '.AuthenticationResult.IdToken' <<<"$RESPONSE" >/dev/null 2>&1; then
  echo "Refresh gave no new token. Log in again with the wildix-auth skill." >&2
  exit 1
fi

jq --arg email "$EMAIL" \
   --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   --arg rt "$REFRESH_TOKEN" \
   --arg exp "$EXISTING_EXPIRES_IN" \
   '.AuthenticationResult + {email: $email, savedAt: $ts, RefreshToken: $rt, ExpiresIn: ($exp | tonumber)}' \
   <<< "$RESPONSE" | wildix_save_tokens "$TOKEN_FILE"

echo "Tokens refreshed for $EMAIL"
