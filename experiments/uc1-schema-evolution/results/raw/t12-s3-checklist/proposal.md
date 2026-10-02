# Change Proposal: Allow guest checkouts (nullable customerId)

## Decision: Request changes

The proposed change cannot be shipped as-is. The schema evolution is BACKWARD compatible but NOT FORWARD compatible, and at least one consumer (order-router) requires `customerId` as a non-null field. Additionally, critical information about the billing consumer is missing.

## Change summary

**Current schema (v1)**: `customerId` is a required string field.

**Candidate schema (v2)**: `customerId` is nullable (`["null", "string"]` with `default: null`), allowing guest checkouts where no customer ID exists.

**Topic**: `orders.order-created`  
**Registry artifact**: `orders-t12/orders.order-created-value`

## Constraints (with source for each)

| Constraint | Value | Source |
|------------|-------|--------|
| Registry group/artifact | `orders-t12/orders.order-created-value` | `scenarios/s3-missing-context/consumers.json` |
| Artifact type | AVRO | `consumers.json` |
| Configured compatibility rule | BACKWARD | Registry API `/groups/orders-t12/artifacts/orders.order-created-value/rules/COMPATIBILITY` |
| Producer | order-service, currently on v1 schema | `consumers.json` |
| Consumer: order-router | Apache Camel route (camel-kafka + Apicurio Avro deserializer)<br>Owner: team-fulfilment<br>Release cadence: weekly<br>Current reader schema: v1<br>**Required fields: orderId, customerId, amount** | `consumers.json` |
| Consumer: billing | Kind: Plain Kafka consumer (Apicurio Avro deserializer)<br>Owner: team-billing<br>**Release cadence: UNKNOWN**<br>**Current reader schema: UNKNOWN**<br>**Required fields: UNKNOWN** | `consumers.json` |
| Topic retention/replay requirements | **UNKNOWN** | `consumers.json` notes field |
| Avro library | Apache Avro 1.12.0 | `fixture/read-matrix/pom.xml` |

## Required compatibility direction and why

**The configured BACKWARD rule is insufficient.**

- **BACKWARD compatibility** (configured): New readers must read old data. This is satisfied: v2 readers can read v1 events because `customerId` has a default value.
  
- **FORWARD compatibility** (required but NOT satisfied): Old readers must read new data. This is needed because:
  1. Producer and consumers have independent release cycles (order-router releases weekly; billing's cadence is unknown)
  2. There is no guarantee all consumers will upgrade before the producer ships v2 events
  3. Replay requirements are unknown - if old events must be replayable by new consumers while old readers are still active, both directions are needed

The proposed change is **NOT FORWARD compatible**: v1 readers cannot decode v2 events that contain `null` for `customerId` (type mismatch: STRING vs NULL).

## Evidence

### Registry compatibility checks

| Check | Rule | Result | Detail |
|-------|------|--------|--------|
| Registry dry-run | BACKWARD | **COMPATIBLE** | v2 is backward compatible with v1 |
| Registry dry-run | FORWARD | **INCOMPATIBLE** | `reader type: STRING not compatible with writer type: NULL at /fields/1/type/0` |
| Registry dry-run | FULL | **INCOMPATIBLE** | Same as FORWARD |

### Client read matrix

Tested all writer/reader combinations using Apache Avro 1.12.0 with schema resolution (matching Apicurio Avro deserializer behavior):

| Writer | Consumer | Reader | Result | Detail |
|--------|----------|--------|--------|--------|
| v1 | order-router | v1* | **PASS** | decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v1 | order-router | v2 | **PASS** | decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| **v2** | **order-router** | **v1*** | **FAIL** | sample #2 not decodable: Found null, expecting string |
| **v2** | **order-router** | **v2** | **FAIL** | sample #2: required field 'customerId' is null |
| **v2** | **billing** | **v1** | **FAIL** | sample #2 not decodable: Found null, expecting string |
| v2 | billing | v2 | **UNVERIFIED** | decoded 2 samples; consumer contract unknown |
| v1 | billing | v1 | **UNVERIFIED** | decoded 2 samples; consumer contract unknown |
| v1 | billing | v2 | **UNVERIFIED** | decoded 2 samples; consumer contract unknown |

\* = reader schema the consumer currently runs (per inventory)

**Critical finding**: order-router **requires `customerId` as a non-null field**. Even if it upgrades to v2 reader schema, it will fail when processing guest checkout events (sample #2 with `customerId: null`).

## Release sequence

**No safe release sequence exists for the proposed change** because:

1. If producer ships first → old consumers (v1 readers) cannot decode v2 events with null `customerId` → **BREAKS**
2. If consumers upgrade first → order-router still requires non-null `customerId` even with v2 reader schema → will fail on guest checkout events → **BREAKS**
3. Billing consumer's requirements are unknown → cannot verify safety → **UNVERIFIED**

## Not verified / limitations

1. **Billing consumer contract**: Current reader schema version, required fields, and release cadence are unknown. Cannot verify if it can handle null `customerId` or when it could be upgraded.

2. **Topic retention and replay requirements**: Unknown whether old events must remain readable by new consumers, or if replay across multiple versions is needed. This affects whether TRANSITIVE compatibility variants are required.

3. **Edge case handling**: While client read tests verify that null `customerId` can be decoded, they do not verify that consumer business logic can handle guest checkouts correctly (e.g., routing decisions, billing calculations, audit trails).

4. **Production event characteristics**: Tests used 2 sample events per version. Real production events may have additional edge cases not covered.

## Recommended alternative: Expand-Migrate-Contract pattern

To safely introduce guest checkouts, use a three-phase release:

### Phase 1: Expand (add new field, keep old field required)
```json
{
  "fields": [
    {"name": "orderId", "type": "string"},
    {"name": "customerId", "type": "string"},
    {"name": "customerType", "type": {"type": "enum", "name": "CustomerType", 
                                      "symbols": ["REGISTERED", "GUEST"]}, "default": "REGISTERED"},
    {"name": "amount", "type": "double"},
    {"name": "currency", "type": "string"},
    {"name": "createdAt", "type": {"type": "long", "logicalType": "timestamp-millis"}}
  ]
}
```
- Producer emits `customerType: GUEST` for guest checkouts, uses a sentinel value (e.g., `"GUEST"`) for `customerId`
- This is BACKWARD and FORWARD compatible
- Deploy producer first, then consumers can migrate at their own pace

### Phase 2: Migrate consumers
- Upgrade order-router to use `customerType` field instead of checking `customerId` presence
- Upgrade billing consumer to use `customerType` field (after gathering requirements)
- Verify all consumers are migrated

### Phase 3: Contract (remove old field) - OPTIONAL
- In a future release, could remove `customerId` or make it nullable if business requirements allow
- Requires re-verification at that time

## Questions for owners

### For team-fulfilment (order-router owner):
1. Can order-router's business logic be modified to handle guest checkouts using a `customerType` field instead of requiring a non-null `customerId`?
2. What routing decisions depend on `customerId` today, and how should guest orders be routed?

### For team-billing (billing owner):
1. What is the current reader schema version for the billing consumer?
2. What fields does billing require from `OrderCreated` events?
3. What is the release cadence for the billing service?
4. Can billing handle guest checkouts, and if so, what information is needed (e.g., a flag or enum to distinguish guest vs registered customers)?

### For order-service owner (if different from requestor):
1. What are the topic retention settings for `orders.order-created`?
2. Are there any replay requirements (e.g., reprocessing old events with new consumer versions)?
3. Are there other consumers not listed in the inventory?
