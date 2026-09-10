# Publishing an ADR to Confluence

Step 7 of the `wildix-adr-from-meeting` skill: page markup and the Atlassian MCP's rough edges.

All ids and addresses come from `~/.claude/adr.config.json` (`confluence.cloudId`,
`confluence.spaceId`, `confluence.indexPageId`, `confluence.folders`). In the examples below they
appear as `<cloudId>`, `<spaceId>`, `<indexPageId>`, `<folders.ADR>`.

A `cloudId` of the form `<your-site>.atlassian.net` works directly — no separate
`getAccessibleAtlassianResources` call is needed. A `spaceId` is accepted as a space key, both a
regular one (`ENG`) and a personal space (`~<account-id>`).

## The header is a Page Properties macro, not a list

The header is published as a Page Properties macro: Confluence indexes its rows as the page's
properties, and the "ADR index" page is assembled from them
(`https://<cloudId>/wiki/spaces/<spaceId>/pages/<indexPageId>`), where the paired Page Properties
Report macro sits with the CQL `ancestor = <folders.ADR> and type = page` and the columns
`Status,Meeting date,Project`. The index updates itself — there is no need to maintain it by hand.
**Participants are not surfaced as an index column** (a dozen names blow the table apart), but the
`Participants` row stays in the record's own header — it is needed there.

⚠️ **The header row labels are fixed English strings** — `Status`, `Meeting date`, `Project`,
`Participants`, `Related records`, `Source` — and they do not follow `adrLanguage`. The Report
macro matches its columns against those exact strings, so a translated label lands the record in
the index with empty columns. If the labels ever change, the macro on the index page has to be
edited in the same pass.

Selection is **by location, not by title**: `ancestor` on a folder works and is transitive — pages
inside the series folders are found by a query on the root `ADR` folder. So a new series is picked
up on its own, and a record with a non-standard name does not fall out. No labels are needed for
this.
⚠️ Do not confuse this with `getConfluencePageDescendants`: that returns 404 for a folder id, while
the `ancestor` predicate works with the same folder.

```html
<div data-type="bodied-extension" data-extension-key="details"
     data-extension-type="com.atlassian.confluence.macro.core" data-layout="wide">
<table data-layout="wide"><tbody>
<tr><th><p>Status</p></th><td><p><span data-type="status" data-color="green">Accepted</span> — caveat</p></td></tr>
<tr><th><p>Meeting date</p></th><td><p><time datetime="YYYY-MM-DD"></time> (clarification)</p></td></tr>
<tr><th><p>Project</p></th><td><p>RNA</p></td></tr>
<tr><th><p>Participants</p></th><td><p>mentions</p></td></tr>
<tr><th><p>Related records</p></th><td><p>links</p></td></tr>
<tr><th><p>Source</p></th><td><p><a href="https://app.x-bees.com/insights/conferences/&lt;conferenceId&gt;">meeting transcription</a> (ASR, distortions marked ⚠️)</p></td></tr>
</tbody></table>
</div>
```

Mandatory details:

- **the first cell of each row is `<th>`** — that is the property name. Without it the row does not
  become a property at all;
- **the second cell must be `<td>`** — that is the property value. A `<th>` there does not merely
  look wrong: **the value never reaches the Page Properties Report**, and the record shows up in the
  index with that column empty. This is the single most consequential detail on the page;
- **never use `<thead>` in this table** — every row goes in `<tbody>`. Confluence promotes the
  second cell of a row inside `<thead>` from `<td>` to `<th>`, which triggers the failure above.

  ⚠️ The promotion happens **on write, every time**, not once at creation. Sending `<td>` inside a
  `<thead>` does not preserve it — the stored page comes back with `<th>`. So when you rewrite the
  body of a page whose header table still has a `<thead>`, **move those rows into `<tbody>` in the
  same pass**; "the second cell is still a `<td>`, leave it alone" is wrong, because your own
  rewrite is what breaks it. Learned the hard way 2026-09-10 while migrating the corpus to English
  labels: nine records were rewritten with the `<thead>` preserved and lost their `Status` value in
  the index;
