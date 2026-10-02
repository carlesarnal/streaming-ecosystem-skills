# Schema Evolution Change Proposal: OrderCreated v1 → v2

## Decision: Request changes

The proposed schema change is **not safe to ship**. It will break the `billing` consumer in all deployment scenarios.

## Change summary

Rename field `currency` to `currencyCode` to comply with data-standards naming conventions. The v2 schema removes the `currency` field and adds `currencyCode` with a default value of `"EUR"`.

## Constraints (with source for each)

| Constraint | Value | Source |
|------------|-------|--------|
| Topic | `orders.order-created` | fixture/consumers.json |
| Registry group | `orders-t19` | fixture/consumers.json |
| Artifact ID | `orders.order-created-value` | fixture/consumers.json |
| Artifact type | `AVRO` | Apicurio Registry |
| Configured compatibility rule | `BACKWARD` | fixture/consumers.json |
| Current schema version | v1 with field `currency` (string, no default) | fixture/schemas/order-created-v1.avsc |
| Candidate schema version | v2 with field `currencyCode` (string, default `"EUR"`) | scenarios/s2-break-contract/order-created-v2.avsc |
| **Consumer: order-router** | | |
| Owner | team-fulfilment | fixture/consumers.json |
| Current reader schema | v1 | fixture/consumers.json |
| Required fields | `orderId`, `customerId`, `amount` | fixture/consumers.json |
| Release cadence | weekly | fixture/consumers.json |
| Serde | Apache Camel (camel-kafka + Apicurio Avro deserializer) | fixture/consumers.json |
| **Consumer: billing** | | |
| Owner | team-billing | fixture/consumers.json |
| Current reader schema | v1 | fixture/consumers.json |
| Required fields | `orderId`, `amount`, **`currency`** | fixture/consumers.json |
| Release cadence | monthly | fixture/consumers.json |
| Serde | Plain Kafka consumer (Apicurio Avro deserializer) | fixture/consumers.json |
| Retention / replay requirement | **ASSUMED: old events must remain readable** | No explicit documentation found |
| Producer planned ship date | Next week | scenarios/s2-break-contract/task.md |

**Critical constraint:** The `billing` consumer explicitly requires the `currency` field, which is removed in v2.

## Required compatibility direction and why

**Required: FORWARD or FULL** (depending on deployment order)

The configured rule is `BACKWARD`, but the actual deployment constraints require stricter compatibility:

1. **Independent release cycles:** Producer ships next week, but `billing` releases monthly. This means the producer will ship v2 events **before** the billing consumer can upgrade → requires **FORWARD** compatibility (old readers must read new data).

2. **Weekly vs monthly cadence:** Even `order-router` (weekly cadence) may lag behind the producer during rollout windows → requires **FORWARD** compatibility.

3. **Retention/replay:** If old events (v1) must remain readable by new consumers after they upgrade, or if consumers can seek to earliest offset → requires **BACKWARD** compatibility (new readers must read old data).

4. **Combined requirement:** If both (1) and (3) apply → requires **FULL** compatibility.

**The configured `BACKWARD` rule is insufficient for this deployment plan.** The Registry will accept this change under `BACKWARD`, but it will break production consumers.

## Evidence

| Check | Rule/combination | Result | Detail |
|-------|------------------|--------|--------|
| **Registry compatibility checks** | | | |
| Apicurio Registry | `BACKWARD` | ✓ PASS | New readers (v2) can read old data (v1) via `currencyCode` default |
| Apicurio Registry | `FORWARD` | ✗ FAIL | Old readers (v1) cannot read new data (v2): missing required field `currency` at `/fields/3` |
| Apicurio Registry | `FULL` | ✗ FAIL | Same failure as `FORWARD`: field `currency` removed |
| **Consumer read matrix** | | | |
| v1 writer → order-router v1* | Current state | ✓ PASS | Decoded 2 samples; contract `[orderId, customerId, amount]` satisfied |
| v1 writer → order-router v2 | Consumer upgrades first | ✓ PASS | Decoded 2 samples; contract `[orderId, customerId, amount]` satisfied |
| v1 writer → billing v1* | Current state | ✓ PASS | Decoded 2 samples; contract `[orderId, amount, currency]` satisfied |
| v1 writer → billing v2 | Consumer upgrades first | ✗ FAIL | Required field `currency` absent from reader schema |
| v2 writer → order-router v1* | Producer ships before consumer | ✗ FAIL | Sample #1 not decodable: missing required field `currency` |
| v2 writer → order-router v2 | Both upgraded | ✓ PASS | Decoded 2 samples; contract `[orderId, customerId, amount]` satisfied |
| v2 writer → billing v1* | Producer ships before consumer | ✗ FAIL | Sample #1 not decodable: missing required field `currency` |
| v2 writer → billing v2 | Both upgraded | ✗ FAIL | Required field `currency` absent from reader schema |

