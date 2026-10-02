# Change Proposal: OrderCreated Schema v1 → v2

## 1. Decision: REQUEST CHANGES

**This change CANNOT be shipped as proposed.** The renaming of `currency` to `currencyCode` breaks the contract with the `billing` consumer and will cause production failures.

## 2. Release Sequence

Not applicable - no safe release sequence exists for this change as currently designed.

## 3. Evidence Gathered

### Registry Compatibility Check

Tested the proposed v2 schema against Apicurio Registry with different compatibility rules:

- **BACKWARD**: ✅ COMPATIBLE (misleading - see actual read matrix results)
- **FORWARD**: ❌ INCOMPATIBLE - `currency` field removed at `/fields/3`
- **FULL**: ❌ INCOMPATIBLE - `currency` field removed at `/fields/3`

### Read Matrix Verification

Verified all writer/reader combinations using `fixture/scripts/read-matrix.sh`:

| Writer | Consumer | Reader | Result | Detail |
|--------|----------|--------|--------|--------|
| v1 | order-router | v1* | ✅ PASS | Contract satisfied: orderId, customerId, amount |
| v1 | order-router | v2 | ✅ PASS | Contract satisfied: orderId, customerId, amount |
| v1 | billing | v1* | ✅ PASS | Contract satisfied: orderId, amount, currency |
| v1 | billing | v2 | ❌ FAIL | Required field 'currency' absent from reader schema |
| v2 | order-router | v1* | ❌ FAIL | Missing required field 'currency' when decoding |
| v2 | order-router | v2 | ✅ PASS | Contract satisfied: orderId, customerId, amount |
| v2 | billing | v1* | ❌ FAIL | Missing required field 'currency' when decoding |
| v2 | billing | v2 | ❌ FAIL | Required field 'currency' absent from reader schema |

*\* indicates current deployed reader schema*

**Summary**: 4 failed, 0 unverified

### Critical Findings

1. **Billing consumer contract violation**: The `billing` consumer (team-billing) explicitly requires the `currency` field. Removing this field breaks their contract regardless of which schema version they use.

2. **No viable upgrade path**: Even if billing upgrades to v2 reader schema, they still cannot read v2-written data because their required field `currency` is absent from the schema entirely.

3. **Order-router also impacted**: While order-router doesn't list `currency` in their required fields, the v1 reader fails to decode v2-written data due to the missing required field.

4. **Registry check is insufficient**: Apicurio's BACKWARD compatibility check passes because the schema evolution is technically backward compatible (old readers can ignore new fields). However, it doesn't validate that old readers can still access their required fields - which they cannot.

## 4. Known Limitations

### Limitations of Registry Compatibility Checks

- **Does not validate consumer contracts**: The registry BACKWARD check verifies schema evolution rules but does not cross-reference actual consumer requirements from `consumers.json`.
- **Field removal appears safe**: Removing a non-default field appears backward compatible to the registry because old readers can still be constructed, but this doesn't account for runtime field access failures.

### Limitations of Read Matrix Verification

- **Test data scope**: Only verified with 2 sample messages per schema version.
- **Consumer logic not tested**: Only verified deserialization; did not test actual consumer business logic that accesses the `currency` field.
- **No cross-version scenarios**: Did not test scenarios where some events in the topic are v1 and others are v2 (which would occur during a rolling deployment).

## Recommended Path Forward

To safely rename `currency` to `currencyCode`, use a multi-phase approach:

**Phase 1**: Add `currencyCode` while keeping `currency` (both fields present)
- Producer writes both fields with identical values
- Schema has both: `currency` (for compatibility) and `currencyCode` (new standard)
- Deploy producer first

**Phase 2**: Update consumers to use `currencyCode`
- Billing and other consumers migrate to read `currencyCode` 
- Update `consumers.json` to reflect new required fields
- Deploy consumers on their normal cadence (weekly for order-router, monthly for billing)

**Phase 3**: Deprecate and remove `currency` field
- After all consumers are confirmed upgraded (wait at least one billing release cycle)
- Remove `currency` field from schema and producer code
- This removal will be backward compatible because no deployed consumers require it

This approach requires 3 schema versions (v1 → v2-dual → v3) and coordination across 3 release cycles, but ensures zero-downtime migration.
