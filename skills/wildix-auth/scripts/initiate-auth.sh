#!/bin/bash
# Initiates Wildix/Cognito CUSTOM_AUTH flow. Outputs the Session token on success.
# Usage: bash initiate-auth.sh <email>
set -e
source "$(dirname "$0")/config.sh"

EMAIL="${1:?Usage: $0 <email>}"

PAYLOAD=$(jq -n \
  --arg email "$EMAIL" \
  --arg clientId "$WILDIX_CLIENT_ID" \
  '{"AuthFlow":"CUSTOM_AUTH","ClientId":$clientId,"AuthParameters":{"USERNAME":$email},"ClientMetadata":{}}')

RESPONSE=$(wildix_cognito InitiateAuth "$PAYLOAD")

SESSION=$(echo "$RESPONSE" | jq -r '.Session')
if [ -z "$SESSION" ] || [ "$SESSION" = "null" ]; then
  echo "Unexpected response (no Session): $RESPONSE" >&2
  exit 1
fi

echo "$SESSION"
