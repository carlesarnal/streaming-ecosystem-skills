# Change Proposal: Add `channel` field to OrderCreated

## Decision: Accept

The proposed change can be shipped safely with any release order.

## Change summary

Add a new `channel` field to the `OrderCreated` event schema (v1 → v2):
- **Field name:** `channel`
- **Type:** `string`
- **Default value:** `"web"`
- **Purpose:** Track which sales channel (web, mobile, etc.) the order originated from
- **Documentation:** "Sales channel. Informational only."

## Constraints

| Constraint | Value | Source |
|------------|-------|--------|
| Topic | `orders.order-created` | `fixture/consumers.json` |
| Registry group | `orders-t25` | `fixture/consumers.json` |
| Registry artifact | `orders.order-created-value` | `fixture/consumers.json` |
| Artifact type | `AVRO` | Registry configuration |
| Configured compatibility rule | `BACKWARD` | `fixture/consumers.json` |
| Current schema version | v1 (5 fields) | `fixture/schemas/order-created-v1.avsc` |
| Candidate schema version | v2 (6 fields) | `scenarios/s1-add-field/order-created-v2.avsc` |
| **Consumers** | | |
| order-router | Weekly releases, team-fulfilment, currently v1 reader | `fixture/consumers.json` |
| order-router required fields | `orderId`, `customerId`, `amount` | `fixture/consumers.json` |
| billing | Monthly releases, team-billing, currently v1 reader | `fixture/consumers.json` |
| billing required fields | `orderId`, `amount`, `currency` | `fixture/consumers.json` |
| Serde libraries | Apache Camel Kafka + Apicurio Avro deserializer (order-router), Plain Kafka consumer + Apicurio Avro deserializer (billing) | `fixture/consumers.json` |
| **Assumptions** | | |
| Old events must stay readable | Assumed YES (standard practice, but not explicitly documented) | Default assumption |
| Replay requirements | Unknown, not documented | Not specified |

## Required compatibility direction and why

**Required: FULL** (both BACKWARD and FORWARD)

**Reasoning:**
- Consumers have **independent release cadences** (weekly for order-router, monthly for billing)
- Producer (order-service) may ship **before** all consumers upgrade → old readers (v1) must read new data (v2) → requires **FORWARD** compatibility
- Consumers **may** upgrade before producer ships (particularly order-router with weekly cadence) → new readers (v2) must read old data (v1) → requires **BACKWARD** compatibility
- If old events must be replayed (assumed but unconfirmed) → new readers must read old data → requires **BACKWARD** compatibility

**Note:** The configured rule (`BACKWARD`) is **less strict** than the required direction (`FULL`). However, the change passes FULL compatibility, so this is not a concern for this specific change.

## Evidence

### Registry Compatibility Checks

| Check | Rule | Result | Detail |
|-------|------|--------|--------|
| Registry dry-run | BACKWARD (configured) | ✅ PASS | Compatible under configured rule |
| Registry dry-run | FORWARD | ✅ PASS | Compatible for producer-first deployment |
| Registry dry-run | FULL | ✅ PASS | Compatible for any release order |

### Client Read Matrix Tests

All writer/reader combinations tested with representative sample data:

| Writer | Consumer | Reader | Result | Detail |
|--------|----------|--------|--------|--------|
| v1 | order-router | v1* | ✅ PASS | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v1 | order-router | v2 | ✅ PASS | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v1 | billing | v1* | ✅ PASS | Decoded 2 samples; contract [orderId, amount, currency] satisfied |
| v1 | billing | v2 | ✅ PASS | Decoded 2 samples; contract [orderId, amount, currency] satisfied |
| v2 | order-router | v1* | ✅ PASS | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v2 | order-router | v2 | ✅ PASS | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v2 | billing | v1* | ✅ PASS | Decoded 2 samples; contract [orderId, amount, currency] satisfied |
| v2 | billing | v2 | ✅ PASS | Decoded 2 samples; contract [orderId, amount, currency] satisfied |

*\* = reader schema the consumer currently runs*

**Summary:** 8/8 combinations passed, 0 failed, 0 unverified

## Release sequence

Since the change achieves **FULL compatibility**, any release order is safe:

### Recommended sequence (producer-first):

1. **Deploy order-service** with v2 schema
   - Producer begins emitting events with the `channel` field populated
   - Existing v1 consumers continue reading successfully (ignoring the new field)

2. **Consumers upgrade on their normal cadence**
   - order-router: upgrades within 1 week (team-fulfilment, weekly releases)
   - billing: upgrades within 1 month (team-billing, monthly releases)
   - Both can optionally use the `channel` field once upgraded, but it's not required by their contracts

### Alternative (consumer-first) also safe:
- Consumers could upgrade to v2 readers before producer ships
- v2 readers will populate `channel` with default value `"web"` when reading v1 events
- This works because the field has a default value

## Not verified / limitations

1. **Edge cases in sample data:**
   - Test samples included: `channel="mobile"` and `channel="web"`
   - Not tested: empty string, very long channel names, special characters, null (not allowed per schema)
   - Assumption: all channel values will be valid non-empty strings

2. **Replay scenarios:**
   - Not explicitly verified: whether old events from before the schema change must remain readable indefinitely
   - Assumption: standard practice is to support replay, which is why FULL compatibility was required
   - If replay is guaranteed never to occur with v2 readers, FORWARD-only would be sufficient

3. **Multi-version transitions:**
   - Only tested v1 ↔ v2 transitions (single version jump)
   - Not tested: TRANSITIVE compatibility across 3+ versions
   - Relevant only if future schema changes occur before all consumers upgrade to v2

4. **Consumer implementation details:**
   - Verified: deserializer can decode the message and required fields are present
   - Not verified: downstream business logic correctness, database schema changes, API contracts

5. **Performance impact:**
   - Not measured: impact of additional field on message size, serialization/deserialization time
   - Expected to be negligible for a single string field

## Questions for owners

None. All information needed for the decision was available.
