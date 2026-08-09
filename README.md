# Wildix Agent Skills

AI agent skills for [Wildix](https://wildix.com) [x-bees](https://x-bees.com): authenticate, read chats, browse channels, fetch conference details, and send messages — all from Claude Code.

## Installation

```bash
npx skills add gorets/wildix-skills
```

Or install individual skills:

```bash
npx skills add gorets/wildix-skills --s wildix-auth -y
npx skills add gorets/wildix-skills --s wildix-chats-overview -y
npx skills add gorets/wildix-skills --s wildix-get-conference -y
npx skills add gorets/wildix-skills --s wildix-get-last-chats -y
npx skills add gorets/wildix-skills --s wildix-get-chat -y
npx skills add gorets/wildix-skills --s wildix-get-messages-in-chat -y
npx skills add gorets/wildix-skills --s wildix-get-unread-messages -y
npx skills add gorets/wildix-skills --s wildix-send-message -y
```

## Skills

### `wildix-auth` *(required by all others)*

Authenticates with Wildix x-bees via AWS Cognito. Tokens are stored locally and refreshed automatically.

**Triggers:** "log in to x-bees", "tokens are missing", "authenticate with Wildix"

---

### `wildix-chats-overview`

Fetches and summarizes x-bees messages for a given period: today, yesterday, a specific date, or a date range.

**Triggers:** "show me today's chats", "summarize x-bees for this week", "what was discussed yesterday"

**Depends on:** `wildix-auth`, `wildix-get-conference`

---

### `wildix-get-conference`

Fetches conference details (participants, duration, transcription, AI insights) from `wda.wildix.com`.

**Triggers:** "get conference details", "show me the meeting summary", passing a conference ID or URL

**Depends on:** `wildix-auth`

---

### `wildix-get-last-chats`

Returns the user's x-bees inbox — list of chats sorted by last activity. For browsing chats by name, not for ID lookup.

**Triggers:** "list my chats", "show inbox", "show all conversations", "find chat by name"

**Depends on:** `wildix-auth`

---

### `wildix-get-chat`

Resolves a raw channel ID or x-bees inbox URL (`https://app.x-bees.com/inbox/<rawId>`) to a full chat object using the Wildix API.

**Triggers:** x-bees inbox URL, bare raw channel ID that needs type resolution

**Depends on:** `wildix-auth`

---

### `wildix-get-messages-in-chat`

Fetches messages from a specific x-bees chat with pagination support.

**Triggers:** "read messages in chat X", "show chat history", "what was said in group Y"

**Depends on:** `wildix-auth`, `wildix-get-last-chats`

---

### `wildix-get-unread-messages`

Fetches unread channels and their recent messages.

**Triggers:** "show unread messages", "what did I miss", "any unread chats"

**Depends on:** `wildix-auth`

---

### `wildix-send-message`

Sends a text message to an x-bees channel as a bot or as the authenticated user.

**Triggers:** "send a message to channel X", "notify channel", "post to chat"

**Depends on:** `wildix-auth`

## Requirements

- `jq` — `brew install jq` (macOS) or `apt install jq` (Linux)
- `python3` — included on macOS/Linux
- `curl` — included on macOS/Linux

## License

MIT
