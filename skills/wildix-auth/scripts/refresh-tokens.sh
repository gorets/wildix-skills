#!/bin/bash
# Refreshes IdToken/AccessToken using the stored RefreshToken.
# Cognito refresh responses don't include a new RefreshToken — existing one is preserved.
# Usage: bash refresh-tokens.sh <email>
set -e
source "$(dirname "$0")/config.sh"

EMAIL="${1:?Usage: $0 <email>}"
ENDPOINT="https://cognito-idp.eu-central-1.amazonaws.com/"

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

RESPONSE=$(curl -sf "$ENDPOINT" \
  -H "User-Agent: wildix-agent-skills/1.1.0" \
  -H 'content-type: application/x-amz-json-1.1' \
  -H 'cache-control: no-store' \
  -H 'x-amz-target: AWSCognitoIdentityProviderService.InitiateAuth' \
  -H 'x-amz-user-agent: aws-amplify/5.0.4 auth framework/1' \
  -d "$PAYLOAD")

if echo "$RESPONSE" | jq -e '.__type' > /dev/null 2>&1; then
  echo "Refresh error: $(echo "$RESPONSE" | jq -r '.message // .__type')" >&2
  exit 1
fi

jq --arg email "$EMAIL" \
   --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   --arg rt "$REFRESH_TOKEN" \
   --arg exp "$EXISTING_EXPIRES_IN" \
   '.AuthenticationResult + {email: $email, savedAt: $ts, RefreshToken: $rt, ExpiresIn: ($exp | tonumber)}' \
   <<< "$RESPONSE" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE" 2>/dev/null || true

echo "Tokens refreshed for $EMAIL"
