#!/usr/bin/env bash
# Files in channels. Usage: files.sh <command> [args]   (references/files.openapi.json)
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: files.sh <command> [args]
  upload <channel> <path>                           uploads the file and prints the attachment object
                                                    (put it into a message, or use: messages.sh send ... --file PATH)
  info <channel> <fsId>
  download-url <channel> <message> <fsId>           a temporary download link
  download <channel> <message> <fsId> <outFile>     saves the file
A channel is an id or an inbox link; a message is an id or an inbox link to it.
U
  exit 1; }

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift

case "$cmd" in
  upload)
    [[ $# -eq 2 ]] || usage
    upload_file "$(norm_channel "$1")" "$2" ;;
  info)
    [[ $# -eq 2 ]] || usage
    check_id "the file id" "$2"
    stream_call GET "/channels/$(norm_channel "$1")/files/$2" ;;
  download-url)
    [[ $# -eq 3 ]] || usage
    check_id "the file id" "$3"
    stream_call GET "/channels/$(norm_channel "$1")/messages/$(norm_message "$2")/files/$3/download-url" ;;
  download)
    [[ $# -eq 4 ]] || usage
    check_id "the file id" "$3"
    out="$4"
    [[ ! -e "$out" ]] || die "$out exists already: choose another path (nothing was overwritten or deleted)"
    [[ -d "$(dirname -- "$out")" ]] || die "the folder of $out does not exist"
    url=$(stream_call GET "/channels/$(norm_channel "$1")/messages/$(norm_message "$2")/files/$3/download-url?download=1" | jq -r '.presignedDownloadUrl // empty')
    [[ -n "$url" ]] || die "no download link in the answer"
    tmp=$(mktemp "$(dirname -- "$out")/.download.XXXXXX") || die "cannot write in the folder of $out"
    code=$(curl -sS -L --connect-timeout 10 --max-time 600 --proto '=https' --proto-redir '=https' -o "$tmp" -w '%{http_code}' "$url") || { rm -f "$tmp"; die "download failed"; }
    [[ "$code" == 2* ]] || { rm -f "$tmp"; die "storage answered HTTP $code"; }
    mv -n "$tmp" "$out" && [[ ! -e "$tmp" ]] || { rm -f "$tmp"; die "$out appeared meanwhile: nothing was overwritten"; }
    jq -nc --arg f "$out" --arg s "$(wc -c < "$out" | tr -d ' ')" '{ok:true, file:$f, bytes:($s|tonumber)}' ;;
  *) usage ;;
esac
