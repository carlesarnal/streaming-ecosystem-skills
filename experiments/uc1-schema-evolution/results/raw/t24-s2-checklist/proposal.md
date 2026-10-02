# Change Proposal: OrderCreated Schema v2 (Field Rename: currency → currencyCode)

## Decision: **Request changes**

The proposed v2 schema renames the `currency` field to `currencyCode` without retaining the old field. This is a **breaking change** that will cause production failures regardless of release order.

## Change summary

Proposed change renames `currency` (string, required) to `currencyCode` (string, with default "EUR") in the OrderCreated event schema.

Current v1 schema:
```json
{"name": "currency", "type": "string"}
```

Proposed v2 schema:
```json
{"name": "currencyCode", "type": "string", "default": "EUR", "doc": "ISO 4217 code. Replaces the old currency field."}
```

## Constraints

**Source: `fixture/consumers.json`**

- **Topic**: `orders.order-created`
- **Registry**: 
  - Group: `orders-t24`
  - Artifact: `orders.order-created-value`
  - Type: AVRO
  - Configured compatibility rule: **BACKWARD**
- **Producer**: order-service (current schema: v1, wants to ship v2 next week)
- **Retention/replay**: Unknown/assumed — old events may need to be readable (not explicitly documented)
- **Serde**: Apicurio Avro deserializer (all consumers)

**Consumer inventory:**

1. **order-router** (team-fulfilment)
   - Reader schema: v1
   - Release cadence: weekly
   - Required fields: `orderId`, `customerId`, `amount`
   - Does **NOT** require `currency` field

2. **billing** (team-billing)
   - Reader schema: v1
   - Release cadence: monthly
   - Required fields: `orderId`, `amount`, **`currency`**
   - **CRITICAL**: Billing's contract explicitly requires the `currency` field

## Required compatibility direction and why

**Producer ships before consumers upgrade** (or independent release schedules):
- Producer could deploy v2 next week
- billing releases monthly → billing will still be running v1 reader when v2 events arrive
- **FORWARD compatibility required**: old readers (v1) must be able to read new data (v2)

**Additional consideration:**
- Configured rule is BACKWARD only
- Even if BACKWARD passes, it doesn't guarantee consumer contracts are satisfied
- billing requires the `currency` field, which doesn't exist in v2 schema

## Evidence

| Check | Rule/Combination | Result | Detail |
|-------|------------------|--------|--------|
| Registry compatibility | BACKWARD | ✅ PASS | New schema (v2) can structurally read old events (v1) |
| Registry compatibility | FORWARD | ❌ FAIL | Old schema (v1) cannot read new events (v2). Incompatibility: `currency` field at `/fields/3` |
| Registry compatibility | FULL | ❌ FAIL | Same as FORWARD |
| Client read test | v1 writer → order-router v1 reader | ✅ PASS | Current state: decoded 2 samples, contract satisfied |
| Client read test | v1 writer → order-router v2 reader | ✅ PASS | order-router can upgrade to v2 and still read old events |
| Client read test | v1 writer → billing v1 reader | ✅ PASS | Current state: decoded 2 samples, contract `[orderId, amount, currency]` satisfied |
| Client read test | v1 writer → billing v2 reader | ❌ FAIL | **Required field 'currency' absent from reader schema** |
| Client read test | v2 writer → order-router v1 reader | ❌ FAIL | **Cannot decode**: `missing required field currency` |
| Client read test | v2 writer → order-router v2 reader | ✅ PASS | order-router can work with v2 on both sides |
| Client read test | v2 writer → billing v1 reader | ❌ FAIL | **Cannot decode**: `missing required field currency` |
| Client read test | v2 writer → billing v2 reader | ❌ FAIL | **Required field 'currency' absent from reader schema** |

**Summary**: 4 of 8 writer/reader combinations failed. All failure scenarios involve either:
1. v1 readers trying to read v2 events (missing `currency` field), or
2. v2 readers trying to satisfy billing's contract (field renamed, contract broken)

## Release sequence

**This change cannot be safely deployed in any single-step release order:**

- ❌ **Producer first**: billing (v1 reader) cannot decode v2 events → production outage
- ❌ **Consumers first**: billing (v2 reader) cannot satisfy its contract (requires `currency` field) → breaks billing service even before new events arrive

**Recommended alternative: Expand-Migrate-Contract pattern**

1. **Phase 1 - Expand** (week 1):
   - Modify v2 schema to include **both** `currency` and `currencyCode` fields
   - `currencyCode` can be the preferred field, but keep `currency` populated
   - Deploy producer (order-service) with v2a schema
   - Both fields present in new events ensures all consumers continue working

2. **Phase 2 - Migrate** (week 2-5):
   - Upgrade order-router to read from `currencyCode` (weekly release)
   - Upgrade billing to read from `currencyCode` (monthly release - wait for their cycle)
   - Verify both consumers have migrated and are healthy

3. **Phase 3 - Contract** (after all consumers migrated):
   - Create v3 schema that removes the old `currency` field
   - Run this same verification process for v3
   - Deploy producer with v3

This approach ensures zero downtime and maintains all consumer contracts throughout the migration.

## Not verified / limitations

1. **Historical data replay**: Unknown whether old events need to be replayable by future consumers. If yes, the `currency` field must be retained indefinitely or a backfill strategy is needed.

2. **Other consumers**: Only two consumers documented in `consumers.json`. Unknown if there are undocumented consumers reading this topic. **Recommend**: 
   - Check topic consumer groups in Kafka: `kafka-consumer-groups --list --bootstrap-server <broker>`
   - Verify all active consumers are documented

3. **Schema evolution beyond v2**: The expand-migrate-contract approach requires multiple releases. Timeline depends on billing's monthly cadence (minimum ~4-5 weeks for complete migration).

4. **Default value semantics**: The v2 schema includes `"default": "EUR"` for `currencyCode`. Not verified whether this default is appropriate for the billing service's use case when reading old v1 events (which have actual currency values that would be lost).

5. **Backward compatibility claim**: While the registry BACKWARD check passed, this only validates schema structure. It does **not** verify that:
   - Consumer contracts remain satisfied
   - Business logic can handle field renames
   - Default values are semantically correct substitutes for actual data

## Questions for owners

**team-billing (billing service owner):**

1. Can billing's business logic be modified to read from `currencyCode` instead of `currency`? What is the migration effort?

2. Is the EUR default value acceptable for billing when processing old v1 events (which have actual currency values in the `currency` field)?

3. What is the next available release window for billing to deploy schema changes (given monthly cadence)?

4. Are there any archived/historical events in the topic that billing may need to replay in the future?

**team-fulfilment (order-router owner):**

1. Can order-router upgrade to read from `currencyCode` in the next weekly release?

**order-service (producer owner):**

1. Is there flexibility in the next week deployment deadline to accommodate the expand-migrate-contract approach?

2. Can order-service populate both `currency` and `currencyCode` fields during the migration phase?
