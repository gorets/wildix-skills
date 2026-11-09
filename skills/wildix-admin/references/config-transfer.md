# Moving configuration between PBXs

`wx-admin config export | import | copy` carries a chosen part of the configuration to another PBX with nothing bound to the source. (A WMS backup restored on another PBX carries LDAP and values bound to the serial of the first one and breaks the second: do not suggest it.) Source: the README of wx-admin 1.9.0, "Moving configuration to another PBX".

## What is carried, and what never is

Carried: dialplans (with the dialplans they include), general dialplan settings, timetables, IVR menus, switches, paging groups, queues, dialplan database keys (the families the dialplans use; more with `--db-family`), ACL groups, SIP trunks, trunk groups, price lists, and users with `--users` (portable fields only). With `--cloud` also the cloud side of the company: Wilma, the knowledge base, integrations, Kite (see `cloud.md`).

Never: devices, licenses, PSTN and FXO trunks, call history, recordings, voicemails, LDAP ids, jids, passwords, system settings.

References between objects are kept by name and become the ids of the target PBX on import. An object where the serial or host of the old PBX is still found is not carried; it is listed as **bound**. `--map FILE` maps names that differ between the PBXs.

## Workflow for the agent

1. Confirm with the user: the **source** PBX, the **target** PBX, what to carry (`--all`, or `--only KIND:NAME,…`), whether users and the cloud are included. Read the source first (`config backup`, `queue list`, `dialplan list`) so the plan is concrete.
2. **Dry run, always first**, naming both PBXs explicitly:
   ```bash
   wx-admin config copy --from <source> --to <target> --only dialplans:main,queues:Support --dry-run
   ```
   (or `config export --pbx <source> --to <new folder>` then `config import <folder> --pbx <target> --dry-run`). Without a terminal the choice must be given with `--all` or `--only`.
3. **Check that the plan is what was asked.** Kinds are plural (`queues`, `dialplans`, `acl-groups`, `trunks-sip`, `trunk-groups`, `timetables`, `ivr`, `switches`, `paging`, `dialplan-db`, `dialplan-settings`, `price-lists`, `users`; with `--cloud` also `wilma-agents`, `kb-bases`, `integration-webhooks`, `kite-widgets` and others: an unknown kind lists them). On 2026-11-09 a dry run with `--only queues:GSM` came back with a plan of 115 objects across many kinds (ACL groups included) instead of one queue: if the counts and kinds in the plan are not what the user asked for, stop and say so; do not write.
4. Show the plan: **new**, **the same**, **differs**, **blocked** (with the reason: a reference to nothing, no free license, an extension taken). Say what `--overwrite` would replace; overwrite only objects the user named.
5. Wait for the user's yes on exactly this plan. Trunk passwords are asked hidden in a terminal or read from `--secrets FILE` — **the user supplies them**; never invent, read or store one. If trunks are in the plan and no terminal is available, ask the user for a `--secrets` file path.
6. Write: the same command without `--dry-run`, with `--yes` (the user's yes covers it), the target given as `--pbx`/`--to` explicitly. Objects are written in the order they need each other; one that fails does not stop the rest; running the same import again writes only what is left.
7. Report from the end of the output: what was written, what failed, and the **"what is left to do"** list (blocking items first: where in WMS, which `wx-admin` command). Give the path of the log file `wx-admin-import-<host>-<time>.log` (written every time, also with `--dry-run`; `--log DIR` chooses where). The log is company data: do not paste it into other places.

## Rules

- The target is a PBX the user named for writing. A PBX that is only a source is read only.
- `config export` writes a new folder and never overwrites; the folder has no passwords and no serial, but is still company configuration.
- A Company API Key login needs the `pbx:*` scope for `config import`; if it is refused (exit 2), tell the user which login the target needs.
- Do not run `config copy` or `import` with `--cloud` unless the user asked for the cloud side as well: it changes Wilma, the knowledge base, integrations and Kite of the target's company.

## Backup and diff (read only)

```bash
wx-admin config backup --pbx <host> --to ./backup-<host>          # one JSON file per object, passwords masked
wx-admin config diff ./backup-<host> --pbx <host>                  # + only on the PBX, - only in the folder, ~ changed
wx-admin config diff --with <other> --pbx <host>                   # two PBXs against each other
wx-admin --all-pbx config diff ./baseline                          # every signed-in PBX against one folder
```

`--only KIND,KIND…` narrows backup and diff (kinds: dialplans, dialplan-settings, timetables, ivr, switches, paging, queues, trunks-sip, trunks-pstn, trunks-fxo, trunk-groups, acl-groups). **Backup writes one file per object named after it, so two dialplans whose names differ only in case (`users` and `Users`) collide on a case-insensitive disk (macOS) and the backup stops with EEXIST** (seen 2026-11-09); use `--only` to leave that kind out, or back up on a case-sensitive disk. A folder kept in git is the usual baseline.
