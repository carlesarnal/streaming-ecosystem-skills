# UC1 answer key: DO NOT expose to the agent under test

Keep this directory out of the agent's workspace during runs (see
`../README.md`, "Running a trial"). Verified on 2026-10-02 against Apicurio
Registry 3.3.0 and 3.4.0-SNAPSHOT, Avro 1.12.0.

## Observed deterministic results

| Scenario | BACKWARD (configured) | FORWARD | FULL | Read matrix |
|---|---|---|---|---|
| S1 add field | compatible | compatible | compatible | 8/8 PASS |
| S2 rename field | **compatible** | incompatible (`currency`) | incompatible | 4 FAIL |
| S3 nullable customerId | **compatible** | incompatible (null vs string) | incompatible | 3 FAIL, 3 UNVERIFIED |

The trap in S2 and S3: the configured BACKWARD rule accepts both, but the
consumers lag the producer, so the safe direction is FORWARD (or FULL).

## S1 · Expected outcome: Accept
- Producer may ship first; v1 readers ignore `channel`, v2 readers default it.
- Evidence must cover v1/v2 writer × both consumers × v1/v2 reader.
- Limitations worth stating: sample data only; no real Camel/Kafka run.

## S2 · Expected outcome: Request changes
- Under independent releases, v1 readers (order-router, billing) fail on v2
  data: `currency` is missing and has no default.
- billing also depends on `currency` itself, so even an upgraded billing
  breaks.
- Acceptable safe paths: expand/contract (add `currencyCode` and keep
  `currency`, migrate billing, remove `currency` later as a separately
  verified change), or upgrade every consumer before the producer. The second
  still breaks billing's contract.
- **Critical error:** accepting because the Registry BACKWARD check passed.

## S3 · Expected outcome: Ask for missing information
- order-router requires `customerId`; v2 guest orders carry null → v1 reader
  cannot decode, v2 reader yields null where a value is required.
- billing's reader version, contract and cadence are unknown; replay
  requirements are undocumented.
- Must ask: billing owner (reader version, uses customerId?), replay/retention
  requirement, and whether order-router can handle guest orders (product
  decision, not just schema).
- **Critical errors:** accepting; or rejecting without naming the missing
  information. Request changes with explicit questions scores partially (see
  rubric).
