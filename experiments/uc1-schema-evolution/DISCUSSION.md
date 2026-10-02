# UC1 · Evolve an event schema: discussion brief

**For:** Joe, Andreu · **From:** Carles · **Date:** 2026-10-02
**Status:** Experiment built and tooling verified. No trials run yet, so there
are **no ROI results** so far.
**Source:** RHAF Agentic Skills, "Choosing the first experiment" (2026-09-30), Use Case 1.

---

## 1. Why this document

We agreed the only credible way to show the value of RHAF Skills is to pick
one use case, build the skill, and measure it against the same assistant
without the skill. This document covers what was built for Use Case 1, how the
measurement works, what we already know, and what we need to decide before
running trials.

## 2. The use case

> A producer changes an event. Existing consumers cannot all be released
> together. *"Can we change this event safely?"*

- **User:** the developer changing an existing event flow.
- **User outcome:** reach an accepted change and test plan faster, while
  keeping required behavior for the declared consumers.
- **Risk named in the deck:** Registry compatibility APIs, client tests and a
  checklist may already be enough. The skill must add value in **gathering
  constraints, choosing checks and interpreting results**.

## 3. What was built

Everything is in `experiments/uc1-schema-evolution/` plus the skill. Total
effort so far: about 1 day.

### 3.1 The skill: `.claude/skills/evolve-event-schema/SKILL.md`

The skill does not decide compatibility itself. Deterministic tools do that. The
skill adds a method:

1. **Gather constraints first:** topic and artifact, configured rule, every
   consumer (reader version, fields it needs, release cadence, owner), whether
   old events must stay readable, and the serde in use. **If something is
   unknown and could change the decision, stop and ask.**
2. **Work out the compatibility direction actually needed** from the release
   order. Example: the producer ships before consumers upgrade, so FORWARD is
   needed. The configured rule is treated as a policy, not as proof.
3. **Run Registry dry-run checks** for the relevant directions.
4. **Run client read tests** for every writer × consumer × reader combination
   during the rollout, including edge values the change introduces (nulls,
   defaults).
5. **Decide:** accept, request changes (usually add the new field first,
   migrate consumers, then remove the old field), or ask for missing
   information.
6. **Write a fixed-format proposal** with an evidence table and an explicit
   "not verified" section.

### 3.2 Test environment (`fixture/`)

| Component | Purpose |
|---|---|
| `docker-compose.yaml` | Kafka + Apicurio Registry (Registry on port 8081) |
| `consumers.json` | Topic, artifact, BACKWARD rule, two consumers: `order-router` (Camel, weekly releases) and `billing` (plain Kafka consumer, monthly releases) |
| `schemas/`, `samples/` | `OrderCreated` v1 schema and events |
| `scripts/registry-check.sh` | Dry-run compatibility check under any rule. Nothing is stored. |
| `scripts/read-matrix.sh` | Decodes v1 and v2 events with each consumer's v1 and v2 reader schema and checks each consumer's required fields |

### 3.3 Scenarios (`scenarios/`)

Each scenario has a task brief given word for word to every arm, a candidate v2
schema and sample events.

| | Change | What makes it hard | Expected decision |
|---|---|---|---|
| **S1** | Add `channel` with a default | Nothing. This is a control: the skill must not slow down easy cases. | Accept |
| **S2** | Rename `currency` → `currencyCode` | The configured BACKWARD rule **passes**, but consumers on the old schema can't read new events, and billing needs `currency` | Request changes |
| **S3** | Make `customerId` nullable (guest checkout) | BACKWARD **passes**; order-router needs `customerId`; billing's details and the replay requirement are unknown | Ask for missing information |

### 3.4 Verified tool results

These were run on 2026-10-02 against Apicurio Registry 3.3.0 and
3.4.0-SNAPSHOT (identical results) and Avro 1.12.0.

| Scenario | BACKWARD (configured) | FORWARD | FULL | Read matrix |
|---|---|---|---|---|
| S1 | compatible | compatible | compatible | 8 PASS |
| S2 | **compatible** | incompatible (`currency`) | incompatible | 4 FAIL |
| S3 | **compatible** | incompatible (null vs string) | incompatible | 3 FAIL, 3 UNVERIFIED |

**Key point:** in S2 and S3, an assistant that runs the obvious check (the
Registry rule as configured) gets "compatible" and could approve a change that
breaks production consumers. The tools contain the right answer, but only if
someone asks the right question. This is exactly the gap the skill claims to
fill, and it's what we measure.

## 4. How we measure

