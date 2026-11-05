#!/bin/bash
# Completes Wildix/Cognito CUSTOM_CHALLENGE. Saves tokens per-email.
# Usage: bash respond-auth.sh <email> <session> <code>
set -e
source "$(dirname "$0")/config.sh"

EMAIL="${1:?Usage: $0 <email> <session> <code>}"
SESSION="${2:?Session required}"
CODE="${3:?Code required}"
ENDPOINT="https://cognito-idp.eu-central-1.amazonaws.com/"

wildix_ensure_tokens_dir
TOKEN_FILE=$(wildix_token_file "$EMAIL")

PAYLOAD=$(jq -n \
  --arg email "$EMAIL" \
  --arg session "$SESSION" \
  --arg code "$CODE" \
  --arg clientId "$WILDIX_CLIENT_ID" \
  '{"ChallengeName":"CUSTOM_CHALLENGE","ChallengeResponses":{"USERNAME":$email,"ANSWER":$code},"ClientId":$clientId,"Session":$session}')

RESPONSE=$(curl -sf "$ENDPOINT" \
  -H "User-Agent: wildix-agent-skills/1.1.0" \
  -H 'content-type: application/x-amz-json-1.1' \
  -H 'cache-control: no-store' \
  -H 'x-amz-target: AWSCognitoIdentityProviderService.RespondToAuthChallenge' \
  -H 'x-amz-user-agent: aws-amplify/5.0.4 auth framework/1' \
  -d "$PAYLOAD")

if echo "$RESPONSE" | jq -e '.__type' > /dev/null 2>&1; then
  echo "Cognito error: $(echo "$RESPONSE" | jq -r '.message // .__type')" >&2
  exit 1
fi

jq --arg email "$EMAIL" \
   --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.AuthenticationResult + {email: $email, savedAt: $ts}' \
   <<< "$RESPONSE" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE" 2>/dev/null || true

echo "OK: $TOKEN_FILE"
