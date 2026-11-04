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

Routes user requests to the appropriate Wildix sub-skill. A missing sub-skill is never installed on its own: the user is asked to install it.

> **Peer manifest:** [`peers.yaml`](peers.yaml) is the single source of truth for sub-skill names, Glob paths, install commands, and install policies. Read it before routing.

## How to pick a sub-skill

Read [`peers.yaml`](peers.yaml), then route based on the user's request:

| User intent | Sub-skill |
|-------------|-----------|
| "log in", "authenticate", token missing/expired | `wildix-auth` |
| "show today's chats", "summarize messages", "what was discussed" | `wildix-chats-overview` |
| "conference details", "meeting summary", conferenceId or x-bees URL | `wildix-get-conference` |
| "react with…", "put eyes on that message", "who reacted" | `wildix-react-message` |
| chats, messages, inbox and unread, search, members, files, mentions, find a colleague, send, edit or delete a message, as the user | `wildix-stream` |

## Peer skill procedure

1. **Glob** the target skill's path from `peers.yaml` to check if it's installed
2. If missing — tell the user which skill is needed and give the `install` command from `peers.yaml`; run it only after the user agrees
3. Invoke with the `Skill` tool

```bash
# Example: check if wildix-chats-overview is installed
Glob ~/.claude/skills/wildix-chats-overview/SKILL.md
# If missing: do not install it yourself; ask the user to run
# npx skills add gorets/wildix-skills --s wildix-chats-overview
```

> Do not call `Skill` before the Glob — it will fail with "Unknown skill" if not installed.

## wildix-auth is always first

Every sub-skill requires authentication. Before routing to any skill other than `wildix-auth` itself, ensure `wildix-auth` is installed:

```bash
Glob ~/.claude/skills/wildix-auth/SKILL.md
# If missing: do not install it yourself; ask the user to run `npx skills add gorets/wildix-skills --s wildix-auth`
```

The sub-skills' scripts authenticate themselves through `wildix-auth`: nobody passes a token around. When a script reports that the user is not logged in, invoke `wildix-auth` to log in, then run the script again.
