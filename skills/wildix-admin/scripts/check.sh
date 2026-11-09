#!/usr/bin/env bash
# Checks that wx-admin (npm: wldx-admin-cli) is installed, new enough, and signed in to a PBX.
#   check.sh            prints the version and `wx-admin status`
# Exit codes: 0 ready; 2 not installed, too old, or not signed in to any PBX (the hint says what the user runs).
# It installs nothing and handles no credentials: signing in is done by the user in their own terminal.
set -euo pipefail

MIN_VERSION="1.9.0"

if ! command -v wx-admin >/dev/null 2>&1; then
  echo "wx-admin is not installed. Ask the user to install it (Node.js 22+ is needed): npm i -g wldx-admin-cli" >&2
  exit 2
fi

version="$(wx-admin --version 2>/dev/null | head -n 1 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"
if [ -z "$version" ]; then
  echo "Could not read the version of wx-admin (wx-admin --version)." >&2
  exit 1
fi

# the lowest of the two versions, by numeric parts
lowest="$(printf '%s\n%s\n' "$MIN_VERSION" "$version" | sort -t. -k1,1n -k2,2n -k3,3n | head -n 1)"
if [ "$lowest" != "$MIN_VERSION" ]; then
  echo "wx-admin $version is older than $MIN_VERSION. Ask the user to update it: npm i -g wldx-admin-cli" >&2
  exit 2
fi

echo "wx-admin $version"
status="$(wx-admin status 2>&1)" || true
echo "$status"
if ! printf '%s\n' "$status" | grep -q 'serial'; then
  echo "Not signed in to any PBX. Ask the user to run in their own terminal: wx-admin login <pbx>" >&2
  exit 2
fi