\* = reader schema version the consumer currently runs (per inventory)

**Summary:** 4 of 8 combinations fail. The `billing` consumer cannot use v2 schema in any scenario because it requires the `currency` field, which is removed in v2.

## Release sequence

**This change cannot be shipped safely with the current design.** No deployment ordering will work:

1. **Producer first** (planned approach) → breaks both consumers when they read new events with v1 readers (missing `currency` field)
2. **Consumers first** → breaks `billing` consumer immediately when it upgrades to v2 reader, even while reading old v1 events (v2 schema doesn't provide `currency` field)
3. **Simultaneous** → same failures as "consumers first"

## Recommended alternative: Expand-migrate-contract pattern

To safely rename the field, use a three-phase approach:

### Phase 1: Expand (v2a)
Add `currencyCode` alongside the existing `currency` field:
```json
{
  "fields": [
    {"name": "orderId", "type": "string"},
    {"name": "customerId", "type": "string"},
    {"name": "amount", "type": "double"},
    {"name": "currency", "type": "string"},
    {"name": "currencyCode", "type": "string"},
    {"name": "createdAt", "type": {"type": "long", "logicalType": "timestamp-millis"}}
  ]
}
```

**Producer change:** Populate **both** `currency` and `currencyCode` with the same value.

**Deployment:** Ship producer immediately (BACKWARD and FORWARD compatible).

### Phase 2: Migrate
**Consumer changes:**
- Update `billing` to read from `currencyCode` instead of `currency` (both fields available)
- Deploy `billing` consumer update

**Timeline:** Wait for `billing` monthly release cycle (~4 weeks)

### Phase 3: Contract (v3)
Remove the deprecated `currency` field:
```json
{
  "fields": [
    {"name": "orderId", "type": "string"},
    {"name": "customerId", "type": "string"},
    {"name": "amount", "type": "double"},
    {"name": "currencyCode", "type": "string"},
    {"name": "createdAt", "type": {"type": "long", "logicalType": "timestamp-millis"}}
  ]
}
```

**Deployment:** Ship producer after confirming all consumers have migrated to `currencyCode`.

**Total timeline:** ~5-6 weeks (1 week for phase 1, 4 weeks for billing monthly release, 1 week for phase 3)

## Not verified / limitations

1. **Retention policy unknown:** Did not verify the topic's retention period. If retention is shorter than the migration window, old v1 events may not need to be readable by v2 consumers, but this was not confirmed.

2. **Replay requirements unknown:** Did not confirm whether consumers ever seek to earliest offset, replay from snapshots, or reprocess historical events.

3. **Other consumers unknown:** Only verified the two consumers listed in `fixture/consumers.json` (`order-router` and `billing`). If there are other unlisted consumers, they were not checked.

4. **Default value semantics:** The v2 schema sets `currencyCode` default to `"EUR"`. This default will be used when v2 readers decode v1 events (which have `currency` but not `currencyCode`). Did not verify whether `"EUR"` is the correct business default for missing values or if all existing v1 events actually use EUR.

5. **Performance impact:** Did not measure the storage or serialization overhead of carrying both fields during the expand phase.

6. **End-to-end testing:** Read matrix tests verify decode-ability and field presence, but do not exercise the full consumer application logic or validate that the values are semantically correct for downstream processing.

## Questions for owners

**For team-billing (owner of `billing` consumer):**

1. How critical is the `currency` field to your processing? Can you tolerate a multi-week migration using the expand-migrate-contract pattern?

2. Are there any business constraints on the migration timeline beyond your monthly release cadence?

3. What is your disaster recovery procedure? Do you ever replay historical events that would require BACKWARD compatibility?

**For team-fulfilment (owner of `order-router` consumer):**

1. While your required fields don't include `currency`, does your application logic use it anywhere? The read matrix shows decode success, but doesn't verify end-to-end functionality.

**For order-service team (producer owner):**

1. What is the retention period for the `orders.order-created` topic?

2. Are there any other consumers not listed in the inventory?

3. What is the urgency of this data-standards compliance change? Does it justify a 5-6 week migration timeline?
