#!/usr/bin/env bash
# Deterministic Registry compatibility check for UC1.
#
#   registry-check.sh seed
#       Registers fixture v1 as the current version of the artifact and sets the
#       artifact COMPATIBILITY rule from consumers.json. Idempotent.
#
#   registry-check.sh check <candidate.avsc> [RULE]
#       Dry-runs the candidate as a new version (nothing is stored).
#       RULE (BACKWARD, FORWARD, FULL, BACKWARD_TRANSITIVE, ...) temporarily
#       overrides the artifact rule for this check; the configured rule is
#       restored afterwards. Exit code 0 = compatible, 1 = incompatible.
#
# Env: REGISTRY_URL (default http://localhost:8081/apis/registry/v3)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FIXTURE="$(dirname "$HERE")"
REGISTRY_URL="${REGISTRY_URL:-http://localhost:8081/apis/registry/v3}"
CONSUMERS="$FIXTURE/consumers.json"

GROUP=$(jq -r .registry.groupId "$CONSUMERS")
ARTIFACT=$(jq -r .registry.artifactId "$CONSUMERS")
CONFIGURED_RULE=$(jq -r .registry.compatibilityRule "$CONSUMERS")
BASE="$REGISTRY_URL/groups/$GROUP/artifacts/$ARTIFACT"

set_rule() {
  local rule="$1"
  local body
  body=$(jq -nc --arg c "$rule" '{ruleType:"COMPATIBILITY",config:$c}')
  # PUT updates an existing rule; fall back to POST when it does not exist yet.
  if ! curl -sf -o /dev/null -X PUT -H 'Content-Type: application/json' \
      "$BASE/rules/COMPATIBILITY" -d "$body"; then
    curl -sf -o /dev/null -X POST -H 'Content-Type: application/json' \
      "$BASE/rules" -d "$body"
  fi
}

seed() {
  local v1="$FIXTURE/schemas/order-created-v1.avsc"
  local body
  body=$(jq -nc --arg a "$ARTIFACT" --rawfile s "$v1" \
    '{artifactId:$a, artifactType:"AVRO",
      firstVersion:{version:"1", content:{content:$s, contentType:"application/json"}}}')
  curl -sf -o /dev/null -X POST -H 'Content-Type: application/json' \
    "$REGISTRY_URL/groups/$GROUP/artifacts?ifExists=FIND_OR_CREATE_VERSION" -d "$body"
  set_rule "$CONFIGURED_RULE"
  echo "seeded $GROUP/$ARTIFACT v1 with COMPATIBILITY=$CONFIGURED_RULE"
}

check() {
  local candidate="$1"
  local rule="${2:-$CONFIGURED_RULE}"
  local body out code
  body=$(jq -nc --rawfile s "$candidate" \
    '{content:{content:$s, contentType:"application/json"}}')
  [ "$rule" != "$CONFIGURED_RULE" ] && set_rule "$rule"
  out=$(mktemp)
  code=$(curl -s -o "$out" -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
    "$BASE/versions?dryRun=true" -d "$body")
  [ "$rule" != "$CONFIGURED_RULE" ] && set_rule "$CONFIGURED_RULE"
  if [ "$code" = "200" ]; then
    echo "COMPATIBLE   rule=$rule candidate=$candidate"
    rm -f "$out"
    return 0
  fi
  echo "INCOMPATIBLE rule=$rule candidate=$candidate (HTTP $code)"
  jq -r '.detail // .title // .' "$out" 2>/dev/null || cat "$out"
  jq -r '.causes[]? | "  - \(.description) [\(.context)]"' "$out" 2>/dev/null || true
  rm -f "$out"
  return 1
}

case "${1:-}" in
  seed) seed ;;
  check) shift; [ $# -ge 1 ] || { echo "usage: $0 check <candidate.avsc> [RULE]" >&2; exit 2; }; check "$@" ;;
  *) echo "usage: $0 seed | check <candidate.avsc> [RULE]" >&2; exit 2 ;;
esac
