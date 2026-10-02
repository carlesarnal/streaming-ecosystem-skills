# Change Proposal: Allow Guest Checkouts (Making customerId Nullable)

## Decision: REQUEST CHANGES

**This schema change cannot be shipped safely in its current form.** While the change passes Apicurio Registry's BACKWARD compatibility check, actual verification reveals critical failures that will break existing consumers.

## Problems Identified

1. **order-router will fail** - This consumer requires `customerId` as a non-null field. Even if they upgrade to the v2 schema, their application contract explicitly lists `customerId` as a required field, and the read-matrix confirms their logic rejects null values.

2. **FORWARD incompatibility** - The configured BACKWARD compatibility rule is insufficient. Old consumers with v1 schema cannot deserialize events with null `customerId` values, resulting in "Found null, expecting string" errors.

3. **billing consumer is a black box** - Schema version: unknown, release cadence: unknown, required fields: unknown. Cannot verify safety for this consumer.

4. **Schema compatibility ≠ application compatibility** - The registry's compatibility check only validates that data can be deserialized, not that consumer business logic will accept the values.

## Evidence Gathered

### Registry Compatibility Checks
- **BACKWARD**: ✅ COMPATIBLE (new consumers can read old data)
- **FORWARD**: ❌ INCOMPATIBLE - "reader type: STRING not compatible with writer type: NULL at /fields/1/type/0"
- **FULL**: ❌ INCOMPATIBLE (same FORWARD incompatibility)

### Read Matrix Verification

| Writer Schema | Consumer | Reader Schema | Result | Detail |
|--------------|----------|---------------|--------|---------|
| v1 | order-router | v1* | ✅ PASS | decoded 2 samples; contract satisfied |
| v1 | order-router | v2 | ✅ PASS | decoded 2 samples; contract satisfied |
| v1 | billing | v1 | ⚠️ UNVERIFIED | decoded 2 samples; contract unknown |
| v1 | billing | v2 | ⚠️ UNVERIFIED | decoded 2 samples; contract unknown |
| v2 | order-router | v1* | ❌ FAIL | sample #2 not decodable: Found null, expecting string |
| v2 | order-router | v2 | ❌ FAIL | sample #2: required field 'customerId' is null |
| v2 | billing | v1 | ❌ FAIL | sample #2 not decodable: Found null, expecting string |
| v2 | billing | v2 | ⚠️ UNVERIFIED | decoded 2 samples; contract unknown |

*\* = reader schema the consumer currently runs*

**Summary: 3 failed, 3 unverified**

### Verified Writer/Reader Combinations
- ✅ **v1 writer → v1 readers**: All consumers can successfully consume current production events
- ✅ **v1 writer → v2 readers**: Schema-level upgrade path works (consumers can safely upgrade schema first)
- ❌ **v2 writer → v1 readers**: Breaks ALL consumers still on v1 schema (deserialization failure)
- ❌ **v2 writer → v2 readers**: Breaks order-router even after schema upgrade (application contract violation)
- ⚠️ **v2 writer → billing**: Unknown impact - insufficient information to verify

## Required Changes Before Shipping

### 1. order-router (team-fulfilment) Must Update
- Remove `customerId` from their required fields list
- Update application logic to handle null `customerId` gracefully (guest checkout flow)
- Upgrade to v2 schema
- Deploy and verify in production

### 2. billing (team-billing) Must Provide Information
Required information:
- Current schema version in use
- Required fields for their use case
- Does their billing flow support guest checkouts?
- Release cadence and deployment timeline

After gathering this information:
- If they require `customerId`: same code changes as order-router
- If they don't require `customerId`: only schema upgrade needed
- Must verify with read-matrix after clarification

### 3. Consider Registry Compatibility Rule Change
Current: `BACKWARD` (allows this breaking change to pass)

Recommendation: Change to `FULL` compatibility to catch FORWARD incompatibilities like this. This would prevent producers from shipping schema changes that break existing consumers.

## Safe Release Sequence (After Changes)

**Phase 1: Consumer Updates (Parallel)**
1. order-router deploys code changes + v2 schema upgrade
2. billing deploys any needed changes + schema upgrade
3. Verify both consumers can process v1 events successfully

**Phase 2: Producer Update**
1. order-service deploys v2 schema and starts producing events with nullable `customerId`
2. Monitor both consumers for errors
3. Test guest checkout flow end-to-end

**Critical**: Consumers MUST ship first. Producer shipping first will immediately break consumers.

## Known Limitations of Verification

1. **billing consumer is opaque** - Cannot verify actual impact without knowing their schema version, required fields, and use case
2. **No topic retention information** - Cannot assess replay risk. If topic has long retention and billing replays historical events, they need to handle both schemas
3. **Schema compatibility != runtime safety** - Read-matrix tests deserialization and known contracts, but cannot verify all application-level logic
4. **Unlisted consumers** - Only verifying 2 known consumers. If there are unlisted consumers of this topic, they will break
5. **Test environment only** - Production behavior may differ (load, error handling, monitoring)

## Recommendation

**Do not proceed** until:
1. ✅ order-router confirms they can support null `customerId` and provides deployment timeline
2. ✅ billing provides their requirements and deployment timeline  
3. ✅ All consumers have deployed and verified their updates
4. ✅ Consider changing registry compatibility rule to FULL
5. ✅ Document topic retention and replay requirements

The guest checkout feature is blocked on consumer readiness, not schema design. The v2 schema itself is well-designed (proper null handling with default), but the ecosystem is not ready for this change.
