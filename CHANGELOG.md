# Changelog

All notable changes to the Wildix agent skills. The version is the number of the whole pack, shown at the top of the [`README.md`](README.md); the skills standard has no place for it, and `npx skills` notices updates by the content of each skill folder, not by a number. It follows [Semantic Versioning](https://semver.org): a skill removed or renamed is a major version, a skill or a command added is a minor one, a fix is a patch.

## 3.3.0 — 2026-11-07

### Added
- `wildix-live-monitor`: **queue statistics**. `live.sh queues --stats` gives each queue, each of its agents and all the queues together their figures since the local midnight (`--window today`) or over the last 15 to 60 minutes: offered, answered, abandoned (short abandons apart), unanswered, transferred, service level against `--sla` (5 to 30 s), abandon rate, ASA, average talk and ring, longest wait now, agents by state; per agent offered, answered, missed, answer rate, talk, time available, busy, paused and in wrap-up, occupancy. `--active` and `--pbx` narrow the list. `watch --stats` adds `QUEUE_STATS` lines when the figures of a queue change. The figures come from the stats of the WDA live stream, the ones the x-caracal wallboard uses.
- `wildix-calls-history`: **`queues.sh`**, the reports of the call queues over days from the WDA x-caracal service: `summary`, `by-queue`, `by-period` (hour, day, week, month, weekday), `answered` and `unanswered` with their breakdowns (by queue, agent, user, disconnect reason, talk time), `service-level` ladders, `calls` (the queue calls one by one, with pages) and `events` (one queue call step by step), filtered by days, PBX, queues, extensions, outcomes, hours, weekdays, wait and talk bands, disconnect reasons and SLA thresholds; `list` names the queues and the PBXs that have them. Its reference `queues.openapi.json` is built by `tools/split-xcaracal-openapi.mjs`.

### Notes
- Both need a Premium license. The trend series of a live stats window and the x-caracal dashboards are in the service models but not served on production yet: not offered.

## 3.2.2 — 2026-11-07

### Changed
- `wildix-live-monitor`, `wildix-chats` (`watch.sh`) and `wildix-call-control` (`sip.sh`): the Node helpers write to stdout and stderr in blocking mode. On macOS a piped stdout is asynchronous, and the exit right after a write cut the output at 64 KB: `live.sh queues` or `live.sh conversations` read through a pipe (as an agent reads them) gave broken JSON in a large company. Output written to a file or a terminal was not affected.

## 3.2.1 — 2026-11-07

### Added
- `CHANGELOG.md`, restored from the history of the old plugin manifest back to 1.1.0; the version is now shown at the top of the README.
- `AGENTS.md`: the rules of the repository for agents and people who change it (skill and script rules, security, what every change needs); `CLAUDE.md` points Claude Code at it.

### Removed
- `.cursor-plugin/plugin.json`, the manifest of a Cursor plugin: `npx skills` does not read it. The skills install into Cursor through `npx skills` as into any other agent.

## 3.2.0 — 2026-11-07

### Added
- **`wildix-live-monitor`**: what is going on now in the user's company, read only, from the live stream of Wildix Data Analytics (`wss://wda-ws.wildix.com`): call queues and their agents (`live.sh queues`), the calls, customer chats and conferences in progress with their AI insights (`conversations`), presence of colleagues (`presence`), the live transcript of a call or conference (`transcript`, `--follow`), and a feed of all this (`watch`). Queues and conversations need a Premium PBX license. Short views by default; e-mail, IP addresses and locations of people only with `--full`.
- **`wildix-chats`: `watch.sh`**, the live events of the user's chats from the Stream websocket (`wss://eu-1-ws.stream.wildix.com`): messages, reactions, read receipts, members, channel changes, typing; filtered by channel, person, event type, count and time, with the names of people. The user's own messages and reading are left out unless `--mine`.
- Both watchers renew their connection by themselves and take a fresh login token when the old one ends. They need Node.js 22+ and no npm packages.

### Notes
- A reaction event of the Stream service does not name who reacted: `watch.sh` prints the message author as `messageAuthor`.
- Not yet seen live: transcript lines of `live.sh transcript`, `call.update` events within a call, conferences.

## 3.1.0 — 2026-11-06

### Added
- **`wildix-call-control`**: live calls on the user's PBX through the Call Control REST API (`/api/v2/call-control/`): place (click-to-call), answer, hold, unhold, hang up, blind and attended transfer, DTMF, the name shown for a call, the calls going on, the user's devices and which one rings (`calls.sh`, `devices.sh`). `sip.sh` adds a headless SIP watcher of the extension (calls, devices, presence, ringing mode, event by event), recording and the transfer through a conference; it needs Node.js 24+ and installs two pinned npm packages into a cache folder. The PBX comes from the login, which it accepts as it is.
- `tools/extract-pbx-call-control.py` builds its reference from the PBX API document of docs.wildix.com.

## 3.0.0 — 2026-11-06

### Removed
- **`wildix-react-message`**: reactions are in `wildix-chats` (`messages.sh react`, `unreact`, `reactions`).

### Added
- `wildix-chats`: who reacted, through `reactions/query` (`messages.sh reactions [--users]`); `channels.sh create-group --auto-transcribe`; references rebuilt.

## 2.1.0 — 2026-11-05

### Added
- **`wildix-calls-history`** (first named `wildix-conversation-history`): records, participants, transcripts, AI summaries and insights, recording links, the call history and missed calls, and a search over calls, conferences and chats that are over.
- The `save` command: a conference or a chat to an Obsidian note.
- `tools/check-skills.py`: checks frontmatter, names, descriptions, peer manifests, links and scripts.

### Changed
- `wildix-stream` renamed to `wildix-chats` (via `wildix-chat`); the user search in it gets the corporate directory.
- `wildix-get-conference` replaced by `wildix-calls-history` `conferences.sh brief` (several conferences at once).
- Numeric options are checked before the request.

### Security
- Tokens never on a command line; ids and request paths validated; an allow-list of service addresses; safe downloads and outputs; honest revoke and sign-out.
- The chats overview (local days, clear errors, base64url token) and the ADR transcript downloader (no false status gate, UTC, private and non-destructive output) fixed.
- Rules about values taken from fetched content in every skill that reads chat data.

## 2.0.0 — 2026-11-05

### Removed
- The six skills of the old x-bees conversations API: `wildix-get-last-chats`, `wildix-get-chat`, `wildix-get-messages-in-chat`, `wildix-get-unread-messages`, `wildix-send-message`, `wildix-update-message`. The README has a migration table. Posting as a bot is no longer covered.

## 1.7.0 — 2026-11-05

### Added
- **`wildix-stream`** for the new Wildix Stream service: one script per section and the OpenAPI of each section as its reference, read piece by piece with `openapi.sh`; operations the service does not implement yet are marked.

### Changed
- Peer skills are checked by what the agent can see, not by a path; `wildix-auth` is looked for next to the skill, then in `.agents` and `.claude`.

## 1.6.0 — 2026-11-04

### Changed
- Authentication stays inside `wildix-auth`: the scripts load the token themselves and the agent never handles it.

## 1.5.1 — 2026-11-04

### Changed
- Peer skills are never installed silently: the user is asked.
- The untrusted-content rule in every skill that reads chat data.

## 1.5.0 — 2026-11-04

### Added
- `wildix-update-message`: edit and delete the user's own messages; `--markdown` in `wildix-send-message`.

## 1.4.0 — 2026-11-04

### Added
- `wildix-react-message`: add, remove and list the reactions of a message, as the user.

## 1.3.0 — 2026-09-10

### Changed
- Stated as an unofficial project: the author is Vladimir Gorobets in the manifest and every skill, the homepage is the repository, a disclaimer in the README; MIT `LICENSE` added.

## 1.2.0 — 2026-09-10

### Added
- **`wildix-adr-from-meeting`**: an Architecture Decision Record from a meeting transcription, published to Confluence; the `adr` command.

## 1.1.0 — 2026-08-09

First published version: the `wildix` router, `wildix-auth`, `wildix-chats-overview`, `wildix-get-chat`, `wildix-get-conference`, `wildix-get-last-chats`, `wildix-get-messages-in-chat`, `wildix-get-unread-messages`, `wildix-send-message`.
