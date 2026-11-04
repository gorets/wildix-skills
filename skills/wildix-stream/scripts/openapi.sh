#!/usr/bin/env bash
# Reads the OpenAPI references of the skill without loading a whole file. No login needed.
# Usage: openapi.sh sections
#        openapi.sh ops <section>                    operations: method, path, operationId (and [NOT IMPLEMENTED YET])
#        openapi.sh op <section> <operationId>       one operation: parameters, body, responses
#        openapi.sh schema <section> <SchemaName>    one schema
#        openapi.sh schemas <section>                names of the schemas of the section
set -euo pipefail
command -v jq >/dev/null || { echo "Error: jq is required (brew install jq)" >&2; exit 1; }
REF="$(cd "$(dirname "${BASH_SOURCE[0]}")/../references" && pwd)"

usage() { sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1; }
file_of() { local f="$REF/$(echo "$1" | tr 'A-Z' 'a-z').openapi.json"; [[ -f "$f" ]] || { echo "Error: no section '$1'. Sections: $(ls "$REF" | sed 's/.openapi.json//' | tr '\n' ' ')" >&2; exit 1; }; echo "$f"; }

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift
case "$cmd" in
  sections)
    for f in "$REF"/*.openapi.json; do
      printf '%-10s %s operations\n' "$(basename "$f" .openapi.json)" "$(jq '[.paths[] | keys[] | select(IN("get","post","put","patch","delete"))] | length' "$f")"
    done ;;
  ops)
    [[ $# -eq 1 ]] || usage
    f=$(file_of "$1") || exit 1
    jq -r '.paths | to_entries[] | .key as $p | .value | to_entries[] | select(.key | IN("get","post","put","patch","delete")) | "\(.key | ascii_upcase)\t\($p)\t\(.value.operationId)\(if .value["x-not-implemented"] then "\t[NOT IMPLEMENTED YET]" else "" end)"' "$f" | sort -t$'\t' -k2,2 -k1,1 ;;
  op)
    [[ $# -eq 2 ]] || usage
    f=$(file_of "$1") || exit 1
    jq --arg id "$2" '[.paths | to_entries[] | .key as $p | .value | to_entries[] | select(.value|type=="object" and .operationId==$id) | {method:(.key|ascii_upcase), path:$p} + .value] | if length==0 then error("no operation " + $id + " in this section; list them with: openapi.sh ops <section>") else .[0] end' "$f" ;;
  schema)
    [[ $# -eq 2 ]] || usage
    f=$(file_of "$1") || exit 1
    if jq -e --arg n "$2" '.components.schemas | has($n)' "$f" >/dev/null; then
      jq --arg n "$2" '.components.schemas[$n]' "$f"
    else
      where=$(for g in "$REF"/*.openapi.json; do jq -e --arg n "$2" '.components.schemas | has($n)' "$g" >/dev/null && basename "$g" .openapi.json || true; done | tr '\n' ' ')
      echo "Error: no schema '$2' in '$1'. ${where:+It is in: $where}" >&2; exit 1
    fi ;;
  schemas)
    [[ $# -eq 1 ]] || usage
    f=$(file_of "$1") || exit 1
    jq -r '.components.schemas | keys[]' "$f" ;;
  *) usage ;;
esac
