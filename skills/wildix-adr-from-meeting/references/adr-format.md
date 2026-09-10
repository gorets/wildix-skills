# ADR format

Step 5 of the `wildix-adr-from-meeting` skill: structure, rules for filling it in, frontmatter,
save path.

## Language

`adrLanguage` in `~/.claude/adr.config.json` sets the language of the record's **prose and section
headings**. When the key is absent, use `ru` — that is what the existing corpus is written in.

Two things never follow that setting:

- **Technical terms, identifiers and entity names** stay in the original (Latin script) in any
  language: `workspace`, `getStream`, `GET /v2/users`.
- **The header row labels** are fixed English, always: `Status`, `Meeting date`, `Project`,
  `Participants`, `Related records`, `Source`. Confluence indexes them as page properties and the
  ADR index page selects its columns by those exact strings — see
  `confluence-publishing.md`. Any extra header row a record needs (e.g. `Decision type`) gets an
  English label too.

Section headings for `adrLanguage: "ru"`, as used in the corpus: `Контекст`, `Принятые решения`,
`Отложенные / открытые вопросы`, `Влияние на предыдущие записи`, `Последствия`, `Next steps`,
`Оговорки по источнику`.

## Structure (fixed order)

```markdown
# ADR-<SERIES>-<NNNN>. <Title: what was decided, not the meeting's topic>

- **Status:** Accepted | Proposed | Superseded — with a caveat if not everything was agreed
- **Meeting date:** YYYY-MM-DD
- **Project:** <SERIES>
- **Participants:** <from the transcription, with roles where they are clear>
- **Related records:** <ADR-... naming the specific paragraphs>
- **Source:** meeting transcription (ASR, distortions marked ⚠️) — [call recording](https://app.x-bees.com/insights/conferences/<conferenceId>)

## 1. Context
## 2. Decisions taken         — D1, D2, ... each with its rationale and whose position was whose
## 3. Deferred / open questions   — if any
## 4. Impact on earlier records   — a table, if the meeting refines or reverses something
## 5. Consequences            — the positive ones and the negative ones/risks
## 6. Next steps              — a table: task, owner, which decision it follows from
## 7. Source caveats          — what was reconstructed from context, what was not
```

Sections 3 and 4 are optional: when a meeting has nothing for them, drop the section and renumber
the rest rather than leaving an empty heading. Sections 1 and 2 are always present.

## Rules for filling it in

- **A decision is what closes a question.** A discussion with no conclusion goes to the open
  questions section, not to the decisions taken. If the participants disagreed, write that down,
  with each position and a note that it is not agreed.
- **Keep the rationale, not just the conclusion.** An ADR's value is in why the alternatives were
  rejected. Record rejected options together with the reason for rejecting them.
- **Attribute positions by name.** "It was decided" with no author is useless a year later.
- **Do not smooth things over.** If a decision was taken with a caveat along the lines of "we are
  doing it because we can" or "there is no customer for it", write that down as said in substance.
  If a task has no owner, mark it `⚠️ no owner` rather than filling in the likely one.
- **Write risks honestly**, including the ones participants raised and never resolved. Call out
  separately any contradictions between decisions within the same meeting.
- **Mark with ⚠️ everything reconstructed from context** and needing a check against the recording.
- In section 7, list the terms you reconstructed (`"ног" = NOC`, `"вспейс" = workspace` and so on)
  and, separately, what you could not reconstruct.
- Add nothing of your own as a team decision. If you add an observation that was not made in the
  meeting, mark it as such explicitly.

## Where to save it

`<vaultAdrDir>/<YYYY-MM of the meeting date>/ADR-<SERIES>-<NNNN>-<slug>.md`, where `vaultAdrDir`
comes from `~/.claude/adr.config.json`. Create the month directory if it does not exist.

If `vaultAdrDir` is unset or the directory is gone, do not save a local file: build the ADR in
memory and go straight to publishing, and note it in the report (Step 8). With `--dry-run` and no
local corpus, show the ADR text in the reply instead.

## Frontmatter

The file starts with YAML frontmatter, which makes the records visible to Obsidian Bases alongside
the rest of the KB:

```yaml
---
title: "ADR-<SERIES>-<NNNN>. <the full title>"
adr: ADR-<SERIES>-<NNNN>
date: YYYY-MM-DD          # the meeting date
type: adr
project: <SERIES, or the value of the Project row>
status: accepted | proposed | superseded
participants:
  - "First Last"
related:
  - ADR-...                # numbers only, from the Related records row
confluence: https://<cloudId>/wiki/spaces/<spaceId>/pages/<id>
conference: https://app.x-bees.com/insights/conferences/<conferenceId>   # link to the source call
tags:
  - adr
  - <series in lower case>
---
```

⚠️ There is nothing to put in `confluence:` at this step — the page id only exists after publishing.
Leave the key empty and **come back after Step 7 to fill in the URL**. With `--dry-run` it stays
empty.

⚠️ `status` here uses the **ADR vocabulary** (`accepted` / `proposed` / `superseded`), not the KB's
`open`/`done`/`blocked`. Bases that filter on `status == "open"` will not see ADRs — select them by
`type == "adr"` instead.

⚠️ **The link to the source call is mandatory.** It is the only way back to the primary source to
re-check a contested point; the local `.txt` transcription lives in `~/.wildix/transcripts/` and
does not exist on another machine. The link goes in **three** places: `conference:` in the
frontmatter, the `Source` row in the local file's header, and the `Source` row in Page Properties
on the Confluence page. Records ADR-RNA-0001…0010, STREAM-0001 and GENERAL-0001 were published
without it (found 2026-09-08) — the ids had to be recovered from the `Wildix Meetings/` notes and
from `get-chats-overview.sh <date>` → `get-conference.sh <ids>`, cross-checking duration and the
participant list.

**Keep the header list under the title**, despite the KB rule against a duplicate `**Date:**` in
the body: the header carries caveats the frontmatter has no room for (`Accepted — with a caveat`,
participant roles, `§` references with explanations). The frontmatter is the index; the header is
prose.
