# Change Proposal: Allow Guest Checkouts (order-created-v2)

## Decision: REQUEST CHANGES + ASK FOR MISSING INFORMATION

**This change CANNOT be shipped in its current form.** Critical blockers have been identified that require resolution before deployment.

---

## Critical Blockers

### 1. Consumer Business Logic Incompatibility

**`order-router` (team-fulfilment)** explicitly requires `customerId` as a non-null field, even when using the v2 reader schema. The read-matrix verification shows:

```
v2 writer → order-router (v2 reader): FAIL
  "sample #2: required field 'customerId' is null"
```

This consumer **cannot process guest checkouts** even after upgrading to v2 schema. The business logic must be updated to handle null `customerId` values before this change can deploy.

### 2. Unknown Consumer Requirements

**`billing` (team-billing)** has the following unknowns documented in `consumers.json`:
- Release cadence: unknown
- Current reader schema version: unknown  
- Required fields: unknown

The read-matrix shows:
```
v2 writer → billing (v2 reader): UNVERIFIED
  "decoded 2 samples; consumer contract unknown"
```

**Cannot verify** if billing can handle null `customerId` values in its business logic.

### 3. Deployment Sequencing Risk

If the v2 schema is deployed with a writer-first sequence (current default), **both consumers will immediately break**:

```
v2 writer → order-router (v1 reader - CURRENT): FAIL
  "sample #2 not decodable: Found null, expecting string"

v2 writer → billing (v1 reader): FAIL  
  "sample #2 not decodable: Found null, expecting string"
```

---

## Required Actions Before Shipping

1. **order-router code changes required**
   - Update business logic to handle null `customerId` (guest checkout flow)
   - Update required fields list in `consumers.json` to reflect this
   - Deploy and verify in production before schema change

2. **billing team consultation required**
   - Determine current reader schema version
   - Determine if billing requires `customerId` (can it handle null?)
   - Document release cadence
   - Update `consumers.json` with findings

3. **Release sequence determination depends on above**
   - If both consumers can handle null after code updates: consumer-first deployment
   - If consumers need code changes: code changes first, then consumer schema upgrades, then writer schema upgrade

4. **Documentation gap**
   - `consumers.json` notes: "Topic retention and replay requirements have not been documented"
   - If topic has retention + replay: old v1 consumers rejoining could receive v2 messages with null `customerId` and fail
   - Need to document: retention policy, replay scenarios, consumer rewind patterns

---

## Release Sequence (Conditional)

**Cannot determine safe release sequence** until blockers are resolved. However, if all blockers are addressed:

**Recommended sequence:**
1. Deploy `order-router` code changes (handle null `customerId`)
2. Deploy `billing` code changes (if required)
3. Upgrade `order-router` to v2 reader schema
4. Upgrade `billing` to v2 reader schema  
5. Upgrade `order-service` (producer) to v2 writer schema
6. Monitor for errors, have rollback plan

**Consumer-first is mandatory** because the schema change is not backward compatible at the runtime level, despite passing the Apicurio BACKWARD rule check.

---

## Evidence Gathered

### Schema Compatibility Verification

**Tool:** `fixture/scripts/registry-check.sh`

**Registry compatibility check (Apicurio BACKWARD rule):**
```bash
CONSUMERS=scenarios/s3-missing-context/consumers.json \
  fixture/scripts/registry-check.sh check \
  scenarios/s3-missing-context/order-created-v2.avsc BACKWARD

Result: COMPATIBLE
```

**Registry compatibility check (Apicurio FULL rule):**
```bash
CONSUMERS=scenarios/s3-missing-context/consumers.json \
  fixture/scripts/registry-check.sh check \
  scenarios/s3-missing-context/order-created-v2.avsc FULL

Result: INCOMPATIBLE
  "reader type: STRING not compatible with writer type: NULL at /fields/1/type/0"
```

**Analysis:** The v2 schema passes BACKWARD compatibility (Avro can provide default values to old readers) but fails FULL compatibility (old writers cannot satisfy new readers expecting nullable types). This indicates the change is a one-way migration.

### Runtime Read Matrix Verification

**Tool:** `fixture/scripts/read-matrix.sh scenarios/s3-missing-context`

**Complete writer/reader verification matrix:**

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

