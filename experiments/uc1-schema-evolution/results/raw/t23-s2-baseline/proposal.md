# Change Proposal: OrderCreated Schema v1 → v2

## Decision: REQUEST CHANGES

**The proposed v2 schema cannot be shipped.** The field rename from `currency` to `currencyCode` breaks the billing service's contract and is not backward compatible with existing consumers.

---

## Evidence Gathered

### 1. Registry Compatibility Checks

```
✅ BACKWARD:  COMPATIBLE
❌ FORWARD:   INCOMPATIBLE - "currency at /fields/3"
❌ FULL:      INCOMPATIBLE - "currency at /fields/3"
```

The registry's BACKWARD check passed, but this is **misleading**. Apicurio validates Avro schema compatibility rules (can old schema read new data?), but does not verify consumer contracts (are required fields still present?).

### 2. Consumer Read Matrix Results

Tested all 8 writer/reader combinations (2 writer schemas × 2 consumers × 2 reader schemas):

| Writer | Consumer     | Reader | Result | Detail |
|--------|--------------|--------|--------|--------|
| v1     | order-router | v1*    | ✅ PASS | decoded 2 samples; contract satisfied |
| v1     | order-router | v2     | ✅ PASS | decoded 2 samples; contract satisfied |
| v1     | billing      | v1*    | ✅ PASS | decoded 2 samples; contract satisfied |
| v1     | billing      | v2     | ❌ FAIL | **required field 'currency' absent from reader schema** |
| v2     | order-router | v1*    | ❌ FAIL | **sample #1 not decodable: missing required field currency** |
| v2     | order-router | v2     | ✅ PASS | decoded 2 samples; contract satisfied |
| v2     | billing      | v1*    | ❌ FAIL | **sample #1 not decodable: missing required field currency** |
| v2     | billing      | v2     | ❌ FAIL | **required field 'currency' absent from reader schema** |

**4 failures** identified, blocking both upgrade paths.

---

## Writer/Reader Combinations Verified

### Writers (Producers)
- **v1**: order-service producing with current schema (field: `currency`)
- **v2**: order-service producing with proposed schema (field: `currencyCode`)

### Readers (Consumers)
- **order-router** (team-fulfilment, weekly releases)
  - Reader v1*: current schema (requires: orderId, customerId, amount)
  - Reader v2: upgraded schema
- **billing** (team-billing, monthly releases)
  - Reader v1*: current schema (requires: orderId, amount, **currency**)
  - Reader v2: upgraded schema

*\* = currently deployed version*

### Critical Finding

The **billing** service explicitly requires the `currency` field (per `consumers.json`), which the v2 schema removes. This creates an unresolvable conflict:

1. **If billing stays on v1 reader schema**: Cannot decode v2-written messages (missing required field `currency`)
2. **If billing upgrades to v2 reader schema**: Still fails because the v2 schema doesn't contain the `currency` field the billing service requires in its application logic

---

## Root Cause Analysis

The proposed change is a **field rename**, which in Avro is actually:
1. **Remove** the old field (`currency`)
2. **Add** a new field (`currencyCode` with default "EUR")

While Avro's BACKWARD compatibility rules permit this (new field has default, old field removal is allowed), it violates the **consumer contract**:
- The billing service requires `currency` to be present and non-null
- No amount of schema evolution can satisfy this requirement if the field is removed

---

## Release Sequence

**N/A** - This change cannot be shipped in its current form.

To ship the rename, you must:

1. **Phase 1**: Add `currencyCode` alongside `currency` (both fields present)
   - Producer writes both fields
   - Allows consumers to migrate gradually
   - BACKWARD and FORWARD compatible

2. **Phase 2**: Migrate all consumers to read from `currencyCode`
   - Update billing service to use `currencyCode` instead of `currency`
   - Update `consumers.json` to reflect new requirements
   - Wait for monthly billing release cycle

3. **Phase 3**: Deprecate and eventually remove `currency` field
   - Only after all consumers are updated and verified
   - Requires coordination across all teams

**Estimated timeline**: Minimum 4-6 weeks (accounting for billing's monthly release cadence)

---

## Known Limitations

1. **Registry compatibility checks are insufficient**: Apicurio's BACKWARD rule validates Avro schema compatibility but does not verify consumer contracts. Always use the read-matrix tool to verify actual consumer behavior.

2. **Sample data coverage**: Only 2 sample events per schema version were tested. Edge cases (null values, missing fields, boundary conditions) may reveal additional issues.

3. **Deserialization semantics**: The read-matrix simulates Avro schema resolution but may not capture framework-specific deserialization behavior (e.g., Camel route transformations, custom deserializers).

4. **Deployed vs. declared state**: Verification assumes `consumers.json` accurately reflects production. If deployed consumers differ from declared schemas, additional failures may occur.

5. **No rollback testing**: Did not verify the safety of rolling back from v2 to v1 after partial deployment.

---

## Recommendations

1. **Reject the current v2 schema**
2. **Redesign using the 3-phase approach** outlined above
3. **Update the compatibility rule** from BACKWARD to FULL if you want to prevent similar issues (though this adds constraints on evolution)
4. **Establish a policy** requiring read-matrix verification for all schema changes
5. **Coordinate with team-billing** early, given their monthly release cadence

---

## Verification Commands Used

```bash
# Seed registry with v1
fixture/scripts/registry-check.sh seed

# Check v2 compatibility
fixture/scripts/registry-check.sh check scenarios/s2-break-contract/order-created-v2.avsc
fixture/scripts/registry-check.sh check scenarios/s2-break-contract/order-created-v2.avsc FORWARD
fixture/scripts/registry-check.sh check scenarios/s2-break-contract/order-created-v2.avsc FULL

# Run consumer read matrix
cd fixture/read-matrix && mvn -q clean compile exec:java \
  -Dexec.args="../../fixture/schemas/order-created-v1.avsc \
               ../../scenarios/s2-break-contract/order-created-v2.avsc \
               ../../fixture/samples/order-created-v1.jsonl \
               ../../scenarios/s2-break-contract/order-created-v2.jsonl \
               ../../fixture/consumers.json"
```
