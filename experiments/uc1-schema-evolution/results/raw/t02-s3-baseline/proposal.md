# Change Proposal: Allow Guest Checkouts (OrderCreated v2)

## Decision: REQUEST CHANGES

The proposed schema change **cannot be shipped** in its current form. While the v2 schema is technically BACKWARD compatible according to Apicurio Registry, it violates existing consumer contracts and lacks critical information needed for safe deployment.

## Critical Issues

### 1. Consumer Contract Violation (order-router)
The `order-router` consumer declares `customerId` as a required field and expects it to be non-null. When v2 events with `customerId: null` are produced:
- **v1 reader**: Fails to decode (schema incompatibility - expects string, finds null)
- **v2 reader**: Decodes successfully but violates contract (required field is null)

This is a **breaking change** for order-router regardless of whether they upgrade their reader schema.

### 2. Missing Information (billing consumer)
The billing consumer has:
- `currentReaderSchema: "unknown"`
- `requiredFields: "unknown"`

Without this information, we cannot verify whether billing can safely consume v2 events. This represents an unquantified risk.

## Evidence Gathered

### Registry Compatibility Check
```
✓ BACKWARD compatible: order-created-v2.avsc passes Apicurio Registry validation
```

The registry check confirms that Avro schema resolution works correctly - consumers using v1 schema can technically decode v2 events (when customerId is non-null).

### Read Matrix Verification

Tested all writer/reader combinations using `fixture/read-matrix` with sample events from both schemas:

| Writer | Consumer     | Reader | Result      | Detail |
|--------|--------------|--------|-------------|--------|
| v1     | order-router | v1*    | PASS        | Current state - working |
| v1     | order-router | v2     | PASS        | Forward upgrade path works |
| v1     | billing      | v1     | UNVERIFIED  | Contract unknown |
| v1     | billing      | v2     | UNVERIFIED  | Contract unknown |
| **v2** | **order-router** | **v1*** | **FAIL** | **sample #2 not decodable: Found null, expecting string** |
| **v2** | **order-router** | **v2**  | **FAIL** | **sample #2: required field 'customerId' is null** |
| **v2** | **billing**      | **v1**  | **FAIL** | **sample #2 not decodable: Found null, expecting string** |
| v2     | billing      | v2     | UNVERIFIED  | Contract unknown |

\* = current reader schema per consumer inventory

**Verified combinations:**
- Writer v1 × Reader v1 (order-router): ✓ PASS
- Writer v1 × Reader v2 (order-router): ✓ PASS  
- Writer v2 × Reader v1 (order-router): ✗ FAIL
- Writer v2 × Reader v2 (order-router): ✗ FAIL (contract violation)
- Writer v2 × billing (any reader): Cannot verify due to missing contract information

**Sample events tested:**
- v1: 2 events with non-null customerId
- v2: 2 events (1 with customerId, 1 with null customerId for guest checkout)

## Required Changes

Before this schema change can be deployed:

### 1. Update order-router Consumer
The `order-router` consumer must be updated to:
- Remove `customerId` from the `requiredFields` list, OR
- Implement business logic to handle null `customerId` (guest checkout routing)

**Owner**: team-fulfilment  
**Release cadence**: weekly

### 2. Gather Billing Consumer Information
Obtain the following from team-billing:
- Current reader schema version
- Required fields list
- Whether billing needs customerId for their operations

This will enable verification of billing's compatibility with the proposed change.

### 3. Define Release Sequence (pending consumer updates)
Once consumer changes are made, the recommended sequence is:

**Option A - Consumer-First (Safest)**
1. Deploy updated order-router (with relaxed customerId requirement)
2. Wait for full rollout (1 week per release cadence)
3. Verify billing compatibility and deploy updates if needed
4. Deploy order-service v2 (start producing guest checkout events)

**Option B - Cannot proceed** without addressing consumer contracts first.

## Known Limitations

1. **Incomplete consumer inventory**: Only order-router's contract is documented. The billing consumer has unknown requirements, preventing full verification.

2. **Replay scenarios not verified**: The consumer inventory notes "Topic retention and replay requirements have not been documented." If consumers replay messages, they would encounter v2 events even if they haven't upgraded, which could cause failures.

3. **Runtime behavior assumptions**: Verification assumes consumers use Apicurio Avro deserializer as documented. Actual runtime behavior may differ if configurations are incorrect or documentation is outdated.

4. **Sample coverage**: Verification used 2 sample events per schema version. Edge cases (e.g., extremely long guest order scenarios, mixed batches) were not tested.

5. **Partial producer ownership**: Analysis assumes order-service is the sole producer of OrderCreated events. If other services produce to this topic, their deployment coordination is not considered.

## Recommendation

**Do not proceed with deployment** until:
1. team-fulfilment updates order-router to handle null customerId
2. team-billing provides their consumer contract details
3. All affected consumers are verified against v2 schema with null customerId samples
4. A coordinated release plan accounts for the 1+ week deployment window
