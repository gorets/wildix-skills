#!/usr/bin/env bash
# Messages where the user was mentioned. Usage: mentions.sh list [--unread] [--cursor C]   (references/mentions.openapi.json)
. "$(dirname "$0")/lib.sh"

usage() { echo "Usage: mentions.sh list [--unread] [--cursor C]" >&2; exit 1; }

[[ "${1:-}" == list ]] || usage; shift
filter=""; cursor=""
while [[ $# -gt 0 ]]; do case "$1" in --unread) filter="unread"; shift ;; --cursor) cursor="$2"; shift 2 ;; *) usage ;; esac; done
stream_call GET "/mentions$(qs filter "$filter" cursor "$cursor")"
