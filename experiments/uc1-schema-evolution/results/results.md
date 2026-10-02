# UC1 results: run of 2026-10-02

**Pre-registered verdict (see `../rubric.md`): NO DEMONSTRATED VALUE for the
skill as installed.** Exploratory findings below explain why and what to test
next. They are hypotheses, not conclusions.

## Setup

| Item | Value |
|---|---|
| Agent under test | Claude Code 2.1.280, headless (`claude -p`), model `claude-sonnet-4-5@20250929` |
| Isolation | Fresh workspace per trial, containing only the fixture and one scenario. `--setting-sources project`. No user-level skills or CLAUDE.md. Separate Registry group per trial. |
| Registry | Apicurio Registry 3.4.0-SNAPSHOT (fixture, port 8081) |
| Design | 3 scenarios × 3 arms × 3 runs = 27 trials, order randomized (seed 20261002, `raw/trial-plan.txt`), up to 9 running concurrently |
| Runner | `../harness/run-trial.sh` |
| Scoring | Blind: arm labels and the words "skill"/"checklist" removed, random IDs, one scorer (separate LLM agent) per scenario with rubric, answer key and the list of executed commands. Key: `raw/blind-key.json` |
| Follow-ups | None needed. Every trial produced a proposal without asking the human anything mid-run, so the scripted answers were never used. |
| Total agent cost | $8.41 |

## Trial log

| Trial | Scenario | Arm | Skill loaded | Decision | Score /10 | Critical | Time (s) | Turns | Cost |
|---|---|---|---|---|---|---|---|---|---|
| t01 | S1 | baseline | n/a | accept | 10 | no | 151 | 28 | $0.35 |
| t11 | S1 | baseline | n/a | accept | 8 | no | 77 | 17 | $0.19 |
| t20 | S1 | baseline | n/a | accept | 9 | no | 143 | 27 | $0.30 |
| t03 | S1 | checklist | n/a | accept | 10 | no | 127 | 22 | $0.27 |
| t10 | S1 | checklist | n/a | accept | 9 | no | 179 | 28 | $0.40 |
| t17 | S1 | checklist | n/a | accept | 10 | no | 124 | 27 | $0.29 |
| t09 | S1 | skill | **no** | accept | 9 | no | 110 | 20 | $0.24 |
| t25 | S1 | skill | yes | accept | 10 | no | 125 | 22 | $0.27 |
| t27 | S1 | skill | yes | accept | 10 | no | 157 | 29 | $0.41 |
| t15 | S2 | baseline | n/a | request changes | 9 | no | 146 | 23 | $0.34 |
| t18 | S2 | baseline | n/a | request changes | 9 | no | 154 | 30 | $0.37 |
| t23 | S2 | baseline | n/a | request changes | 8 | no | 138 | 24 | $0.32 |
| t07 | S2 | checklist | n/a | request changes | 10 | no | 152 | 21 | $0.32 |
| t19 | S2 | checklist | n/a | request changes | 9 | no | 154 | 23 | $0.32 |
| t24 | S2 | checklist | n/a | request changes | 10 | no | 150 | 23 | $0.31 |
| t08 | S2 | skill | **no** | request changes | 8 | no | 107 | 21 | $0.24 |
| t13 | S2 | skill | **no** | request changes | 8 | no | 109 | 21 | $0.28 |
| t22 | S2 | skill | **no** | request changes | 8 | no | 104 | 20 | $0.28 |
| t02 | S3 | baseline | n/a | request changes | 6 | no | 136 | 27 | $0.32 |
| t14 | S3 | baseline | n/a | request changes + ask | 8 | no | 149 | 20 | $0.27 |
| t16 | S3 | baseline | n/a | request changes | 6 | no | 122 | 19 | $0.25 |
| t04 | S3 | checklist | n/a | request changes + ask | 9 | no | 176 | 26 | $0.39 |
| t06 | S3 | checklist | n/a | **ask** | 10 | no | 185 | 29 | $0.38 |
| t12 | S3 | checklist | n/a | request changes | 8 | no | 148 | 24 | $0.35 |
| t05 | S3 | skill | **no** | request changes | 7 | no | 144 | 27 | $0.36 |
| t21 | S3 | skill | yes | **ask** | 10 | no | 147 | 22 | $0.32 |
| t26 | S3 | skill | **no** | request changes | 7 | no | 126 | 20 | $0.26 |

Proposals, executed commands and run metadata for each trial are in `raw/`.

## Summary by arm (as assigned)

