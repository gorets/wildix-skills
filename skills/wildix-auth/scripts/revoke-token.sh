#!/bin/bash
# Revokes the current refresh token for <email> and deletes the local token file.
# Usage: bash revoke-token.sh <email>
set -e
source "$(dirname "$0")/config.sh"

EMAIL="${1:?Usage: $0 <email>}"
ENDPOINT="https://cognito-idp.eu-central-1.amazonaws.com/"

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

RESPONSE=$(curl -sf "$ENDPOINT" \
  -H "User-Agent: wildix-agent-skills/1.1.0" \
  -H 'content-type: application/x-amz-json-1.1' \
  -H 'x-amz-target: AWSCognitoIdentityProviderService.RevokeToken' \
  -d "$PAYLOAD" || true)

if echo "$RESPONSE" | jq -e '.__type' > /dev/null 2>&1; then
  echo "Revoke error: $(echo "$RESPONSE" | jq -r '.message // .__type')" >&2
  exit 1
fi

rm -f "$TOKEN_FILE"
echo "Token revoked and local session deleted for $EMAIL"
