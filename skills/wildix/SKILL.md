---
name: wildix
description: Router for Wildix x-bees skills. Use when the user wants to work with x-bees chats, channels, conferences, or messaging — reads, sends, lists, summarizes, or fetches conference details.
license: MIT
metadata:
  author: Vladimir Gorobets
allowed-tools: >-
  Bash, Skill
---

# Wildix — skill router

Routes user requests to the appropriate Wildix sub-skill. A missing sub-skill is never installed on its own: the user is asked to install it.

> **Peer manifest:** [`peers.yaml`](peers.yaml) is the single source of truth for sub-skill names, install commands, and install policies. Read it before routing.

## How to pick a sub-skill

Read [`peers.yaml`](peers.yaml), then route based on the user's request:

| User intent | Sub-skill |
|-------------|-----------|
| "log in", "authenticate", token missing/expired | `wildix-auth` |
| "show today's chats", "summarize messages", "what was discussed" | `wildix-chats-overview` |
| a call or meeting that is over: transcript, AI summary, decisions, recording, call history, missed calls, find a meeting, as the user | `wildix-calls-history` |
| "react with…", "put eyes on that message", "who reacted" | `wildix-react-message` |
| chats, messages, inbox and unread, search, members, files, mentions, find a colleague, send, edit or delete a message, as the user | `wildix-chats` |

## Peer skill procedure

1. Check that the target skill is among the skills you can use. A skill is installed when you can see it; do not look for it on disk, the place depends on the agent and on how it was installed.
2. If missing — tell the user which skill is needed and give the `install` command from `peers.yaml`; run it only after the user agrees
3. Invoke with the `Skill` tool

> Calling `Skill` for a skill that is not installed fails with "Unknown skill".

## wildix-auth is always first

Every sub-skill requires authentication. Before routing to any skill other than `wildix-auth` itself, check that `wildix-auth` is among the skills you can use; if not, ask the user to run `npx skills add gorets/wildix-skills --s wildix-auth`.

The sub-skills' scripts authenticate themselves through `wildix-auth`: nobody passes a token around. When a script reports that the user is not logged in, invoke `wildix-auth` to log in, then run the script again.
