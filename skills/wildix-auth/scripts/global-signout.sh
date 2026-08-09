#!/bin/bash
# Signs out from ALL devices by invalidating all tokens via Cognito GlobalSignOut.
# Deletes the local token file afterwards.
# Usage: bash global-signout.sh <email>
set -e
source "$(dirname "$0")/config.sh"

EMAIL="${1:?Usage: $0 <email>}"
ENDPOINT="https://cognito-idp.eu-central-1.amazonaws.com/"

TOKEN_FILE=$(wildix_token_file "$EMAIL")

if [ ! -f "$TOKEN_FILE" ]; then
  echo "No token file for $EMAIL" >&2
  exit 1
fi

ACCESS_TOKEN=$(jq -r '.AccessToken' "$TOKEN_FILE")

PAYLOAD=$(jq -n \
  --arg token "$ACCESS_TOKEN" \
  '{"AccessToken":$token}')

RESPONSE=$(curl -sf "$ENDPOINT" \
  -H "User-Agent: wildix-agent-skills/1.1.0" \
  -H 'content-type: application/x-amz-json-1.1' \
  -H 'x-amz-target: AWSCognitoIdentityProviderService.GlobalSignOut' \
  -d "$PAYLOAD" || true)

if echo "$RESPONSE" | jq -e '.__type' > /dev/null 2>&1; then
  echo "GlobalSignOut error: $(echo "$RESPONSE" | jq -r '.message // .__type')" >&2
  exit 1
fi

rm -f "$TOKEN_FILE"
echo "Global sign-out successful. All sessions invalidated for $EMAIL"
