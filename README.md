# Wildix Agent Skills

AI agent skills for [Wildix](https://wildix.com) [x-bees](https://x-bees.com): authenticate, read chats, browse channels, fetch conference details, send messages, and turn a meeting transcription into a published Architecture Decision Record — all from Claude Code.

> **Unofficial project.** These skills are a personal project, not an official Wildix product. They
> are not released, endorsed or supported by Wildix, and Wildix gives no warranty for them. They
> were built against publicly documented endpoints and the observable behaviour of the x-bees apps
> — the APIs they call are internal product APIs, not a public contract, and can change or
> disappear without notice. "Wildix" and "x-bees" are trademarks of Wildix, used here only to say
> which service these skills talk to.

## Installation

```bash
npx skills add gorets/wildix-skills
```

Or install individual skills:

```bash
npx skills add gorets/wildix-skills --s wildix-auth -y
npx skills add gorets/wildix-skills --s wildix-chats-overview -y
npx skills add gorets/wildix-skills --s wildix-get-conference -y
npx skills add gorets/wildix-skills --s wildix-react-message -y
npx skills add gorets/wildix-skills --s wildix-chats -y
npx skills add gorets/wildix-skills --s wildix-calls-history -y
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

### `wildix-react-message`

Adds, removes or lists a reaction (`eyes`, `thumbsup`, `white_check_mark`, …) on an x-bees message as the authenticated user, so the reaction shows under their own name.

**Triggers:** "put eyes on that message", "react with a check mark", "mark the message as taken", "remove my reaction", "who reacted to this message"

**Depends on:** `wildix-auth`

---

### `wildix-chats`

Chats on the new Wildix Stream service (`stream.wildix.com`), the replacement of the x-bees conversations API, **as the logged-in user**, never as a bot: channels, messages (send, edit, delete, pin, reactions), members, inbox and unread, search over messages, channels and users (the user search is fuzzy: names in any script, typos, names as they sound, exact by e-mail or phone), files, mentions, users. One script per section, and the OpenAPI of each section as its reference, read piece by piece with `openapi.sh`.

**Triggers:** "show my chats", "read the messages in this chat", "react with a check mark", "search the chats for X", "what did I miss", "who is in this channel"

**Depends on:** `wildix-auth`

The service is still being built: a call to an operation that is not ready answers `Operation … is not implemented`. The skill lists what was missing when it was written.

---

### `wildix-calls-history`

What is on record about calls and meetings (conferences) that are over, as the logged-in user: the record and its participants, the transcript, the AI summary and insights, the recording link, the user's call history and missed calls, and a search over calls, conferences and chats by date, person, tag or language. It reads the past: it does not start, join or control a live call. One script per section (conferences, calls, conversations), and the OpenAPI of each section as its reference.

**Triggers:** "what was discussed in yesterday's meeting", "get the transcript of that call", "summarize the conference", "my missed calls", "find the meeting with Anna on Monday"

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

## Migrating from 1.x

Version 2.0.0 removed six skills that went through the old x-bees conversations API; `wildix-chats` does the same on the new Stream service, as the logged-in user:

| Removed | Now |
|---|---|
| `wildix-get-last-chats` | `channels.sh list`, `inbox.sh get` |
| `wildix-get-chat` | `channels.sh get <channel or inbox link>` |
| `wildix-get-messages-in-chat` | `messages.sh list <channel>` |
| `wildix-get-unread-messages` | `inbox.sh get`, `messages.sh list <channel> --unread` |
| `wildix-send-message` | `messages.sh send` (`--markdown`, `--reply-to`, `--file`) |
| `wildix-update-message` | `messages.sh edit`, `messages.sh delete` |

Posting as a bot (a `BOT_TOKEN`) is no longer covered by these skills. `wildix-react-message` and `wildix-chats-overview` stay for now: the new service does not tell who reacted, and there is no overview by date yet.

## Authentication

Log in once with `wildix-auth`. After that every script of the other skills gets its token itself, through `wildix-auth`: the agent never sees, passes or prints a token. With several accounts logged in, set `WILDIX_EMAIL=<email>` to choose one. A script that finds no session stops with exit code 2 and tells you to log in.

The scripts look for `wildix-auth` next to their own skill, so it does not matter whether the skills were installed into `~/.agents/skills` or `~/.claude/skills` (often a symlink to the former) or elsewhere; `WILDIX_SKILLS_DIR` names the folder when the skills are apart. Whether a skill is installed is judged by the agent seeing it, not by a file path.

## Maintaining

The references of `wildix-chats` are generated from the OpenAPI of the service, one file per section:

```bash
node tools/split-stream-openapi.mjs <path to>/stream-client.openapi.json skills/wildix-chats/references
```

The references of `wildix-calls-history` are built the same way from the OpenAPI of the two services behind it, WDA History and WDA Insights:

```bash
node tools/split-wda-openapi.mjs <path to>/wda-history-client.openapi.json <path to>/wda-insights-client.openapi.json
```

Both sources are produced by the SDK generator (`yarn install`, then `node scripts/build-clients -s wda-history-client`, and the same for `wda-insights-client`, in `sdk-ts`): they land in `packages/<client>/etc/<client>.openapi.json`. Note that the generator also rewrites the tracked client sources of those packages.

Operations the service does not implement yet are listed in `tools/stream-not-implemented.json`; the generator marks them (`x-not-implemented`) and `openapi.sh ops` shows `[NOT IMPLEMENTED YET]`. When the service gets one ready, remove it from that file, regenerate, and update the tables in `skills/wildix-chats/SKILL.md` (Sections and Known gaps).

## Requirements

- `jq` — `brew install jq` (macOS) or `apt install jq` (Linux)
- `python3` — included on macOS/Linux
- `curl` — included on macOS/Linux
- an Atlassian MCP server in Claude Code — only for `wildix-adr-from-meeting`, to publish to Confluence

## License

MIT — see [LICENSE](LICENSE).
