#!/usr/bin/env bash
# Runs the consumer read matrix for a scenario directory.
#   read-matrix.sh <scenario-dir>
# Uses <scenario-dir>/consumers.json when present, else fixture/consumers.json.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FIXTURE="$(dirname "$HERE")"
SCENARIO="$(cd "${1:?usage: $0 <scenario-dir>}" && pwd)"
CONSUMERS="$SCENARIO/consumers.json"
[ -f "$CONSUMERS" ] || CONSUMERS="$FIXTURE/consumers.json"

mvn -q -f "$FIXTURE/read-matrix/pom.xml" compile exec:java -Dexec.args="\
$FIXTURE/schemas/order-created-v1.avsc \
$SCENARIO/order-created-v2.avsc \
$FIXTURE/samples/order-created-v1.jsonl \
$SCENARIO/order-created-v2.jsonl \
$CONSUMERS"
