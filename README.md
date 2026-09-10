# Wildix Agent Skills

AI agent skills for [Wildix](https://wildix.com) [x-bees](https://x-bees.com): authenticate, read chats, browse channels, fetch conference details, send messages, and turn a meeting transcription into a published Architecture Decision Record — all from Claude Code.

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
npx skills add gorets/wildix-skills --s wildix-adr-from-meeting -y
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

---

### `wildix-adr-from-meeting`

Downloads a meeting transcription from `wda.wildix.com`, turns it into an Architecture Decision
Record, and publishes it to Confluence as a Page Properties page that a Page Properties Report
indexes automatically. Keeps a local copy in an Obsidian vault when you have one.

**Triggers:** "write an ADR from this call", "record the architecture decisions from that meeting",
passing an `app.x-bees.com/insights/conferences/<id>` link

**Depends on:** `wildix-auth`

**Extra setup.** This skill needs a config file of its own — space, folder ids, your account:

```bash
cp ~/.claude/skills/wildix-adr-from-meeting/config.example.json ~/.claude/adr.config.json
```

It also needs an Atlassian MCP server connected in Claude Code for the Confluence half; without it
the record is still built locally and the skill tells you what is missing. `vaultAdrDir` and
`participantsFile` in the config are optional — with no Obsidian vault the skill works straight
against Confluence.

**Optional short command.** The skill is invocable as `/wildix-adr-from-meeting`. For a shorter
`/adr` with an argument hint, copy the wrapper — `npx skills` installs skills only, not commands:

```bash
cp commands/adr.md ~/.claude/commands/adr.md
```

## Requirements

- `jq` — `brew install jq` (macOS) or `apt install jq` (Linux)
- `python3` — included on macOS/Linux
- `curl` — included on macOS/Linux
- an Atlassian MCP server in Claude Code — only for `wildix-adr-from-meeting`, to publish to Confluence

## License

MIT
