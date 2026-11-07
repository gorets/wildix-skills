# Wildix Agent Skills

**Version 3.4.0** — what changed in each version: [`CHANGELOG.md`](CHANGELOG.md).

AI agent skills for [Wildix](https://wildix.com) [x-bees](https://x-bees.com): authenticate, work with chats and messages as yourself, find colleagues, read what is on record about calls and meetings that are over (records, transcripts, AI summaries), place and control live phone calls on your PBX and watch them as they happen, see what is going on now in your company (call queues and their agents, calls and customer chats in progress, presence of colleagues, live transcripts), and turn a meeting transcription into a published Architecture Decision Record. They are written for Claude Code and work with other agents that read `SKILL.md` skills.

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
npx skills add gorets/wildix-skills --s wildix-chats -y
npx skills add gorets/wildix-skills --s wildix-calls-history -y
npx skills add gorets/wildix-skills --s wildix-call-control -y
npx skills add gorets/wildix-skills --s wildix-live-monitor -y
npx skills add gorets/wildix-skills --s wildix-adr-from-meeting -y
```

## Skills

### `wildix` *(router)*

Names the skill that does a thing: chats, calls and meetings after the fact, live calls, what is going on now, ADRs. It reads nothing and changes nothing itself; it only points at the right sub-skill, and says what to install when one is missing.

---

### `wildix-auth` *(required by all others)*

Authenticates with Wildix x-bees via AWS Cognito. Tokens are stored locally and refreshed automatically.

**Triggers:** "log in to x-bees", "tokens are missing", "authenticate with Wildix"

---

### `wildix-chats-overview`

Fetches and summarizes x-bees messages for a given period: today, yesterday, a specific date, or a date range.

**Triggers:** "show me today's chats", "summarize x-bees for this week", "what was discussed yesterday"

**Depends on:** `wildix-auth`, `wildix-calls-history`

---

### `wildix-chats`

Chats on the new Wildix Stream service (`stream.wildix.com`), the replacement of the x-bees conversations API, **as the logged-in user**, never as a bot: channels, messages (send, edit, delete, pin, reactions and who reacted), members, inbox and unread, search over messages, channels and users (the user search is fuzzy: names in any script, typos, names as they sound, exact by e-mail or phone), files, mentions, users. One script per section, and the OpenAPI of each section as its reference, read piece by piece with `openapi.sh`.

`watch.sh` follows the chats live through the websocket of the service: one line per new, edited or deleted message, reaction, read receipt, member or channel change, filtered by channel, person or event, until stopped, for a while or for a number of events ("tell me when Anna answers"). It needs Node.js 22+ and no npm packages.

**Triggers:** "show my chats", "read the messages in this chat", "react with a check mark", "who reacted to this message", "search the chats for X", "what did I miss", "who is in this channel", "tell me when Anna writes"

**Depends on:** `wildix-auth`

The service is still being built: a call to an operation that is not ready answers `Operation … is not implemented`. The skill lists what was missing when it was written.

---

### `wildix-calls-history`

What is on record about calls and meetings (conferences) that are over, as the logged-in user: the record and its participants, the transcript, the AI summary and insights, the recording link, the user's call history and missed calls, a search over calls, conferences and chats by date, person, tag or language, statistics of them (counts by department, direction, hour, weekday, duration or AI sentiment, one dimension broken down by another, the data of a chart), and the reports of the call queues over days from x-caracal (offered, answered, abandoned and lost calls, service level, waits, per queue, agent, hour or day, and the queue calls one by one). It reads the past: it does not start, join or control a live call. One script per section (conferences, calls, conversations, queues), and the OpenAPI of each section as its reference.

**Triggers:** "what was discussed in yesterday's meeting", "get the transcript of that call", "summarize the conference", "my missed calls", "find the meeting with Anna on Monday", "how many calls per department last month", "service level of the support queue last week", "which callers did we lose yesterday"

**Depends on:** `wildix-auth`

---

### `wildix-call-control`

Live phone calls on your Wildix PBX, **as the logged-in user**, from your own extension: place a call (click-to-call: the PBX rings your phone or x-bees first, then dials), answer, hold and resume, hang up, blind and attended transfer, DTMF, the name shown for a call, the calls going on now, your registered devices and which one rings (a device, the mobile, all). It uses the PBX's Call Control REST API (`/api/v2/call-control/`, [documented by Wildix](https://docs.wildix.com/api-reference/rest/wms/pbx)). The PBX is taken from your x-bees login, which the PBX accepts as it is: nothing else to configure.

`sip.sh` adds a live view over SIP: one line per call, device, presence and ringing-mode event, to be watched by the agent, plus recording and the transfer through a conference. It needs Node.js 24+, and on its first run installs two pinned npm packages ([`@gorets/wildix-callcontrol`](https://www.npmjs.com/package/@gorets/wildix-callcontrol) and `sip.js`) into `~/.cache/wildix-call-control`.

**Triggers:** "call 201", "hang up", "transfer this call to 305", "press 1", "record this call", "which phones are online", "ring only my desk phone", "tell me when someone calls"

**Depends on:** `wildix-auth`

The PBX needs a recent WMS (7.11 has the API); an older one answers 404 to the REST part.

---

### `wildix-live-monitor`

What is going on **now** in your company, as the logged-in user, read only, from the live stream of Wildix Data Analytics (WDA) that the x-bees supervisor views use: every call queue with the calls in it and its agents (available, paused, in DND and why) and, on request, how each queue and agent did since midnight or in the last hour (service level, answered, abandoned, waits, occupancy), the calls, customer chats and conferences in progress with their live AI insights (sentiment, CSAT, topics), presence of colleagues, the live transcript of a call in progress, and all of it as a feed, one line per change, to be watched by the agent. Queues and the conversations of the company need a Premium PBX license; the conversations a user sees follow their PBX right to view calls of other groups. Short views by default: e-mail, IP addresses and locations of people only on request.

**Triggers:** "what's going on in the support queue", "who is paused in the sales queue", "service level of the support queue today", "which customer chats wait for a reply", "is Anna available", "what is the customer saying on my call", "tell me when a call comes into the queue"

**Depends on:** `wildix-auth`

Needs Node.js 22+ (no npm packages).

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
cp <the folder of the installed wildix-adr-from-meeting skill>/config.example.json ~/.claude/adr.config.json
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

**Optional command to save to Obsidian.** `commands/save.md` saves a conference (summary, decisions, participants, from `wildix-calls-history`) or a chat (summary by days, from `wildix-chats`) as a note in your Obsidian vault:

```bash
cp commands/save.md ~/.claude/commands/save.md
```

Run it as `/save <conference or chat link>`. It writes with whatever Obsidian tool you have (an MCP server, the CLI or plain files); the folders `Meetings/` and `Chats/` are only defaults.

## Migrating from 1.x

Version 2.0.0 removed the skills that went through the old x-bees conversations API and the old conference reader; `wildix-chats` does the same on the new Stream service, as the logged-in user:

| Removed | Now |
|---|---|
| `wildix-get-last-chats` | `channels.sh list`, `inbox.sh get` |
| `wildix-get-chat` | `channels.sh get <channel or inbox link>` |
| `wildix-get-messages-in-chat` | `messages.sh list <channel>` |
| `wildix-get-unread-messages` | `inbox.sh get`, `messages.sh list <channel> --unread` |
| `wildix-send-message` | `messages.sh send` (`--markdown`, `--reply-to`, `--file`) |
| `wildix-update-message` | `messages.sh edit`, `messages.sh delete` |
| `wildix-get-conference` | `wildix-calls-history`: `conferences.sh brief <id>...` (several at once), `conferences.sh transcript` |

Posting as a bot (a `BOT_TOKEN`) is no longer covered by these skills. `wildix-chats-overview` stays for now: there is no overview by date yet. Reactions, including who reacted, are in `wildix-chats` (`messages.sh react`, `unreact`, `reactions`); `wildix-react-message` is removed.

## Authentication

Log in once with `wildix-auth`. After that every script of the other skills gets its token itself, through `wildix-auth`: the agent never sees, passes or prints a token. With several accounts logged in, set `WILDIX_EMAIL=<email>` to choose one. A script that finds no session stops with exit code 2 and tells you to log in.

The scripts look for `wildix-auth` next to their own skill, so it does not matter whether the skills were installed into `~/.agents/skills` or `~/.claude/skills` (often a symlink to the former) or elsewhere; `WILDIX_SKILLS_DIR` names the folder when the skills are apart. Whether a skill is installed is judged by the agent seeing it, not by a file path.

## Maintaining

The rules for changing the skills (and what every change needs: a version, a [`CHANGELOG.md`](CHANGELOG.md) entry, the router and this README) are in [`AGENTS.md`](AGENTS.md).

Before pushing, run the checker: it reads every skill the way a strict consumer would (valid YAML frontmatter, `name` equal to the folder, description length, peers that exist, links that resolve, `bash -n` on the scripts, no hard-coded `~/.claude/skills` path, executable scripts):

```bash
python3 tools/check-skills.py
```

The references of `wildix-chats` are generated from the OpenAPI of the service, one file per section:

```bash
node tools/split-stream-openapi.mjs <path to>/stream-client.openapi.json skills/wildix-chats/references
```

The references of `wildix-calls-history` are built the same way from the OpenAPI of the two services behind it, WDA History and WDA Insights:

```bash
node tools/split-wda-openapi.mjs <path to>/wda-history-client.openapi.json <path to>/wda-insights-client.openapi.json
```

The reference of `wildix-call-control` is cut from the PBX API document that docs.wildix.com publishes (`https://docs.wildix.com/pbx-openapi.yaml`); the script keeps the Call Control operations and points the server at `/api/v2`, where they live:

```bash
python3 tools/extract-pbx-call-control.py <path to>/pbx-openapi.yaml
```

The `queues` reference of `wildix-calls-history` comes from the smithy model of the x-caracal service (`sdk-models/models/wda-xcaracal`, which has no published OpenAPI yet) and the list of queues of the WDA stream document. Build the OpenAPI with the smithy `openapi` plugin (add `software.amazon.smithy:smithy-openapi` to `build.gradle.kts` and a projection `{"plugins": {"openapi": {"service": "wildix.wda.xcaracal#WdaXcaracal", "protocol": "aws.protocols#restJson1", "version": "3.1.0"}}}` to `smithy-build.json`, in a copy of `sdk-models`, then `./gradlew build`), then:

```bash
node tools/split-xcaracal-openapi.mjs <path to>/WdaXcaracal.openapi.json <path to>/wda-stream-client.openapi.json
```

The two WDA sources are produced by the SDK generator (the same documents are also published, a little older, under `sdk-docs/static/codegen/api/`) (`yarn install`, then `node scripts/build-clients -s wda-history-client`, and the same for `wda-insights-client`, in `sdk-ts`): they land in `packages/<client>/etc/<client>.openapi.json`. Note that the generator also rewrites the tracked client sources of those packages.

Operations the service does not implement yet are listed in `tools/stream-not-implemented.json`; the generator marks them (`x-not-implemented`) and `openapi.sh ops` shows `[NOT IMPLEMENTED YET]`. When the service gets one ready, remove it from that file, regenerate, and update the tables in `skills/wildix-chats/SKILL.md` (Sections and Known gaps).

## Requirements

- `jq` — `brew install jq` (macOS) or `apt install jq` (Linux)
- `python3` — included on macOS/Linux
- `curl` — included on macOS/Linux
- Node.js 24+ and npm — only for the live view of `wildix-call-control` (`sip.sh`)
- Node.js 22+ — only for `wildix-live-monitor` and the live events of `wildix-chats` (`watch.sh`)
- an Atlassian MCP server in Claude Code — only for `wildix-adr-from-meeting`, to publish to Confluence

## License

MIT — see [LICENSE](LICENSE).
