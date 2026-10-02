# UC1 scoring rubric

Fix this rubric **before** any trial. Score every proposal blind to the arm
(with skill / without skill): strip arm identifiers before review.

## Correctness (per proposal, 0–10)

| # | Criterion | Points |
|---|---|---|
| C1 | Decision matches the answer key | 4 (S3: "request changes" with the right questions = 2) |
| C2 | Required compatibility direction identified and justified from the release order | 2 |
| C3 | Evidence covers every writer/reader combination that occurs during rollout | 2 |
| C4 | "Not verified" section is accurate: no claim exceeds executed evidence | 1 |
| C5 | Release sequence is safe and actionable | 1 |

**Critical error (score capped at 0):** accepting a change the answer key
rejects, or claiming a check that was not run.

## Process metrics (per trial)

| Metric | How to measure |
|---|---|
| Time to proposal | Wall clock from task start to final proposal (agent + human turns) |
| Human turns | Number of human messages after the initial brief |
| Rework | Times the proposal had to be corrected after the human pointed out an error |
| Tool calls / checks run | From the transcript |
| Cost | Input + output tokens (or provider-reported cost) |
| Asked when needed | S3: did it stop and ask before deciding? (yes/no) |

Report setup cost (fixture, skill authoring) separately; it is not part of
per-trial cost.

## Decision thresholds (agree before running)

Pre-registered on 2026-10-02 by Carles, before any trial, and committed
before the first run. Design: 3 scenarios × 3 arms (baseline, skill,
checklist) × 3 runs = 27 trials.

**Primary outcome:** critical errors (rate per arm, S2 + S3 = 6 trials per arm).
**Secondary:** mean correctness on S2 + S3; S1 time and cost overhead.

| Verdict | Condition (all must hold) |
|---|---|
| **SKILL ADDS VALUE** | Skill arm: 0 critical errors on S2/S3 **and** baseline: ≥2 critical errors on S2/S3 (or a skill mean correctness gain on S2/S3 of ≥2.0 points over baseline); **and** on S1 the skill arm's mean correctness is ≥8 and median time ≤ 1.5× baseline; **and** the skill beats checklist by ≥1.0 point mean correctness on S2/S3 or by ≥1 fewer critical error. |
| **CONTENT ADDS VALUE, SKILL MECHANISM DOES NOT** | The skill meets the first two conditions above, but the checklist arm is within 1.0 point and has no more critical errors. Recommendation: ship the guidance as docs/checklist; the skill packaging is not justified by this data. |
| **NO DEMONSTRATED VALUE** | Skill mean correctness on S2/S3 is < baseline + 1.0 **and** critical errors are not lower than baseline. Recommendation: stop or change the case. |
| **INCONCLUSIVE** | Anything else. Recommendation: more runs or more scenarios before deciding. |

With n = 3 per cell, these thresholds can detect large effects only. A
difference of 1–2 trials is reported as a direction, not as proof.
