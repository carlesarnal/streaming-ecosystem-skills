#!/usr/bin/env bash
# Runs one UC1 trial with Claude Code in headless mode.
#
#   run-trial.sh <trial-id> <scenario> <arm> [model]
#     arm: baseline | skill | checklist
#
# Builds an isolated workspace under $TRIALS_DIR/<trial-id> containing only the
# fixture and the one scenario (never the answer key, rubric or results). Gives
# the trial its own Registry group so concurrent trials cannot interfere, seeds
# it, then runs `claude -p`. Output: workspace/proposal.md, run.json (Claude
# result incl. session id, turns, cost, usage) and meta.json.
#
# Requires the fixture Registry to be running (fixture/docker-compose.yaml).
set -euo pipefail

ID="$1"; SCENARIO="$2"; ARM="$3"; MODEL="${4:-sonnet}"
HERE="$(cd "$(dirname "$0")" && pwd)"
EXP="$(dirname "$HERE")"
REPO="$(cd "$EXP/../.." && pwd)"
TRIALS_DIR="${TRIALS_DIR:-/tmp/uc1-trials}"
WS="$TRIALS_DIR/$ID/workspace"
OUT="$TRIALS_DIR/$ID"

rm -rf "$OUT"; mkdir -p "$WS/scenarios"
cp -R "$EXP/fixture" "$WS/fixture"
rm -rf "$WS/fixture/read-matrix/target"
cp -R "$EXP/scenarios/$SCENARIO" "$WS/scenarios/$SCENARIO"

# Per-trial Registry group for isolation.
GROUP="orders-$ID"
for f in "$WS/fixture/consumers.json" "$WS/scenarios/$SCENARIO/consumers.json"; do
  [ -f "$f" ] || continue
  jq --arg g "$GROUP" '.registry.groupId = $g' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
"$WS/fixture/scripts/registry-check.sh" seed > /dev/null
( cd "$WS" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm init )

PROMPT="Read scenarios/$SCENARIO/task.md and complete the task. Write your final change proposal to proposal.md in the current directory."

case "$ARM" in
  baseline) ;;
  skill)
    mkdir -p "$WS/.claude/skills/evolve-event-schema"
    cp "$REPO/.claude/skills/evolve-event-schema/SKILL.md" "$WS/.claude/skills/evolve-event-schema/"
    ;;
  checklist)
    # Same guidance as the skill, pasted as plain text (frontmatter removed).
    BODY=$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2' "$REPO/.claude/skills/evolve-event-schema/SKILL.md")
    PROMPT="$PROMPT

Follow this checklist:

$BODY"
    ;;
  *) echo "unknown arm: $ARM" >&2; exit 2 ;;
esac

jq -n --arg id "$ID" --arg s "$SCENARIO" --arg a "$ARM" --arg m "$MODEL" --arg g "$GROUP" \
  --arg start "$(date -u +%FT%TZ)" '{id:$id,scenario:$s,arm:$a,model:$m,group:$g,start:$start}' > "$OUT/meta.json"

START=$(date +%s)
( cd "$WS" && claude -p "$PROMPT" \
    --model "$MODEL" \
    --setting-sources project \
    --permission-mode bypassPermissions \
    --output-format json ) > "$OUT/run.json" 2> "$OUT/stderr.log" || true
END=$(date +%s)

jq --argjson secs "$((END-START))" '.wallSeconds = $secs' "$OUT/meta.json" > "$OUT/meta.tmp" && mv "$OUT/meta.tmp" "$OUT/meta.json"
echo "$ID $SCENARIO $ARM done in $((END-START))s; proposal: $([ -f "$WS/proposal.md" ] && echo yes || echo NO)"
