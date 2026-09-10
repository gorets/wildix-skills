---
name: wildix
description: Router for Wildix x-bees skills. Use when the user wants to work with x-bees chats, channels, conferences, or messaging — reads, sends, lists, summarizes, or fetches conference details.
license: MIT
metadata:
  author: Vladimir Gorobets
allowed-tools: >-
  Bash, Glob, Skill
---

# Wildix — skill router

Routes user requests to the appropriate Wildix sub-skill and auto-installs missing ones.

> **Peer manifest:** [`peers.yaml`](peers.yaml) is the single source of truth for sub-skill names, Glob paths, install commands, and install policies. Read it before routing.

## How to pick a sub-skill

Read [`peers.yaml`](peers.yaml), then route based on the user's request:

| User intent | Sub-skill |
|-------------|-----------|
| "log in", "authenticate", token missing/expired | `wildix-auth` |
| "show today's chats", "summarize messages", "what was discussed" | `wildix-chats-overview` |
| "conference details", "meeting summary", conferenceId or x-bees URL | `wildix-get-conference` |
| "list chats", "show inbox" | `wildix-get-last-chats` |
| inbox URL or bare raw channel ID to resolve | `wildix-get-chat` |
| "read messages in chat", "chat history", "what was said in" | `wildix-get-messages-in-chat` |
| "unread messages", "what did I miss", "unread chats" | `wildix-get-unread-messages` |
| "send message", "notify channel", "post to chat" | `wildix-send-message` |

## Peer skill procedure

1. **Glob** the target skill's path from `peers.yaml` to check if it's installed
2. If missing — run the `install` command from `peers.yaml` (all are `silent` — no confirmation needed)
3. Invoke with the `Skill` tool

```bash
# Example: check if wildix-chats-overview is installed
Glob ~/.claude/skills/wildix-chats-overview/SKILL.md
# If missing:
# npx skills add gorets/wildix-skills --s wildix-chats-overview -y
```

> Do not call `Skill` before the Glob — it will fail with "Unknown skill" if not installed.

## wildix-auth is always first

Every sub-skill requires authentication. Before routing to any skill other than `wildix-auth` itself, ensure `wildix-auth` is installed:

```bash
Glob ~/.claude/skills/wildix-auth/SKILL.md
# If missing: npx skills add gorets/wildix-skills --s wildix-auth -y
```

Then invoke `wildix-auth` to get a valid `ID_TOKEN` before the target sub-skill runs.
