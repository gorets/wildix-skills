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
  sanitized=$(echo "$email" | sed 's/@/_at_/g')
  echo "$(wildix_tokens_dir)/${sanitized}.prod.json"
}