- `data-layout="wide"` on the `<div data-type="bodied-extension">` itself and on its table
  (see below);
- the `Project` row is needed **always**, even when the local file has no such line (then use the
  series name): otherwise the index column comes out empty;
- the status is a lozenge, `<span data-type="status">`: `green` = Accepted, `yellow` = Proposed,
  `neutral` = Superseded; the caveat text follows the lozenge;
- the date is a `<time datetime="YYYY-MM-DD">` node with an empty body.

**How to check a header actually works:** open the ADR index page and look at the record's row.
An empty `Status`, `Meeting date` or `Project` cell there means that property did not register —
in practice either the label was renamed or the value cell is a `<th>`. The index is the only
end-to-end check available; the page itself gives no hint.

⚠️ On the page the macro looks like an ordinary table — that is how it is supposed to look, not a
sign that it did not apply. The only way to know for sure is through the storage format: create a
draft (`status: "draft"`) with this block and look for `<ac:structured-macro ac:name="details">` in
the response's `body.storage`. Rendering is not available through the API.

⚠️ This MCP has no tool for labels — but the index does not need them, it selects by `ancestor`
(see above). The index page itself also falls into the `ancestor` selection, yet it does not appear
in the report: Page Properties Report only shows pages carrying the `details` macro. If it does
show up as an empty row, add `and id != <indexPageId>` to the CQL.

## Every table goes full width (Go Wide)

ADR tables are dense (next steps, impact on earlier records), and in the default column width the
text turns to noodles. So **every** table on the page is published as

```html
<table data-layout="wide">
```

— including the table inside the Page Properties macro, and the macro itself
(`<div data-type="bodied-extension" ... data-layout="wide">`).

⚠️ **Do not set `data-width`.** In the storage format it turns into `data-table-width="760"` — a
nailed-down width that overrides `wide` and brings the narrow column back. When editing an existing
page, **delete** a `data-width="760"` left over from the old markup rather than carrying it across.

⚠️ **Checking the width by reading the page is useless:** with `contentFormat: "html"` the
`data-layout` attribute is not returned for tables at all (for macros it is). The absence of
`data-layout` in the html you read **does not mean** wide failed to apply. The only way to be sure
is to look at the page, or to ask the user. `data-colwidth`, unlike `data-layout`, **is** returned
on read — that is what shows whether the widths are set on the page or not.

## Column widths

`wide` alone is not enough: without explicit widths the first column stretches and the table looks
loose. The layout the corpus settled on (2026-09-08, set by hand by the owner):

| Table | Widths |
|---|---|
| Page Properties header | `<th data-colwidth="170">` / `<td data-colwidth="807">` (129–172 / 807–848 across records — keep the proportion, not the exact number) |
| Next steps | `#` — `58`, "Task" — `421`, "Owner" — `240`, "Relation" — `240` |

The `#` column numbering the next-steps items straight through is part of the format: it is narrow
and exists so items can be referenced. The other content tables (impact on earlier records, open
questions) need no column widths.

⚠️ A caveat to the `data-width` ban above: it is about **the default 760 with no colwidth**. In the
corpus, content tables are `<table data-width="960">` together with per-column `data-colwidth`
values summing to ≈ 960, and that looks right. **Preserve** such markup when editing.

## Participants are mentions, not text

The `Participants` row on the Confluence page must contain mention nodes, not plain text. That is
why the body is published with `contentFormat: "html"` (a mention node cannot be expressed in
markdown): the rest of the body is ordinary HTML per the `getContentFormatGuide`, and each
participant is

```html
<span data-type="mention" data-user-id="<AAID>">@First Last</span>
```

Roles and clarifications (`(BE)`, `(presenter)`) stay as ordinary text after the mention.
In the local `.md` file participants stay plain text — mentions exist only in Confluence.

