# What was checked live

wx-admin 1.9.0 (Node 22+), 2026-11-09. Read only on the shared `crm-test.wildixin.com` (WMS 7.11), signed in as `admin` with Basic. Nothing was written on any PBX.

## Read, worked

`pbx check`, `system info`, `queue list`, `user list --limit 3`, `dialplan list`, `trunk list` (passwords masked), `records history --count 2`, `kb list`, `wilma agent list`, `integration list`, `kite widget list`, `key scopes --group pbx`, `key list` (names and scopes only), all with `--output json`. `config backup --only queues,timetables,ivr` then `config diff` of that folder: "no differences". `config copy --from crm-test --to v-gorobets-cloud --dry-run`: nothing written to the target; it wrote its log file (to `--log DIR`; without it, to the current folder) and listed the "Next steps" (sounds to upload first).

## Seen, and what the skill does about it

- `config backup` of the whole PBX stopped with `EEXIST` on `dialplans/Users.json`: two dialplans named `users` and `Users` on a case-insensitive disk. The skill says to leave that kind out with `--only`.
- `config copy … --only queues:GSM --dry-run` returned a plan of 115 objects of many kinds, not the one queue. The skill says to compare the plan with what was asked before anything is written.
- `config copy --dry-run` writes a log file even though nothing was written to the PBX: give `--log DIR` a folder the user chose.

## Not tried

Any write: `user`, `queue`, `dialplan`, `trunk`, `system *-set`, `config import|copy` without `--dry-run`, `key create|delete|rename`, `kb source sync`, `wilma agent update|publish|deploy`, `integration` and `kite` changes, `api` with a method other than GET. `login` (the user's). A Company API Key login (only Basic was used), the WMS sign-in with 2FA, `--all-pbx`, `kb ask`, `records recording-download`, `cloud <service> <operation>`.
