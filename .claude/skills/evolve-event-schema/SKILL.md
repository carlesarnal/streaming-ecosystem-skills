---
name: evolve-event-schema
description: Decide whether a change to an existing Kafka event schema governed by Apicurio Registry can ship safely when producers and consumers release independently. Use when a developer changes an Avro/JSON Schema/Protobuf event, asks "can we change this event safely?", or needs a release sequence and verification evidence for a schema change.
allowed-tools: Read, Bash, Grep, Glob
---

# Evolve an Event Schema Safely

Produce a reviewable change proposal for a schema change: a decision, a release
sequence, the evidence behind it, and an explicit statement of what was **not**
verified. Compatibility is decided by deterministic tools (Apicurio Registry
rules, client read tests), never by reasoning alone. Your job is to gather the
constraints, choose the right checks, run them and interpret the results.

Do not register new versions, change rules permanently, or produce events on
shared topics. Use dry runs and local fixtures only.

1. **Gather the constraints before checking anything.** Collect and write down:
   - Topic, Registry group/artifact ID, artifact type, and the configured
     compatibility rule (`GET /groups/{g}/artifacts/{a}/rules/COMPATIBILITY`;
     if not set at artifact level, check group and global rules).
   - Current and candidate schema.
   - **Every consumer**: the reader schema version it runs today, the fields it
     actually depends on, and its release cadence and owner.
   - Whether old events must stay readable (retention, replay, reprocessing,
     new consumers reading from the earliest offset).
   - Serde/library and versions, if they could change the result (for example,
     specific vs generic Avro readers, or a configured reader schema).

   If any item is unknown and could change the decision, **stop and ask**. Do
   not fill gaps with assumptions. An unknown consumer contract or an unknown
   replay requirement is a reason to return "ask for missing information", not
   to accept.

2. **Derive the compatibility direction actually needed.** The configured rule
   is a policy, not proof that the release plan is safe. Work it out from the
   release order:
   - Consumers upgrade **before** the producer → new readers must read old data
     → **BACKWARD**.
   - Producer ships **before** some consumers upgrade (independent releases,
     lagging consumers) → old readers must read new data → **FORWARD**.
   - Both orders are possible, or old events must be replayed by new readers
     while old readers are still running → **FULL**.
   - Replay across more than two versions → the **_TRANSITIVE** variant.

   If the needed direction is stricter than the configured rule, say so
   explicitly: the Registry will accept a change that will break consumers.

3. **Run the Registry check for each relevant direction.** Use a dry run so
   nothing is stored:
   ```bash
   curl -s -X POST -H 'Content-Type: application/json' \
     "$REGISTRY/groups/$G/artifacts/$A/versions?dryRun=true" \
     -d "$(jq -nc --rawfile s candidate.avsc '{content:{content:$s,contentType:"application/json"}}')"
   ```
   HTTP 200 = compatible under the active rule; HTTP 400/409 lists the
   incompatible paths in `causes`. To test a direction other than the
   configured one, use a fixture or scratch Registry, not production. If a
   helper script exists in the workspace (for example `registry-check.sh`), use it.

4. **Run client read tests for every writer/reader combination in play.** For
   each writer version that will exist on the topic (old and new) and each
   consumer at each reader version it may run during the rollout:
   - Decode real or representative events, **including edge values the change
     introduces** (nulls, new enum symbols, defaults, empty values).
   - Check the consumer's contract: the fields it depends on are present and
     have usable values after decoding. Schema compatibility does not prove
     that a consumer that requires a field can handle its default or a null.

   Record each combination as PASS, FAIL (with the reason) or UNVERIFIED (with
   what is missing).

5. **Interpret the results and decide.**
   - **Accept** only if every combination that will occur during the rollout
     passes and no constraint from step 1 is unknown.
   - **Request changes** if any combination fails. Propose a safer path,
     typically expand → migrate → contract: add the new field alongside the old
     one, upgrade consumers, then remove the old field in a later release
     (re-verified on its own). Alternatively, use a new topic or artifact for a
     truly breaking change.
   - **Ask for missing information** if any relevant combination is
     UNVERIFIED. Name exactly what is needed and from whom (consumer owner).

6. **Write the change proposal.** Use this structure:
   ```markdown
   ## Decision: Accept | Request changes | Ask for missing information
   ## Change summary
   ## Constraints (with source for each; mark assumptions)
   ## Required compatibility direction and why
   ## Evidence
   | Check | Rule/combination | Result | Detail |
   ## Release sequence
   ## Not verified / limitations
   ## Questions for owners (if any)
   ```
   Report only what was actually executed. Never state that a combination is
   safe unless a check in the evidence table covers it.
