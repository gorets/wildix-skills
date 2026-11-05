#!/usr/bin/env bash
# Search messages, channels and users. Usage: search.sh <command> <query> [options]   (references/search.openapi.json)
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: search.sh <command> <query> [options]
  messages <query> [--channel C] [--sender USERID]... [--attachments] [--links] [--size 1-50] [--cursor C] [--sort relevance|recency|recency_asc]
  channels <query> [--type direct|group] [--member USERID] [--size 1-50] [--cursor C] [--sort relevance|recency|recency_asc]
  users <query> [--mode auto|name|email|phone] [--kind human|bot|all] [--with-extension] [--min-confidence 0..1] [--brief] [--size 1-50] [--cursor C]
Pages: pass the nextCursor of the answer as --cursor.
U
  exit 1; }

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift
[[ $# -ge 1 ]] || usage
query="$1"; shift

case "$cmd" in
  messages)
    channel=""; senders=(); att=""; links=""; size=""; cursor=""; sort=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --channel) channel="$(norm_channel "$2")"; shift 2 ;; --sender) senders+=("$2"); shift 2 ;;
      --attachments) att="true"; shift ;; --links) links="true"; shift ;;
      --size) size="$2"; shift 2 ;; --cursor) cursor="$2"; shift 2 ;; --sort) sort="$2"; shift 2 ;; *) usage ;; esac; done
    [[ -z "$size" ]] || check_int --size "$size" 1 50
    q=$(qs q "$query" channelId "$channel" hasAttachments "$att" hasLinks "$links" size "$size" cursor "$cursor" sort "$sort")
    for s in ${senders[@]+"${senders[@]}"}; do q=$(qadd "$q" senderIds "$s"); done
    stream_call GET "/search/messages$q" ;;
  channels)
    type=""; member=""; size=""; cursor=""; sort=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --type) type="$2"; shift 2 ;; --member) member="$2"; shift 2 ;;
      --size) size="$2"; shift 2 ;; --cursor) cursor="$2"; shift 2 ;; --sort) sort="$2"; shift 2 ;; *) usage ;; esac; done
    [[ -z "$size" ]] || check_int --size "$size" 1 50
    stream_call GET "/search/channels$(qs q "$query" channelType "$type" memberId "$member" size "$size" cursor "$cursor" sort "$sort")" ;;
  users)
    mode=""; kind=""; ext=""; minc=""; brief=0; size=""; cursor=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --mode) mode="$2"; shift 2 ;; --kind) kind="$2"; shift 2 ;; --with-extension) ext="true"; shift ;;
      --min-confidence) minc="$2"; shift 2 ;; --brief) brief=1; shift ;;
      --size) size="$2"; shift 2 ;; --cursor) cursor="$2"; shift 2 ;; *) usage ;; esac; done
    [[ -z "$size" ]] || check_int --size "$size" 1 50
    [[ -z "$minc" ]] || [[ "$minc" =~ ^(0|1|0?\.[0-9]+|1\.0+)$ ]] || die "--min-confidence is a number from 0 to 1: $minc"
    res=$(stream_call GET "/search/users$(qs q "$query" mode "$mode" kind "$kind" withExtensionOnly "$ext" minConfidence "$minc" size "$size" cursor "$cursor")")
    if [[ $brief -eq 1 ]]; then
      jq -c '{margin, nextCursor, results: [.results[] | {id: .user.id, name: .user.displayName, email: .user.email, extension: .user.pbxExtension, bot: .user.bot, confidence, matchedOn}]}' <<<"$res"
    else
      printf '%s\n' "$res"
    fi ;;
  *) usage ;;
esac
