# Change Proposal: OrderCreated v2 Schema Migration

## Decision: REQUEST CHANGES

**The proposed v2 schema change cannot be shipped as-is.** It introduces breaking changes that will cause production failures for both declared consumers.

## Evidence Gathered

### 1. Registry Compatibility Checks

Using `fixture/scripts/registry-check.sh` against Apicurio Registry:

- **BACKWARD**: COMPATIBLE ✓ (schema structure only)
- **FORWARD**: INCOMPATIBLE ✗ (`currency` field removal detected)
- **FULL**: INCOMPATIBLE ✗ (`currency` field removal detected)

The BACKWARD compatibility check passes at the schema level because the new `currencyCode` field has a default value. However, this does not verify that actual v2 data can be read by v1 consumers.

### 2. Consumer Read Matrix Verification

Using `fixture/read-matrix` tool to verify all writer/reader combinations with actual sample data:

```
WRITER   CONSUMER       READER   RESULT      DETAIL
v1       order-router   v1*      PASS        decoded 2 samples; contract satisfied
v1       order-router   v2       PASS        decoded 2 samples; contract satisfied
v1       billing        v1*      PASS        decoded 2 samples; contract satisfied
v1       billing        v2       FAIL        required field 'currency' absent from reader schema
v2       order-router   v1*      FAIL        missing required field currency
v2       order-router   v2       PASS        decoded 2 samples; contract satisfied
v2       billing        v1*      FAIL        missing required field currency
v2       billing        v2       FAIL        required field 'currency' absent from reader schema
```

**Summary: 4 failures out of 8 scenarios**

### 3. Writer/Reader Combinations Verified

All possible combinations were verified:
- **Writer schemas**: v1, v2 (with sample data from `fixture/samples/order-created-v1.jsonl` and `scenarios/s2-break-contract/order-created-v2.jsonl`)
- **Consumers**: order-router (team-fulfilment), billing (team-billing)
- **Reader schemas**: v1 (current state, marked with *), v2 (upgraded state)

### 4. Critical Findings

**Breaking change #1 - Field removal without transition:**
- v2 removes the `currency` field entirely and replaces it with `currencyCode`
- When order-service ships v2 and writes events with only `currencyCode`, both consumers running v1 reader schema will fail immediately
- Error: `"missing required field currency"`

**Breaking change #2 - Consumer contract violation:**
- The billing consumer explicitly declares `currency` as a required field (per `fixture/consumers.json` line 34)
- v2 schema does not include `currency`, making it impossible for billing to satisfy its contract even after upgrading to v2 reader schema
- This is a permanent incompatibility, not just a deployment ordering issue

**Additional risk:**
- billing has a monthly release cadence (vs weekly for order-router)
- A coordinated upgrade requiring billing to deploy first would block the producer change for up to a month

## Release Sequence Analysis

**No safe release sequence exists for the current v2 schema.** The following scenarios all fail:

1. **Producer-first deployment:**
   - order-service deploys v2 → both consumers immediately fail reading new events
   - Impact: Complete outage for order-router and billing

2. **Consumer-first deployment:**
   - Consumers upgrade to v2 reader schema first
   - billing still fails because v2 schema lacks the required `currency` field
   - Impact: billing cannot function on either schema version

3. **Coordinated deployment:**
   - Not feasible due to billing's monthly release cadence
   - Still fails due to contract violation (breaking change #2)

## Known Limitations of Verification

1. **Sample data coverage**: Verified with 2 sample events per schema version. Production edge cases (null values, unusual currency codes) were not tested.

2. **Runtime behavior**: The read-matrix tool simulates Apicurio Avro deserializer behavior but does not test:
   - Actual consumer application logic beyond field presence
   - Performance implications of schema resolution
   - Error handling and retry behavior in production

3. **Consumer contract completeness**: Assumed `requiredFields` in consumers.json is exhaustive. Consumers may have additional runtime requirements not declared in the inventory.

4. **Schema registry behavior**: Tested against the configured BACKWARD rule. Did not verify registry's actual enforcement during production writes or potential registry version differences.

5. **Other topics/consumers**: Only verified the two declared consumers for `orders.order-created`. Did not check for:
   - Undeclared consumers
   - Downstream systems that might be reading from topics written by these consumers
   - Development/staging environments with different schema versions

## Recommended Path Forward

To safely migrate from `currency` to `currencyCode`, a multi-phase approach is required:

**Phase 1 - Additive change (v2-revised):**
- Add `currencyCode` as a new field with default value
- Keep the existing `currency` field
- Producer writes BOTH fields with the same value
- Deploy: producer can ship immediately (backward compatible)

**Phase 2 - Consumer migration:**
- Upgrade order-router to read `currencyCode` instead of `currency`
- Upgrade billing to read `currencyCode` and update its contract in consumers.json
- Deploy: consumers upgrade independently, no coordination needed

**Phase 3 - Cleanup (v3):**
- Remove the deprecated `currency` field from schema
- Producer stops writing the old field
- Deploy: only after all consumers have migrated (verify through monitoring)

This approach ensures zero-downtime migration and respects billing's monthly release cadence.
