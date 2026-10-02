# UC1 · Evolve an event schema: discussion brief

**For:** Joe, Andreu · **From:** Carles · **Date:** 2026-10-02
**Status:** Experiment built, thresholds pre-registered, 27 trials run and
blind-scored on 2026-10-02. Results are in section 5 and `results/results.md`.

> **TL;DR:** Pre-registered verdict: **no demonstrated value for the skill
> as installed.** Main reason: Claude Code only auto-invoked it in 3 of 9
> trials. When the guidance did reach the model, proposals were better
> (checklist arm +1.67 points on the hard scenarios; skill-loaded trials 10/10).
> No arm ever approved a breaking change: the deterministic tools prevented
> the dangerous outcome by themselves. The value seems to be in tooling plus a
> consumer inventory, with guidance as a smaller second layer. One clear next
> run would confirm or reject this.
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

## 5. Results (run of 2026-10-02)

### 5.1 How it ran

- **Thresholds** were written into `rubric.md` and committed (`9b2e9c8`)
  **before** the first trial.
- **27 trials:** 3 scenarios × 3 arms (baseline, skill, checklist) × 3 runs,
  randomized order. Claude Code 2.1.280 headless, model **Sonnet 4.5**, a fresh
  isolated workspace and Registry group per trial.
- **Blind scoring:** arm labels removed, random IDs, one LLM scorer per
  scenario with the rubric, answer key and the list of commands each trial
  actually ran.
- **Total cost: $8.41.** About 2 minutes per trial.

### 5.2 Headline numbers

| | Baseline | Skill (as assigned) | Checklist |
|---|---|---|---|
| Critical errors (27 trials) | 0 | 0 | 0 |
| S1 mean score (safe change) | 9.00 | 9.67 | 9.67 |
| S2 mean score (rename trap) | 8.67 | 8.00 | 9.67 |
| S3 mean score (missing context) | 6.67 | 8.00 | 9.00 |
| **S2+S3 mean score** | **7.67** | **8.00** | **9.33** |
| S3 runs that asked for missing info | 1/3 | 1/3 | 2/3 |
| Skill actually loaded | n/a | **3/9** | n/a |

### 5.3 Verdict against pre-registered thresholds

**NO DEMONSTRATED VALUE** for the skill as installed. "Skill adds value"
needed ≥2 baseline critical errors or a ≥2.0-point gain; we observed 0
errors and +0.33.

### 5.4 What explains it (exploratory)

1. **Activation, not content, is the weak point.** The skill was installed
   and matched the task, but Claude Code invoked it in only 3 of 9 runs.
   Those 3 runs scored **10/10**. The 6 runs that didn't load it averaged
   7.83, about the same as the baseline.
2. **The content helps when it reaches the model.** The checklist arm (same
   text, in the prompt) was best on the hard scenarios: **+1.67** over
   baseline on S2+S3 and **+2.33** on S3, mainly by asking for missing
   information instead of assuming, and by choosing the right compatibility
   direction.
3. **The tools did the safety work.** No arm approved a breaking change.
   Every arm ran the read matrix, which encodes each consumer's required
   fields and makes failures obvious. The dangerous outcome we expected the
   skill to prevent never happened in the baseline either. This answers the
   deck's "what could make this unnecessary?": **good tools plus a consumer
   inventory** cover safety; guidance improves reasoning quality.

### 5.5 Caveats

n = 3 per cell; one model; the author built the skill, scenarios and scoring
prompts; LLM scorer without a human second rating; constructed scenarios with
a helpful read matrix. Full list in `results/results.md`.

## 6. Decisions needed

1. **How to read this result.** Options:
   - (a) Take the result as it stands: skills as auto-invoked packages don't
     pay off here; invest in tools and inventory.
   - (b) **Recommended:** one more targeted run (about 1 day, about $10)
     before concluding, because the result depends on activation, which is
     fixable.
2. **Scope of the follow-up run** (if b):
   - Skill explicitly invoked vs checklist vs baseline: is it the content or
     the packaging?
   - Improve the skill description and measure the auto-invocation rate on
     its own.
   - A harder scenario variant **without** the read matrix and consumer
     contracts (only Registry plus consumer source code), so the assistant
     has to discover dependencies. That's closer to real repos and the only
     setting where the "gathering constraints" claim is really tested.
3. **Second model** (for example Opus) and a **human scorer** for a subset.
4. **Customer track:** who recruits customers to check that the scenarios
   match real episodes.
5. **Product implication to discuss:** if tools carry the value, is the
   RHAF deliverable a skill, or a Registry feature (for example "check
   against all consumer reader versions" / FORWARD check of the release
   plan) plus a thin skill?

## 7. Limitations and threats to validity

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

## 8. Incident during setup

The first check run hit an existing local Registry on port 8080
(`agent-discovery-demo`, 3.3.0). That instance now has an extra artifact
`orders/orders.order-created-value` (v1, BACKWARD rule). Deletes are disabled
there, so it needs a container reset. Fixed by moving the fixture to port 8081.

## 9. Proposed next steps

| # | Step | Owner | Effort |
|---|---|---|---|
| 1 | Discuss results and pick option (a) or (b) from section 6 | Joe, Andreu, Carles | 30–45 min meeting |
| 2 | If (b): fix the skill description; add the explicit-invocation arm and the no-read-matrix scenario | Carles | 0.5 day |
| 3 | If (b): rerun (add a second model if agreed), same pre-registration process | Carles | 0.5 day, about $10–20 |
| 4 | Human second scoring of a subset of proposals | TBD (not Carles) | 2 h |
| 5 | Final write-up: extend, change or stop | All | 0.5 day |

## 10. Repository map

```
.claude/skills/evolve-event-schema/SKILL.md   Skill under test
experiments/uc1-schema-evolution/
  DISCUSSION.md        This document
  README.md            Trial protocol
  rubric.md            Scoring and pre-registered thresholds
  answer-key/          Expected outcomes (hidden from agents)
  harness/run-trial.sh Headless Claude Code trial runner
  results/results.md   Full trial log, verdict, exploratory findings
  results/raw/         Per-trial proposals, commands run, cost/usage, blind key
  fixture/             Kafka + Registry, checks, read matrix
  scenarios/s1..s3     Task briefs, candidate schemas, sample events
```
