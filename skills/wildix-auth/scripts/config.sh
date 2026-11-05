#!/bin/bash
# Wildix prod configuration — source this file in other scripts.

WILDIX_CLIENT_ID="2un9vsk5ghu0ocurajqe4a6l1e"
WILDIX_API_URL="https://api.x-bees.com"

wildix_expand_path() {
  echo "${1/#\~/$HOME}"
}

# Shared config directory, same as the official Wildix CLI:
# $WILDIX_CONFIG_DIR, falling back to ~/.wildix
wildix_config_dir() {
  echo "${WILDIX_CONFIG_DIR:-$HOME/.wildix}"
}

wildix_tokens_dir() {
  echo "$(wildix_config_dir)/tokens"
}

# Creates the tokens directory with owner-only permissions.
wildix_ensure_tokens_dir() {
  local dir
  dir=$(wildix_tokens_dir)
  mkdir -p "$dir"
  chmod 700 "$(wildix_config_dir)" 2>/dev/null || true
  chmod 700 "$dir" 2>/dev/null || true
}

# File name format is unchanged: <sanitized_email>.prod.json (@ -> _at_).
# A second argument is accepted and ignored for backwards compatibility.
wildix_token_file() {
  local email="$1"
  local sanitized
  # The e-mail becomes part of a file name: letters, digits and . _ % + - @ only, no "..".
  if ! [[ "$email" =~ ^[A-Za-z0-9._%+@-]+$ ]] || [[ "$email" == *..* ]]; then
    echo "Not a valid e-mail: $email" >&2
    return 1
  fi
  sanitized=$(echo "$email" | sed 's/@/_at_/g')
  echo "$(wildix_tokens_dir)/${sanitized}.prod.json"
}

# wildix_cognito TARGET PAYLOAD: one call to the Cognito identity provider. The payload (it can hold a refresh
# token) goes in on stdin, never in argv. Prints the body of a 2xx answer and returns 0; on any other answer
# prints the reason to stderr and returns 1.
wildix_cognito() {
  local target="$1" payload="$2" out code
  out=$(mktemp)
  code=$(curl -sS --connect-timeout 10 --max-time 30 --proto '=https' -o "$out" -w '%{http_code}' \
    "https://cognito-idp.eu-central-1.amazonaws.com/" \
    -H "User-Agent: wildix-agent-skills" \
    -H 'content-type: application/x-amz-json-1.1' \
    -H 'cache-control: no-store' \
    -H "x-amz-target: AWSCognitoIdentityProviderService.$target" \
    -H 'x-amz-user-agent: aws-amplify/5.0.4 auth framework/1' \
    --data-binary @- <<<"$payload") || { rm -f "$out"; echo "Cognito request failed ($target)" >&2; return 1; }
  if [[ "$code" != 2* ]] || jq -e '.__type' "$out" >/dev/null 2>&1; then
    echo "Cognito error ($target, HTTP $code): $(jq -r '.message // .__type // empty' "$out" 2>/dev/null)" >&2
    rm -f "$out"
    return 1
  fi
  cat "$out"; rm -f "$out"
}

# wildix_save_tokens FILE: reads the token JSON on stdin and saves it privately (0600) and atomically. A set
# without an IdToken, a RefreshToken and ExpiresIn is refused and the existing file stays as it was.
wildix_save_tokens() {
  local file="$1" tmp
  tmp=$(umask 077; mktemp "$file.XXXXXX") || return 1
  cat > "$tmp"
  if ! jq -e '(.IdToken | type == "string") and (.RefreshToken | type == "string") and (.ExpiresIn | type == "number")' "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    echo "The answer carried no complete set of tokens: nothing was saved." >&2
    return 1
  fi
  chmod 600 "$tmp"
  mv -f "$tmp" "$file"
}