| Scenario | Arm | n | Mean score | Critical errors | Median time | Mean cost |
|---|---|---|---|---|---|---|
| S1 | baseline | 3 | 9.00 | 0 | 143 s | $0.28 |
| S1 | checklist | 3 | 9.67 | 0 | 127 s | $0.32 |
| S1 | skill | 3 | 9.67 | 0 | 125 s | $0.31 |
| S2 | baseline | 3 | 8.67 | 0 | 146 s | $0.35 |
| S2 | checklist | 3 | 9.67 | 0 | 152 s | $0.32 |
| S2 | skill | 3 | 8.00 | 0 | 107 s | $0.27 |
| S3 | baseline | 3 | 6.67 | 0 | 136 s | $0.28 |
| S3 | checklist | 3 | 9.00 | 0 | 176 s | $0.38 |
| S3 | skill | 3 | 8.00 | 0 | 144 s | $0.31 |
| **S2+S3** | **baseline** | 6 | **7.67** | 0 | | |
| **S2+S3** | **checklist** | 6 | **9.33** | 0 | | |
| **S2+S3** | **skill** | 6 | **8.00** | 0 | | |

## Verdict against pre-registered thresholds

| Verdict | Met? | Why |
|---|---|---|
| SKILL ADDS VALUE | No | Baseline made 0 critical errors (needed ≥2). Skill gain on S2/S3 is +0.33 (needed ≥2.0). |
| CONTENT ADDS VALUE, SKILL MECHANISM DOES NOT | No (formally) | Requires the skill to meet the first conditions, which it did not |
| **NO DEMONSTRATED VALUE** | **Yes** | Skill 8.00 < baseline + 1.0 (8.67); critical errors 0 vs 0 |

## Exploratory findings (not pre-registered; n is small)

1. **The skill was only loaded in 3 of 9 trials.** Claude Code invoked
   `evolve-event-schema` in t21, t25 and t27 only. In the other 6, it was
   installed and matched the task but was never used. So the skill arm
   measured mostly *auto-invocation* and only partly the skill's content.
2. **When the skill was loaded, it scored 10/10 in 3 of 3 trials**, including
   the only skill-arm S3 run that correctly stopped to ask (t21). Trials where
   it was not loaded averaged 7.83.
3. **The same guidance as plain text (checklist arm) had the best S2+S3 score:
   9.33 vs 7.67 baseline (+1.67).** It was always "loaded" because it was in
   the prompt. Its biggest gain was on S3 (missing context): +2.33 over
   baseline, and 2 of 3 runs explicitly asked for the missing information,
   versus 1 of 3 for baseline.
4. **No arm made a critical error.** Sonnet 4.5 never accepted S2 or S3. The
   expected trap (trusting the configured BACKWARD rule) did not catch the
   baseline. The likely reason is that the fixture's `read-matrix.sh` and
   `consumers.json` (which include each consumer's required fields) make
   failures visible to anyone who runs them, and every arm did. This matches
   the deck's "what could make this unnecessary?" question: **good tools plus
   a consumer inventory already prevent the dangerous outcome**. The guidance
   improved reasoning quality (the right compatibility direction, asking
   instead of assuming), not safety.
5. **Cost and time:** no meaningful overhead. Checklist S3 was slower (median
   176 s vs 136 s), within the 1.5× limit.

## What the data supports saying

- As installed and auto-invoked today, the skill **did not show measurable
  value** on these scenarios.
- The skill's *content* is associated with better proposals when it actually
  reaches the model (checklist arm, and the 3 trials where the skill loaded).
  That's a hypothesis for the next run, not a result.
- The deterministic tools (a read matrix with consumer contracts) carried most
  of the safety value. That points toward the value being in **tooling and a
  consumer inventory**, with guidance as a smaller second layer.

## Threats to validity

- n = 3 per cell. Differences of 1–2 points can be noise.
- One model (Sonnet 4.5). Weaker or stronger models may differ.
- The skill author also wrote the scenarios, the answer key, ran the trials
  and wrote the scoring prompts. Blind scoring reduces but does not remove
  this bias.
- The scorer is also an LLM. It gave partial credit (C1 = 3) for "request
  changes + ask" on S3, a level the rubric does not define. Scores are not
  double-rated by a human.
- Scenarios are constructed. The fixture's read matrix may make the task
  easier than a real repository would.
- Headless single-shot runs: no real developer interaction.

## Suggested next run (to decide at the discussion)

1. **Isolate content from activation:** rerun the skill arm with the skill
   explicitly invoked (`/evolve-event-schema` in the prompt) and compare with
   the checklist arm. Also improve the skill `description` and measure the
   auto-invocation rate on its own.
2. **Make the trap real:** add a scenario variant *without* a read matrix and
   consumer contracts (only the Registry and source code of the consumers), so
   the assistant must discover consumer dependencies. That's closer to real
   repositories and tests the "gathering constraints" claim.
3. Add a second model and a human scorer for a subset.
