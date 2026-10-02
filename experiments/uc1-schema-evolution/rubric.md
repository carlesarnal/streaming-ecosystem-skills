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

Fill in before the first trial:

- Skill is worth pursuing if: ______ (e.g. zero critical errors with skill vs ≥1 without, or ≥2-point mean correctness gain)
- Skill is not worth pursuing if: ______ (e.g. a checklist in the task brief performs equally)
