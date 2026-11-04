#!/usr/bin/env bash
# Messages of the Wildix stream service. Usage: messages.sh <command> [args]   (see references/messages.md)
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: messages.sh <command> [args]
  list <channel> [--from SEQ] [--to SEQ] [--unread]       newest first, 30 per page
  get <channel> <message>
  send <channel> <text|-> [--markdown] [--reply-to MESSAGE] [--mention USERID]... [--file PATH]...
  edit <channel> <message> <text|-> [--markdown]          your own messages only
  delete <channel> <message>                              your own messages only
  pin <channel> <message> | unpin <channel> <message>
  react <channel> <message> <type> | unreact <channel> <message> <type>
  reactions <channel> <message>
A channel is an id or an inbox link; a message is an id or an inbox link to it; "-" as text reads stdin.
U
  exit 1; }

# Stops (exit 2) unless the message is the user's own; keeps the message in MSG_JSON.
owner_check() {
  local ch="$1" msg="$2" author me
  MSG_JSON=$(stream_call GET "/channels/$ch/messages/$msg")
  author=$(jq -r '.message.userId // empty' <<<"$MSG_JSON")
  me=$(me_id)
  [[ -n "$author" && "$author" == "$me" ]] || { echo "Error: the message is not yours (author: ${author:-unknown}, you: $me). Nothing was changed." >&2; exit 2; }
}

check_reaction() { [[ "$1" =~ ^[a-z0-9_+-]{1,64}$ ]] || die "reaction type must match [a-z0-9_+-] (up to 64): $1"; }

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift

case "$cmd" in
  list)
    [[ $# -ge 1 ]] || usage
    ch=$(norm_channel "$1"); shift
    from=""; to=""; anchor=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --from) from="$2"; shift 2 ;; --to) to="$2"; shift 2 ;; --unread) anchor="firstUnread"; shift ;; *) usage ;; esac; done
    stream_call GET "/channels/$ch/messages$(qs from "$from" to "$to" anchor "$anchor")" ;;
  get)
    [[ $# -eq 2 ]] || usage
    stream_call GET "/channels/$(norm_channel "$1")/messages/$(norm_message "$2")" ;;
  send)
    [[ $# -ge 2 ]] || usage
    ch=$(norm_channel "$1"); text=$(read_text "$2"); shift 2
    markdown=0; reply=""; mentions=(); files=()
    while [[ $# -gt 0 ]]; do case "$1" in
      --markdown) markdown=1; shift ;; --reply-to) reply="$2"; shift 2 ;;
      --mention) mentions+=("$2"); shift 2 ;; --file) files+=("$2"); shift 2 ;; *) usage ;; esac; done
    body='{}'
    [[ -z "$text" ]] || jset body text "$text"
    [[ $markdown -eq 0 ]] || jsetj body markdown true
    if [[ -n "$reply" ]]; then
      jsetj body quote "$(jq -nc --arg c "$ch" --arg m "$(norm_message "$reply")" '{channelId:$c,messageId:$m}')"; fi
    if [[ ${#mentions[@]} -gt 0 ]]; then jsetj body mentions "$(jarr "${mentions[@]}")"; fi
    if [[ ${#files[@]} -gt 0 ]]; then
      att='[]'
      for f in "${files[@]}"; do a=$(upload_file "$ch" "$f"); att=$(jq -c --argjson a "$a" '.+[$a]' <<<"$att"); done
      jsetj body attachments "$att"
    fi
    [[ "$body" != '{}' ]] || die "nothing to send: give a text or --file"
    stream_call POST "/channels/$ch/messages" "$body" ;;
  edit)
    [[ $# -ge 3 ]] || usage
    ch=$(norm_channel "$1"); msg=$(norm_message "$2"); text=$(read_text "$3"); shift 3
    markdown=0
    while [[ $# -gt 0 ]]; do case "$1" in --markdown) markdown=1; shift ;; *) usage ;; esac; done
    [[ -n "$text" ]] || die "the new text is empty"
    owner_check "$ch" "$msg"
    # PUT (UpdateMessage) replaces the content, so what the message already has (attachments, quote,
    # mentions, elements, markdown) is sent along with the new text. PATCH is not implemented yet.
    body=$(jq -c --arg t "$text" --argjson md "$markdown" '.message | {
        text: $t,
        mentions: (.mentions // []),
        attachments: ((.attachments // []) | map({fsId, name, size, mime, width, height, thumbnail} | with_entries(select(.value != null)))),
        elements: .elements,
        quote: (if .quote then {channelId: .quote.channelId, messageId: .quote.messageId} else null end),
        forward: (if .forward then {channelId: .forward.channelId, messageId: .forward.messageId} else null end),
        markdown: (if $md == 1 then true else .markdown end)
      } | with_entries(select(.value != null and .value != []))' <<<"$MSG_JSON")
    stream_call PUT "/channels/$ch/messages/$msg" "$body" ;;
  delete)
    [[ $# -eq 2 ]] || usage
    ch=$(norm_channel "$1"); msg=$(norm_message "$2")
    owner_check "$ch" "$msg"
    stream_call DELETE "/channels/$ch/messages/$msg" ;;
  pin|unpin)
    [[ $# -eq 2 ]] || usage
    ch=$(norm_channel "$1"); msg=$(norm_message "$2")
    if [[ "$cmd" == pin ]]; then stream_call PUT "/channels/$ch/messages/$msg/pin"; else stream_call DELETE "/channels/$ch/messages/$msg/pin"; fi ;;
  react|unreact)
    [[ $# -eq 3 ]] || usage
    ch=$(norm_channel "$1"); msg=$(norm_message "$2"); check_reaction "$3"
    if [[ "$cmd" == react ]]; then stream_call PUT "/channels/$ch/messages/$msg/reactions/$3"; else stream_call DELETE "/channels/$ch/messages/$msg/reactions/$3"; fi ;;
  reactions)
    [[ $# -eq 2 ]] || usage
    stream_call GET "/channels/$(norm_channel "$1")/messages/$(norm_message "$2")" | jq -c '.message | {messageId, reactionCounts, latestReactions}' ;;
  *) usage ;;
esac
