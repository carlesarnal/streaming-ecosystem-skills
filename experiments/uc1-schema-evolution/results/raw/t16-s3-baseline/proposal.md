# Change Proposal: Allow Guest Checkouts (order-created v2)

## Decision: REQUEST CHANGES

The proposed schema change **cannot be shipped as-is**. The change introduces breaking incompatibility with existing consumers that will cause production failures.

## Evidence Gathered

### 1. Schema Compatibility Analysis

Using `registry-check.sh` against Apicurio Registry with the configured BACKWARD compatibility rule:

```
✓ BACKWARD:  COMPATIBLE   (new readers can read old messages)
✗ FORWARD:   INCOMPATIBLE (old readers cannot read new messages)
✗ FULL:      INCOMPATIBLE (requires both BACKWARD and FORWARD)
```

**Registry error detail:**
```
reader type: STRING not compatible with writer type: NULL at /fields/1/type/0
```

The v2 schema is BACKWARD compatible only, meaning new consumers with v2 schema can read old v1 messages. However, existing consumers with v1 schema cannot read new v2 messages containing null `customerId` values.

### 2. Consumer Read Matrix Results

Using `read-matrix.sh` to verify all writer/reader combinations:

| Writer | Consumer     | Reader Schema | Result     | Detail |
|--------|--------------|---------------|------------|--------|
| v1     | order-router | v1* (current) | PASS       | decoded 2 samples; contract satisfied |
| v1     | order-router | v2            | PASS       | decoded 2 samples; contract satisfied |
| v1     | billing      | v1            | UNVERIFIED | consumer contract unknown |
| v1     | billing      | v2            | UNVERIFIED | consumer contract unknown |
| **v2** | **order-router** | **v1*** | **FAIL** | **sample #2 not decodable: Found null, expecting string** |
| **v2** | **order-router** | **v2**  | **FAIL** | **sample #2: required field 'customerId' is null** |
| **v2** | **billing**      | **v1**  | **FAIL** | **sample #2 not decodable: Found null, expecting string** |
| v2     | billing      | v2            | UNVERIFIED | consumer contract unknown |

\* indicates the reader schema the consumer currently runs in production

**Summary:** 3 failed, 3 unverified

### 3. Writer/Reader Combinations Verified

**Tested combinations:**
- Writer v1 × Reader v1 (order-router): ✓ VERIFIED
- Writer v1 × Reader v2 (order-router): ✓ VERIFIED
- Writer v2 × Reader v1 (order-router): ✓ VERIFIED (FAILED)
- Writer v2 × Reader v2 (order-router): ✓ VERIFIED (FAILED)
- Writer v1 × Reader v1 (billing): ⚠ UNVERIFIED (no contract)
- Writer v1 × Reader v2 (billing): ⚠ UNVERIFIED (no contract)
- Writer v2 × Reader v1 (billing): ✓ VERIFIED (FAILED - decode error)
- Writer v2 × Reader v2 (billing): ⚠ UNVERIFIED (no contract)

**Root cause of failures:**
- `order-router` declares `customerId` as a required field in its contract
- Even with v2 reader schema, the consumer validates that required fields are non-null
- Sample #2 in `order-created-v2.jsonl` contains `"customerId": null` (guest checkout case)

## Known Limitations of Verification

1. **Incomplete consumer inventory:** The `billing` consumer has critical gaps:
   - `currentReaderSchema`: "unknown" (assumed v1 based on read matrix failures)
   - `requiredFields`: "unknown" (cannot verify contract satisfaction)
   - `releaseCadence`: "unknown" (impacts rollout planning)

2. **Missing operational context:**
   - Topic retention policy not documented
   - Replay requirements unknown
   - No information on whether old messages could be replayed after schema deployment

3. **Limited test data:** Only 2 sample events per schema version tested

4. **Unverified runtime behavior:** The read matrix validates Avro schema resolution and contract checks but does not test actual consumer application logic or error handling

## Required Changes

### Option A: Consumer-First Deployment (Recommended)

1. **Update `order-router` contract** to make `customerId` optional:
   - Remove `customerId` from `requiredFields` in consumers.json
   - Update order-router code to handle null `customerId` (guest checkout logic)
   - Deploy order-router v2

2. **Gather billing requirements:**
   - Confirm billing's current schema version
   - Confirm whether billing requires `customerId` field
   - If required, update billing similarly to order-router
   - Deploy billing update if needed

3. **Deploy schema v2 to registry** (no producer changes yet)

4. **Deploy order-service v2** to start producing guest checkout events

**Release sequence:** Consumers first → Schema → Producer

### Option B: Breaking Change with Coordinated Deployment

If backward compatibility cannot be maintained:

1. Deploy all consumer updates simultaneously
2. Deploy producer update
3. Requires downtime or dual-write strategy

**Not recommended** due to operational complexity and risk.

## Missing Information Required

Before proceeding with either option:

1. **billing consumer details:**
   - Current reader schema version
   - Required fields (specifically: does billing require `customerId`?)
   - Release cadence and deployment timeline
   - Contact information for team-billing

2. **Operational requirements:**
   - Topic retention period for `orders.order-created`
   - Whether consumers replay historical messages
   - Monitoring/alerting strategy for schema evolution failures

3. **Business requirements:**
   - Guest checkout launch timeline
   - Acceptable downtime/degradation window
   - Rollback plan if failures occur

## Recommendation

**Request changes** to the deployment plan:

1. Gather missing consumer information (billing)
2. Update consumer contracts and code to handle nullable `customerId`
3. Deploy consumers before deploying the schema/producer
4. Implement monitoring for schema compatibility errors
5. Document the complete rollout sequence with rollback procedures

The schema change itself is technically sound for the guest checkout use case, but the deployment strategy must account for existing consumers that cannot handle null values.
