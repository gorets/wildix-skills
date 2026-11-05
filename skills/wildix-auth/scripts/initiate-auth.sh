#!/bin/bash
# Initiates Wildix/Cognito CUSTOM_AUTH flow. Outputs the Session token on success.
# Usage: bash initiate-auth.sh <email>
set -e
source "$(dirname "$0")/config.sh"

EMAIL="${1:?Usage: $0 <email>}"
ENDPOINT="https://cognito-idp.eu-central-1.amazonaws.com/"

PAYLOAD=$(jq -n \
  --arg email "$EMAIL" \
  --arg clientId "$WILDIX_CLIENT_ID" \
  '{"AuthFlow":"CUSTOM_AUTH","ClientId":$clientId,"AuthParameters":{"USERNAME":$email},"ClientMetadata":{}}')

RESPONSE=$(curl -sf "$ENDPOINT" \
  -H "User-Agent: wildix-agent-skills/1.1.0" \
  -H 'content-type: application/x-amz-json-1.1' \
  -H 'cache-control: no-store' \
  -H 'x-amz-target: AWSCognitoIdentityProviderService.InitiateAuth' \
  -H 'x-amz-user-agent: aws-amplify/5.0.4 auth framework/1' \
  -d "$PAYLOAD")

if echo "$RESPONSE" | jq -e '.__type' > /dev/null 2>&1; then
  echo "Cognito error: $(echo "$RESPONSE" | jq -r '.message // .__type')" >&2
  exit 1
fi

SESSION=$(echo "$RESPONSE" | jq -r '.Session')
if [ -z "$SESSION" ] || [ "$SESSION" = "null" ]; then
  echo "Unexpected response (no Session): $RESPONSE" >&2
  exit 1
fi

echo "$SESSION"
