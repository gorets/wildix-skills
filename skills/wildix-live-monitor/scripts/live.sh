#!/usr/bin/env bash
# What is going on now in the logged-in user's company, from the live stream of Wildix Data Analytics (WDA): call
# queues and their agents, the calls, chats and conferences in progress, presence of colleagues, the live
# transcript of a call. Read only. Needs Node.js 22+ (no npm packages).
# Usage: live.sh <command> [args]
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: live.sh <command> [args]
  queues [--name TEXT] [--busy] [--paused] [--full]
                        the call queues of the company: strategy, calls in them now, agents with their status
                        (Premium license). --busy: only queues with calls; --paused: only those with an agent paused
  conversations [--calls] [--chats] [--conferences] [--mine] [--status S] [--limit N] [--full]
                        the calls, chats and conferences going on in the company now (Premium license), newest
                        first, 50 by default. --mine: only the user's own calls
  presence <extension>...
                        status, message, "until" and phone registration of colleagues of the company
  transcript <callId> [--follow] [--for SECONDS]
  transcript conference:<id> [--follow] [--for SECONDS]
                        the live transcript of a call or conference in progress: what was said so far, then with
                        --follow each new line until it ends. <callId>: the WDA id of the call, or its SIP call id
  watch [--conversations] [--calls] [--mine] [--queues] [--presence EXT]... [--for SECONDS] [--full]
                        one line per event until stopped (or for SECONDS). Without a choice: --conversations
Short views by default: e-mail, IP address, location and user agent of people only with --full.
U
  exit 1; }

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift
args=(); secs=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --full|--busy|--paused|--calls|--chats|--conferences|--follow|--mine|--queues|--conversations) args+=("$1"); shift ;;
    --name) [[ $# -ge 2 ]] || usage; [[ ${#2} -le 100 ]] || die "--name is too long"; args+=(--name "$2"); shift 2 ;;
    --status) [[ $# -ge 2 ]] || usage; [[ "$2" =~ ^[A-Za-z_]{1,40}$ ]] || die "not a status: $2"; args+=(--status "$2"); shift 2 ;;
    --limit) [[ $# -ge 2 ]] || usage; check_int --limit "$2" 1 1000; args+=(--limit "$((10#$2))"); shift 2 ;;
    --presence) [[ $# -ge 2 ]] || usage; [[ "$2" =~ ^[0-9]{1,15}$ ]] || die "not an extension: $2"; args+=(--presence "$2"); shift 2 ;;
    --for) [[ $# -ge 2 ]] || usage; check_int --for "$2" 1 604800; secs=$((10#$2)); shift 2 ;;
    -h|--help) usage ;;
    --*) usage ;;
    *) args+=("$1"); shift ;;
  esac
done
set -- ${args[@]+"${args[@]}"}

case "$cmd" in
  queues|conversations)
    for a in "$@"; do [[ "$a" == --* || "$a" =~ ^[A-Za-z0-9_\ .-]+$ ]] || usage; done
    run_live "$cmd" "$@" ;;
  presence)
    n=0; for a in "$@"; do [[ "$a" == --* ]] && continue; [[ "$a" =~ ^[0-9]{1,15}$ ]] || die "not an extension: $a"; n=$((n + 1)); done
    [[ $n -ge 1 && $n -le 50 ]] || die "name from 1 to 50 extensions"
    run_live presence "$@" ;;
  transcript)
    id=""; for a in "$@"; do [[ "$a" == --* || "$a" =~ ^[0-9]+$ ]] && continue; id="$a"; done
    [[ "$id" =~ ^(conference:)?[A-Za-z0-9._@:+-]{1,200}$ ]] || die "name the call: its WDA id or its SIP call id (or conference:<id>)"
    [[ $secs -eq 0 ]] || set -- "$@" --for "$secs"
    run_live transcript "$@" ;;
  watch)
    deadline=0; [[ $secs -eq 0 ]] || deadline=$(( $(date +%s) + secs ))
    run_live watch "$@" --deadline "$deadline" ;;
  *) usage ;;
esac
