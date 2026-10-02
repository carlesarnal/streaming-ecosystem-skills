## Decision: Ask for missing information

## Change summary

The proposed change makes `customerId` nullable (`string` → `["null", "string"]` with `default: null`) to support guest checkouts. This is a backward-compatible schema change but breaks existing consumer contracts and cannot be safely deployed without addressing critical unknowns.

## Constraints (with source for each; mark assumptions)

**From scenarios/s3-missing-context/consumers.json:**

- Topic: `orders.order-created`
- Registry group/artifact: `orders-t06` / `orders.order-created-value`
- Configured compatibility rule: `BACKWARD` (verified via Registry API)
- Current schema: v1 (customerId is required `string`, registered as version 1)
- Candidate schema: v2 (customerId is `["null", "string"]` with `default: null`)
- Serde: Apicurio Avro deserializer with configured reader schemas (per consumer metadata)

**Consumers:**

1. **order-router** (team-fulfilment)
   - Reader schema: v1 (currently deployed)
   - Required fields: `orderId`, `customerId`, `amount`
   - Release cadence: weekly
   - Kind: Apache Camel route (camel-kafka + Apicurio Avro deserializer)

2. **billing** (team-billing)
   - Reader schema: **UNKNOWN** ⚠️
   - Required fields: **UNKNOWN** ⚠️
   - Release cadence: **UNKNOWN** ⚠️
   - Kind: Plain Kafka consumer (Apicurio Avro deserializer)

**Other constraints:**

- Topic retention and replay requirements: **NOT DOCUMENTED** ⚠️
- Old events must stay readable: **UNKNOWN** (depends on retention/replay requirements) ⚠️

## Required compatibility direction and why

**Configured rule:** BACKWARD

**Actual requirement depends on release order:**

- If all consumers upgrade **before** producer deploys v2 → BACKWARD sufficient
- If producer deploys **before** any consumer upgrades (independent releases, lagging consumers) → FORWARD required
- If replay of old events by new consumers while old consumers still run → FULL required

**Since billing's release cadence is unknown, the required direction cannot be determined.**

However, even under BACKWARD-only assumption (consumers upgrade first), the change fails consumer contract validation (see Evidence below).

## Evidence

### Registry compatibility checks

| Check | Rule | Result | Detail |
|-------|------|--------|--------|
| Registry dry-run | BACKWARD | ✅ COMPATIBLE | Schema evolution rules satisfied |
| Registry dry-run | FORWARD | ❌ INCOMPATIBLE | `reader type: STRING not compatible with writer type: NULL at /fields/1/type/0` |
| Registry dry-run | FULL | ❌ INCOMPATIBLE | Same as FORWARD: old readers cannot read null values |

**Interpretation:** The schema change is backward compatible at the schema level but forward incompatible. Old readers (v1) cannot decode events where `customerId` is null.

### Client read matrix

Executed via `fixture/read-matrix` with Avro 1.12.0 using schema resolution (writer schema → reader schema) and consumer contract validation.

| Writer | Consumer | Reader | Result | Detail |
|--------|----------|--------|--------|--------|
| v1 | order-router | v1* | ✅ PASS | decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v1 | order-router | v2 | ✅ PASS | decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v1 | billing | v1 | ⚠️ UNVERIFIED | decoded 2 samples; consumer contract unknown |
| v1 | billing | v2 | ⚠️ UNVERIFIED | decoded 2 samples; consumer contract unknown |
| v2 | order-router | v1* | ❌ FAIL | sample #2 not decodable: Found null, expecting string |
| v2 | order-router | v2 | ❌ FAIL | sample #2: required field 'customerId' is null |
| v2 | billing | v1 | ❌ FAIL | sample #2 not decodable: Found null, expecting string |
| v2 | billing | v2 | ⚠️ UNVERIFIED | decoded 2 samples; consumer contract unknown |

`*` = reader schema the consumer currently runs

**Interpretation:**