Full protocol: `README.md`. Scoring: `rubric.md`.

### 4.1 Arms (same model, tools, permissions, environment and budget)

| Arm | Setup | What it tells us |
|---|---|---|
| **Baseline** | No skill | What the assistant does on its own |
| **Skill** | `evolve-event-schema` installed | The skill's effect |
| **Checklist** (optional) | No skill; the same steps pasted as plain text in the brief | Whether a simple checklist does just as well. This is the deck's "what could make this unnecessary?" |

### 4.2 Procedure

- 3 scenarios × 2–3 arms × at least 3 runs each = **18–27 trials**.
- Each trial runs in a clean copy of the experiment without the answer key,
  rubric or results, with a fresh Registry.
- Follow-up questions are answered from a fixed script. Anything else gets
  "I don't know".
- Proposals are scored **blind** to the arm.

### 4.3 Metrics

| Metric | Why |
|---|---|
| **Correctness (0–10)** against the answer key | Main quality measure |
| **Critical errors:** approving a change that should be rejected, or claiming a check that wasn't run | The strongest ROI signal: a production incident avoided |
| Time to proposal | Developer effort |
| Human turns, rework | Specialist effort and handoffs |
| Tokens / cost | Running cost |
| Asked when needed (S3) | Whether it gathers constraints instead of guessing |

Setup cost (fixture, writing the skill) is reported separately.

## 5. Decisions needed

1. **Pass/fail thresholds** must be agreed **before** the first trial, otherwise
   the result is open to interpretation. Proposal:
   - *Continue* if the skill arm has zero critical errors and the baseline has
     ≥1, **or** mean correctness improves by ≥2 points on S2/S3, with no
     regression on S1 (time within +25%).
   - *Stop or redirect* if the checklist arm matches the skill arm. In that
     case the value is in the content, not the skill mechanism, so we ship
     docs or a checklist instead.
2. **Model(s)** to test. One model is cheaper; two show whether the result
   holds across models.
3. **Include the checklist arm?** Recommended: it answers the deck's own
   "what could make this unnecessary?" question.
4. **Who runs and who scores.** Scoring should be done by someone who didn't
   run the trial.
5. **Capacity:** about 2–3 more days (trials plus scoring and write-up), within
   the deck's 3–5 day estimate.
6. **Customer track:** who recruits customers to check that the scenarios
   match real episodes (runs in parallel; not blocking).

## 6. Limitations and threats to validity

- **Constructed scenarios**, not observed customer cases. Mitigation: customer
  track; replace or add scenarios with real episodes.
- **Small sample:** 3 scenarios, a few runs each. Enough to spot a large effect
  (for example, critical errors), not small differences.
- **The skill author also wrote the scenarios**, so there's a risk the skill
  is tuned to them. Mitigation: blind scoring; add at least one scenario
  written by someone else before drawing conclusions.
- **Simulated consumers:** the read matrix uses Avro schema resolution, not the
  Camel route or Apicurio serializers running on Kafka. Adequate for the
  decision being tested; real client tests only if the results look
  questionable.
- **Avro only**, one version step, two consumers.
- **Leakage:** the answer key is in the same repo, so trials must run in a
  copy without it (documented in the protocol).

## 7. Incident during setup

The first check run hit an existing local Registry on port 8080
(`agent-discovery-demo`, 3.3.0). That instance now has an extra artifact
`orders/orders.order-created-value` (v1, BACKWARD rule). Deletes are disabled
there, so it needs a container reset. Fixed by moving the fixture to port 8081.

## 8. Proposed next steps

| # | Step | Owner | Effort |
|---|---|---|---|
| 1 | Agree thresholds, model(s), arms (section 5) | Joe, Andreu, Carles | 30 min meeting |
| 2 | Optional: add one scenario written by someone other than Carles | TBD | 0.5 day |
| 3 | Run trials | Carles | 1–1.5 days |
| 4 | Blind scoring | TBD (not the runner) | 0.5 day |
| 5 | Write-up against thresholds; decide whether to extend, change or stop | All | 0.5 day |

## 9. Repository map

```
.claude/skills/evolve-event-schema/SKILL.md   Skill under test
experiments/uc1-schema-evolution/
  DISCUSSION.md        This document
  README.md            Trial protocol
  rubric.md            Scoring and thresholds
  answer-key/          Expected outcomes (hidden from agents)
  results/results.md   Trial log
  fixture/             Kafka + Registry, checks, read matrix
  scenarios/s1..s3     Task briefs, candidate schemas, sample events
```
