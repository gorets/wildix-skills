# What was checked live

wx-admin 1.9.0 (Node 22+), 2026-11-09. Read only on the shared `crm-test.wildixin.com` (WMS 7.11), signed in as `admin` with Basic. Writes only on the author's own stage PBX `v-gorobets-cloud.wildixin.com` (Basic), listed below.

## Read, worked

`pbx check`, `system info`, `queue list`, `user list --limit 3`, `dialplan list`, `trunk list` (passwords masked), `records history --count 2`, `kb list`, `wilma agent list`, `integration list`, `kite widget list`, `key scopes --group pbx`, `key list` (names and scopes only), all with `--output json`. `config backup --only queues,timetables,ivr` then `config diff` of that folder: "no differences". `config copy --from crm-test --to v-gorobets-cloud --dry-run`: nothing written to the target; it wrote its log file (to `--log DIR`; without it, to the current folder) and listed the "Next steps" (sounds to upload first).

## Written on the stage PBX, worked

`queue create zz-skill-test`, `queue get`, `queue update --timeout 25`, `queue delete` without `--yes` (refused, exit 64: "confirm with --yes"), `queue delete --yes` (the test queue is gone, nothing left behind). `config export --pbx <crm-test> --only queues:GSM --to DIR` carries exactly one queue; `config import DIR --pbx <stage> --all --dry-run --log DIR`: "1 new, 0 blocked", with the next steps (the members 433 and 897 are not users on the stage PBX). Without a terminal `config import` insists on `--all` or `--only`.

## Seen, and what the skill does about it

- `config backup` of the whole PBX stopped with `EEXIST` on `dialplans/Users.json`: two dialplans named `users` and `Users` on a case-insensitive disk. The skill says to leave that kind out with `--only`.
- `config copy --from crm-test --to stage --only queues:GSM --dry-run` returned a plan of 115 objects of many kinds, not the one queue, while `config export --only queues:GSM` followed by `config import --all` gave exactly one. The skill says to compare the plan with what was asked before anything is written; the export-then-import route is the one that was seen to honour `--only`.
- `config copy --dry-run` writes a log file even though nothing was written to the PBX: give `--log DIR` a folder the user chose.

## Not tried

The real `config import` (the write itself): the permission classifier of the author's agent session refused it after the dry-run, so only the plan was seen. Any other write: `user`, `queue` beyond the one test queue, `dialplan`, `trunk`, `system *-set`, `config copy` without `--dry-run`, `key create|delete|rename`, `kb source sync`, `wilma agent update|publish|deploy`, `integration` and `kite` changes, `api` with a method other than GET. `login` (the user's). A Company API Key login (only Basic was used), the WMS sign-in with 2FA, `--all-pbx`, `kb ask`, `records recording-download`, `cloud <service> <operation>`.
