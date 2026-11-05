#!/bin/bash
# Completes Wildix/Cognito CUSTOM_CHALLENGE. Saves tokens per-email.
# Usage: bash respond-auth.sh <email> <session> <code>
set -e
source "$(dirname "$0")/config.sh"

EMAIL="${1:?Usage: $0 <email> <session> <code>}"
SESSION="${2:?Session required}"
CODE="${3:?Code required}"

wildix_ensure_tokens_dir
TOKEN_FILE=$(wildix_token_file "$EMAIL")

PAYLOAD=$(jq -n \
  --arg email "$EMAIL" \
  --arg session "$SESSION" \
  --arg code "$CODE" \
  --arg clientId "$WILDIX_CLIENT_ID" \
  '{"ChallengeName":"CUSTOM_CHALLENGE","ChallengeResponses":{"USERNAME":$email,"ANSWER":$code},"ClientId":$clientId,"Session":$session}')

RESPONSE=$(wildix_cognito RespondToAuthChallenge "$PAYLOAD")

# A wrong code is not an HTTP error: Cognito answers 200 with a new challenge and no tokens.
if ! jq -e '.AuthenticationResult.IdToken' <<<"$RESPONSE" >/dev/null 2>&1; then
  echo "The code was not accepted (Cognito asked for another challenge). Start again with initiate-auth.sh." >&2
  exit 1
fi

jq --arg email "$EMAIL" \
   --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.AuthenticationResult + {email: $email, savedAt: $ts}' \
   <<< "$RESPONSE" | wildix_save_tokens "$TOKEN_FILE"

echo "OK: $TOKEN_FILE"
