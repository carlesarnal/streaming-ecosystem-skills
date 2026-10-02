# UC1 experiment: Evolve an event schema

Tests whether the `evolve-event-schema` skill improves how an AI assistant
handles a schema change for a Kafka event governed by Apicurio Registry, when
producers and consumers release independently. This is RHAF Agentic Skills
Use Case 1.

**Hypothesis:** with the skill, the assistant reaches a correct, evidence-backed
change proposal with fewer critical errors (in particular, accepting a change
because the configured Registry rule passed) and no more human effort than the
same assistant without the skill.

**What would falsify it:** the baseline (same assistant, docs and tools, no
skill) or a plain checklist performs equally well. Record that outcome too.

## Layout

```
fixture/                 Shared environment (identical for every arm)
  docker-compose.yaml    Kafka + Apicurio Registry (Registry on :8081)
  consumers.json         Topic, artifact, rule and declared consumers
  schemas/, samples/     OrderCreated v1 schema and events
  scripts/registry-check.sh   seed | check <candidate.avsc> [RULE] (dry run)
  scripts/read-matrix.sh      writer × consumer × reader decode + contract check
  read-matrix/           Java/Avro harness behind read-matrix.sh
scenarios/               Task briefs given verbatim to both arms
  s1-add-field/          Safe additive change           → expected: accept
  s2-break-contract/     Rename passes BACKWARD rule     → expected: request changes
  s3-missing-context/    Nullable field, unknown consumer → expected: ask
answer-key/              Expected outcomes. NEVER visible to the agent
rubric.md                Scoring, process metrics, decision thresholds
results/results.md       Trial log and summary
```

## Prerequisites

Docker, `jq`, `curl`, JDK 17+, Maven.

```bash
docker compose -f fixture/docker-compose.yaml up -d
fixture/scripts/registry-check.sh seed
fixture/scripts/registry-check.sh check scenarios/s1-add-field/order-created-v2.avsc
fixture/scripts/read-matrix.sh scenarios/s1-add-field
```

## Running a trial

1. **Prepare a clean workspace** for each trial: a copy of this directory
   **without `answer-key/`, `rubric.md` and `results/`**. Reset the Registry
   (`docker compose down && up -d`, then `seed`).
2. **Arm setup.** Both arms use the same model, tools, permissions, fixture
   and token/time budget.
   - `skill`: `.claude/skills/evolve-event-schema/` installed in the workspace.
   - `baseline`: no skill installed (and none from this repo in user config).
   - `checklist` (optional): no skill; the skill's step list pasted as plain
     text in the brief. Separates "structured instructions" from "skill
     mechanism".
3. **Prompt:** "Read `scenarios/<id>/task.md` and complete the task." Answer
   follow-up questions only from a fixed script (below); otherwise reply "I
   don't know".
4. **Record** the transcript, wall-clock time, human turns and token usage.
   Save the final proposal as `results/<date>-<scenario>-<arm>-<run>.md`.
5. **Score** blind against `rubric.md` and `answer-key/`.

Run each scenario × arm at least 3 times. Randomize the order of arms.

### Scripted answers (same for all arms)

| Question about | Answer |
|---|---|
| S3: billing's reader version / contract | "billing is on v1 and reads customerId for invoicing." |
| S3: replay requirement | "Topic retention is 7 days; billing replays on failure." |
| Anything else | "I don't know." |

## Scope and limitations

- One event, Avro only, one version step (v1 → v2), two declared consumers.
- The read matrix simulates consumer deserialization with Avro schema
  resolution. It does not run the Camel route or Apicurio SerDes against Kafka.
  End-to-end client tests are a possible next step, only if the matrix proves
  insufficient.
- Scenarios are constructed, not observed customer cases. Customer validation
  runs in parallel (see the RHAF discovery plan).
- No production systems: Registry dry runs and a local fixture only.
