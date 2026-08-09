---
name: wildix-get-chat
description: Fetch x-bees chat info by raw channel ID, inbox URL, or full channelId. Use when you have a URL like https://app.x-bees.com/inbox/<rawId> or a bare rawId and need channel details (name, type, members) before fetching messages or sending.
license: MIT
metadata:
  author: Wildix
allowed-tools: >-
  Bash, Glob, Skill
---

# Get Chat by ID

Fetches channel info from the Wildix API by raw ID. The API resolves the channel type automatically — no need to know `group:` or `direct:` prefix.

**Do not use `wildix-get-last-chats` for this** — that skill returns the inbox list and cannot look up by ID.

## Peer Skills

Before running, check if `wildix-auth` is installed:
```bash
Glob ~/.claude/skills/wildix-auth/SKILL.md
# If missing: npx skills add gorets/wildix-skills --s wildix-auth -y
```

See [`peers.yaml`](peers.yaml) for full peer manifest.

## Input formats

| Input | Example |
|-------|---------|
| x-bees inbox URL | `https://app.x-bees.com/inbox/abc123` |
| Full channelId | `group:abc123` |
| Bare raw ID | `abc123` |

The script strips URL prefixes and type prefixes automatically.

## Flow

1. **Get IdToken** via `wildix-auth` skill (if not already available)
2. **Run the script**

```bash
ID_TOKEN="$ID_TOKEN" bash <BASE_DIR>/scripts/get-chat-by-id.sh "<input>"
```

## API

`GET https://api.x-bees.com/v2/conversations/channels/{rawId}`

Authorization: `Bearer <IdToken>`

Returns exit code 1 if the channel is not found.