1. **order-router with v1 reader (current state):** Cannot decode v2 events with null customerId → Forward incompatible
2. **order-router with v2 reader (after upgrade):** Decodes successfully but **contract violation** — the consumer requires customerId to be non-null, but v2 events with guest checkouts have null customerId
3. **billing:** All combinations with unknown contract are UNVERIFIED; v1 reader fails on v2 events (same forward incompatibility as order-router)

### Critical finding: Business logic conflict

**order-router requires `customerId` to be non-null** (per its contract) but the business requirement is to support guest checkouts where `customerId` will be null. Even if schemas are compatible, the consumer will fail when processing guest checkout events.

This is not a schema compatibility issue — it's a fundamental mismatch between the business requirement and the consumer's contract.

## Release sequence

**Cannot be determined** due to missing information. No safe release sequence exists until:

1. The billing consumer's contract and release cadence are known
2. The replay requirements are documented
3. The business logic conflict with order-router is resolved

## Not verified / limitations

1. **billing consumer:** Reader schema version, required fields, and release cadence are completely unknown → 4 of 8 read matrix cells are UNVERIFIED
2. **Replay requirements:** Whether old events must remain readable by new consumers is not documented → cannot determine if FULL or BACKWARD_TRANSITIVE compatibility is required
3. **order-router business logic:** The test verifies that the consumer's contract (non-null customerId) is violated, but does not verify what the consumer's runtime behavior will be (fail silently, log error, crash, dead-letter, etc.)
4. **Edge cases not tested:** 
   - Very long strings for customerId (boundary values)
   - Empty string customerId
   - Special characters in customerId
5. **No integration test:** Tests use schema resolution only; did not verify actual Kafka producer/consumer with Apicurio Registry SerDe in a running environment

## Questions for owners

### team-billing (billing consumer)

1. What is your current deployment/release cadence for the billing service?
2. What version of the OrderCreated schema are you currently using as your reader schema?
3. Which fields from OrderCreated events does your service depend on? Specifically:
   - Do you require `customerId` to be present and non-null?
   - If `customerId` is null, what should happen (skip processing, use default value, fail)?
4. Do you ever replay OrderCreated events from the beginning of the topic or from old offsets?

### team-fulfilment (order-router consumer)

1. The business requirement is to support guest checkouts where `customerId` will be null, but your consumer contract requires `customerId` to be non-null. How should order-router handle orders with no customer?
   - Should it skip/filter guest checkout orders?
   - Should it use a sentinel value (e.g., "GUEST") instead of null?
   - Should it process them differently?
2. What happens when order-router encounters a null `customerId` today? (graceful degradation, error logging, crash, dead-letter?)

### order-service (producer, your team)

1. What is the retention period for the `orders.order-created` topic?
2. Are there any consumers that replay events from the beginning or from old offsets?
3. What is the planned release timeline for the guest checkout feature?
4. Given the identified conflicts, would it be acceptable to use a sentinel value (e.g., `customerId: "GUEST"`) instead of null to avoid breaking existing consumers?

## Recommended path forward

**Do not proceed with the proposed schema change.** Instead:

1. **Gather the missing information** listed above from the consumer owners
2. **Resolve the business logic conflict** with order-router — decide whether:
   - Guest orders should be filtered out before reaching order-router
   - order-router should be updated to handle null customerId (requires code change + deployment before producer ships v2)
   - Use a sentinel value instead of null (e.g., `"GUEST"`, `"ANONYMOUS"`, or an empty string)
3. **Consider a multi-phase rollout** (expand → migrate → contract):
   - **Phase 1:** Add a new optional field `guestCheckout: boolean` to indicate guest orders while keeping `customerId` required with a sentinel value
   - **Phase 2:** Update all consumers to use the new field
   - **Phase 3:** Make `customerId` nullable in a later release (re-verify compatibility)

Alternatively, if null `customerId` is essential, use a **new topic** for guest orders with a schema designed for that use case, allowing existing consumers to continue unchanged.
