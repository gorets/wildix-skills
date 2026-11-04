#!/usr/bin/env bash
# Uploads a local file to an x-bees channel and returns the MessageAttachment JSON.
# Usage: upload-file.sh <channelId> <filePath> [--user]
#   token: ID_TOKEN from the environment, else BOT_TOKEN from .env (bot), else the logged-in user
#   through the wildix-auth skill. --user takes the user even when BOT_TOKEN is set in .env.
#   (A token as the third argument still works, but it shows up in the process list.)
# Output: MessageAttachment JSON object (use in send-message.sh --attach)
set -euo pipefail

CHANNEL_ID="${1:?Usage: upload-file.sh <channelId> <filePath>}"
FILE_PATH="${2:?Usage: upload-file.sh <channelId> <filePath>}"
AS_USER=0
TOKEN="${ID_TOKEN:-}"
if [[ "${3:-}" == "--user" ]]; then AS_USER=1; elif [[ -n "${3:-}" ]]; then TOKEN="$3"; fi

API_BASE="https://api.x-bees.com"

# Authentication belongs to the wildix-auth skill: it loads ID_TOKEN without ever printing it.
load_user_token() {
  local _d
  for _d in "$(dirname "$0")/../.." "$HOME/.claude/skills" "$HOME/.agents/skills"; do
    [ -f "$_d/wildix-auth/scripts/load-token.sh" ] && { . "$_d/wildix-auth/scripts/load-token.sh"; break; } || true
  done
  command -v wildix_require_token >/dev/null || { echo "Error: the wildix-auth skill is not installed. Ask the user to run: npx skills add gorets/wildix-skills --s wildix-auth" >&2; exit 2; }
  wildix_require_token || exit 2
  TOKEN="$ID_TOKEN"
}


if [[ ! -f "$FILE_PATH" ]]; then
  echo "Error: file not found: $FILE_PATH" >&2
  exit 1
fi

if [[ -z "$TOKEN" && $AS_USER -eq 1 ]]; then
  load_user_token
fi

if [[ -z "$TOKEN" ]]; then
  ENV_FILE="$(dirname "$0")/../.env"
  [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
  TOKEN="${BOT_TOKEN:-}"
fi

if [[ -z "$TOKEN" ]]; then
  load_user_token   # no bot token either: act as the logged-in user
fi

FILE_NAME=$(basename "$FILE_PATH")
MIME_TYPE=$(file --mime-type -b "$FILE_PATH" 2>/dev/null || echo "application/octet-stream")

# Step 1: get presigned upload URL
echo "Requesting upload URL for '$FILE_NAME'..." >&2
UPLOAD_RESP=$(curl -sf \
  -X POST "${API_BASE}/v2/conversations/channels/${CHANNEL_ID}/files" \
  -H "User-Agent: wildix-agent-skills/1.1.0" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"name\": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$FILE_NAME")}")

FILE_ID=$(echo "$UPLOAD_RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["fileId"])')
PRESIGNED_URL=$(echo "$UPLOAD_RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["presignedUploadUrl"])')

if [[ -z "$FILE_ID" || -z "$PRESIGNED_URL" ]]; then
  echo "Error: unexpected upload response: $UPLOAD_RESP" >&2
  exit 1
fi

# Step 2: upload file binary to S3 presigned URL
echo "Uploading file to S3..." >&2
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PUT "$PRESIGNED_URL" \
  -H "Content-Type: ${MIME_TYPE}" \
  --data-binary "@${FILE_PATH}")

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "Error: S3 upload failed (HTTP $HTTP_CODE)" >&2
  exit 1
fi

# Step 3: fetch file metadata (returns MessageAttachment object)
echo "Fetching file metadata..." >&2
FILE_RESP=$(curl -sf \
  "${API_BASE}/v2/conversations/channels/${CHANNEL_ID}/files/${FILE_ID}" \
  -H "User-Agent: wildix-agent-skills/1.1.0" \
  -H "Authorization: Bearer ${TOKEN}")

# Output the MessageAttachment JSON
echo "$FILE_RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps(d["file"]))'