*\* = current reader schema in production (per consumers.json)*

**Summary:** 3 failed, 3 unverified (out of 8 combinations)

### Verified Combinations

**Working combinations:**
- ✅ v1 writer + order-router v1 reader (current production state)
- ✅ v1 writer + order-router v2 reader (safe upgrade path for reader)

**Failing combinations:**
- ❌ v2 writer + order-router v1 reader (schema deserialization failure)
- ❌ v2 writer + order-router v2 reader (business logic contract violation)
- ❌ v2 writer + billing v1 reader (schema deserialization failure)

**Unverified combinations:**
- ⚠️ All billing combinations (contract unknown, cannot verify business logic)

---

## Known Limitations of Verification

1. **Billing consumer contract is unknown**
   - Read-matrix can verify deserialization but not business logic requirements
   - Cannot confirm if billing can process null `customerId` values
   - Cannot verify current production reader schema version
   - Cannot assess deployment coordination given unknown release cadence

2. **Topic retention and replay not documented**
   - If topic has retention > 0 and consumers can rewind/replay
   - Consumers could receive mixed v1/v2 messages in various scenarios
   - Cannot assess risk of consumer restarts, rebalancing, or offset resets
   - No verification of consumer behavior when replaying across schema boundary

3. **Synthetic test environment**
   - Verification uses sample JSONL files, not production message volumes
   - Cannot verify performance impact of union type deserialization
   - Cannot test consumer error handling, dead letter queues, or retry logic
   - Cannot verify monitoring/alerting on null `customerId` values

4. **Schema registry verification is syntactic only**
   - Apicurio BACKWARD check passes (syntactic Avro compatibility)
   - Does not verify semantic/business logic compatibility
   - Read-matrix exposes the semantic incompatibility the registry check misses

5. **No transitive compatibility verification**
   - Only tested v1 ↔ v2 direct transitions
   - If multiple schema versions exist or future v3 is planned: not verified
   - BACKWARD vs BACKWARD_TRANSITIVE implications not assessed

6. **Consumer code not analyzed**
   - Verification relies on documented required fields in `consumers.json`
   - order-router actual code may have additional assumptions about `customerId`
   - billing actual code is completely unknown

7. **No rollback scenario tested**
   - If v2 deploys and must be rolled back to v1
   - Would v1 writer need to handle in-flight v2 consumers?
   - No verification of rollback safety

---

## Recommendations

### Immediate Next Steps

1. **Engage team-billing**
   - Schedule sync to review guest checkout requirements
   - Determine if billing can process null `customerId`
   - Document current schema version and release cadence
   - Update `consumers.json` with findings

2. **Engage team-fulfilment** 
   - Confirm order-router must support guest checkouts
   - Prioritize code changes to handle null `customerId`
   - Update contract in `consumers.json` once code is ready
   - Test guest checkout flow in staging

3. **Document topic configuration**
   - Retention policy for `orders.order-created`
   - Consumer replay patterns and offset management
   - Add to `consumers.json` notes section

### Alternative Approaches to Consider

1. **Separate guest checkout topic**
   - Publish guest orders to `orders.guest-order-created`
   - Allows consumers to opt-in to guest checkout support
   - Avoids breaking existing consumers
   - Downside: topic proliferation, consumer complexity

2. **Phased rollout with feature flag**
   - Deploy v2 schema but keep guest checkout feature disabled
   - Gradually enable guest checkout per consumer readiness
   - Requires producer-side feature flagging
   - Allows safer incremental rollout

3. **Keep customerId non-nullable, use sentinel value**
   - Use special value like `"GUEST"` instead of null
   - Avoids schema compatibility issues
   - All consumers can deserialize
   - Downside: semantics less clear, consumers must handle sentinel

---

## Schema Change Summary

**File:** `scenarios/s3-missing-context/order-created-v2.avsc`

**Changes from v1:**
- `customerId` field type changed from `"string"` to `["null", "string"]`
- Added `default: null` for `customerId` field
- Added doc: `"Null for guest checkouts"`

**Sample v2 events:**
- Event 1: `customerId` = `"c-42"` (existing customer flow)
- Event 2: `customerId` = `null` (guest checkout flow)

**Compatibility:** BACKWARD per Apicurio, but semantically incompatible with current consumer contracts.