**Take AAIDs from the directory** at `participantsFile` from the config (by default
`~/.claude/data/adr-participants.json`). It holds the whole organisation: it was filled from an
Atlassian People directory export ("People directory - Atlassian Teams", the saved page
`/o/<orgId>/people`, 2026-09-08), where names and ids sit in the cards as
`data-testid="user-member-card-link-<AAID>"` and `<span …>First Last's profile</span>` (the name
inside the span wraps across lines — collapse whitespace when parsing). It used to be built from
the mention nodes of already published ADRs; those 18 values matched the exported ones exactly.

The directory is **user-local and is not part of the skill's repository** — it holds real employee
names and their Atlassian account ids. If the file is missing, go straight to step 0 below.

If a participant is not in the directory (a new hire — the export is from 2026-09-08), or there is
no directory at all:

0. **Ask Teamwork Graph — this works and costs one call:**

   ```
   mcp__claude_ai_Atlassian__getTeamworkGraphContext
     cloudId: <cloudId>
     objectType: AtlassianUser
     objectIdentifier: <email | "First Last" | accountId>
     detailLevel: summary
   ```

   The response carries `data.object.accountId` and `userName`. It resolves both a corporate email
   (`firstname.lastname@wildix.com`) and a display name. Verified on three people — matched the
   directory exactly. Limits: one person per call, up to 10 Rovo credits per call; traversing
   relationships (`user_has_top_collaborators`) returns
   `No accessible relationships found for the given parameters and scopes` — the graph cannot be
   unrolled into a list of colleagues.
1. If there are many people, ask the user to save the People directory page again and re-import the
   whole directory (see above): the MCP has no user list and no arbitrary GraphQL/REST passthrough
   either (`fetch` only accepts an ARI for a Jira issue / Confluence page), so an operation like
   `DirectoryViewPeopleQuery` is not available through the MCP.
2. `mcp__claude_ai_Atlassian__lookupJiraAccountId` **does not work** on this instance — it returns
   `403 The app is not installed on this instance`. Do not spend an attempt on it. The MCP's Jira
   tools (`searchJiraIssuesUsingJql` and the rest) return the same 403 — also a dead end.
3. Read any earlier ADR page where this person was a participant with `contentFormat: "html"`
   (`getConfluencePage`) — the mention nodes hold the real AAIDs. Find candidates by the
   `Participants` row in the local corpus: `grep -l "<Name>" <vaultAdrDir>/**/*.md`.
4. If the AAID is still not found, leave the name as plain text and **say so in the report**.
   **Do not invent an AAID** — a wrong id produces a broken mention pointing at someone else or at
   nobody.

Write newly found AAIDs into the directory so the next run already knows them.

## Editing an already published page

The API has **no** partial page update: `updateConfluencePage` replaces the body wholesale. Two
rules follow from that.

1. **Read the page before any edit** (`getConfluencePage`, `contentFormat: "html"`) and build the
   new body on what you read. This applies to a page published five minutes ago in this same
   session too: on 2026-09-08 someone else's version was overwritten this way — the
   `updateConfluencePage` response came back with `version: 4` where 3 was expected, meaning
   somebody had edited the page by hand between the two edits. A version number mismatch in the
   response is the only signal that this happened; earlier versions cannot be read through the MCP,
   and there is nothing to restore the overwritten text from. People edit these pages by hand —
   adding a participant, fixing a phrase — and publishing "from the local file" silently destroys
   those edits. The local `.md` **is not** the source of truth for a page that is already published.
2. Since the whole body is sent, nodes' `data-local-id` values are regenerated and the version in
   the history looks like a full replacement. The guide asks you to preserve them, but copying
   hundreds of opaque hashes by hand is riskier for the text than losing them; it affects neither
   rendering nor inline comments (those have their own `data-annotation-id`). What does need
   carrying across from what you read is `data-colwidth` on tables and any `data-annotation-id`.

When you hit a limit of Confluence-through-MCP that is not written down here, add it to this file —
it is the record.
