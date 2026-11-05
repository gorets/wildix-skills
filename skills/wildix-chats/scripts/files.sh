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
    stream_call GET "/channels/$(norm_channel "$1")/files/$2" ;;
  download-url)
    [[ $# -eq 3 ]] || usage
    stream_call GET "/channels/$(norm_channel "$1")/messages/$(norm_message "$2")/files/$3/download-url" ;;
  download)
    [[ $# -eq 4 ]] || usage
    url=$(stream_call GET "/channels/$(norm_channel "$1")/messages/$(norm_message "$2")/files/$3/download-url?download=1" | jq -r '.presignedDownloadUrl // empty')
    [[ -n "$url" ]] || die "no download link in the answer"
    code=$(curl -sS -L -o "$4" -w '%{http_code}' "$url") || die "download failed"
    [[ "$code" == 2* ]] || { rm -f "$4"; die "storage answered HTTP $code"; }
    jq -nc --arg f "$4" --arg s "$(wc -c < "$4" | tr -d ' ')" '{ok:true, file:$f, bytes:($s|tonumber)}' ;;
  *) usage ;;
esac
