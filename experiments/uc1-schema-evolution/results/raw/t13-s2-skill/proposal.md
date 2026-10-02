# Change Proposal: Rename `currency` to `currencyCode` in OrderCreated Schema

## Decision: REQUEST CHANGES

This schema change **cannot be shipped safely** in its current form. The renaming of `currency` to `currencyCode` breaks compatibility with existing consumers, despite passing the Registry's BACKWARD compatibility check.

## Critical Issues

### 1. Consumer Contract Violation
The `billing` consumer (team-billing, monthly release cadence) explicitly requires the `currency` field in its contract. The v2 schema removes this field entirely, replacing it with `currencyCode`. This breaks the billing consumer's contract regardless of which reader schema version it runs.

### 2. Schema Resolution Failures
When consumers running v1 reader schema attempt to read v2 events, Avro schema resolution fails because:
- The v1 schema defines `currency` as a required field (no default value)
- The v2 schema does not provide this field
- Avro cannot satisfy the requirement

## Evidence Gathered

### Registry Compatibility Check
```
✓ BACKWARD COMPATIBLE (registry-check.sh)
```

**Why this passed**: The new `currencyCode` field has a default value (`"EUR"`), so from a pure schema perspective, old readers can read new data by using the default.

**Why this is insufficient**: Registry compatibility rules only verify schema-level compatibility, not consumer contract requirements.

### Read Matrix Verification

All 8 writer/reader/consumer combinations were tested:

| Writer | Consumer | Reader | Result | Details |
|--------|----------|--------|--------|---------|
| v1 | order-router | v1* | ✓ PASS | Contract satisfied: [orderId, customerId, amount] |
| v1 | order-router | v2 | ✓ PASS | Contract satisfied: [orderId, customerId, amount] |
| v1 | billing | v1* | ✓ PASS | Contract satisfied: [orderId, amount, currency] |
| **v1** | **billing** | **v2** | **✗ FAIL** | **Required field 'currency' absent from reader schema** |
| **v2** | **order-router** | **v1*** | **✗ FAIL** | **Not decodable: missing required field currency** |
| v2 | order-router | v2 | ✓ PASS | Contract satisfied: [orderId, customerId, amount] |
| **v2** | **billing** | **v1*** | **✗ FAIL** | **Not decodable: missing required field currency** |
| **v2** | **billing** | **v2** | **✗ FAIL** | **Required field 'currency' absent from reader schema** |

**Result**: 4 failures, 0 unverified

(*) = current reader schema per inventory

## Release Sequence

**N/A** - This change cannot proceed as-is. No safe release sequence exists.

## Recommended Path Forward

To ship this change safely, use a **multi-phase migration**:

### Phase 1: Add the new field without removing the old one
```json
{
  "fields": [
    {"name": "orderId", "type": "string"},
    {"name": "customerId", "type": "string"},
    {"name": "amount", "type": "double"},
    {"name": "currency", "type": "string"},
    {"name": "currencyCode", "type": "string", "default": "EUR"},
    {"name": "createdAt", "type": {"type": "long", "logicalType": "timestamp-millis"}}
  ]
}
```

**Release sequence**:
1. Ship producer update (populate both fields)
2. Update all consumers to read from `currencyCode` instead of `currency`
3. Wait for all consumers to deploy (especially billing, which releases monthly)

### Phase 2: Remove the deprecated field
After all consumers have migrated:
```json
{
  "fields": [
    {"name": "orderId", "type": "string"},
    {"name": "customerId", "type": "string"},
    {"name": "amount", "type": "double"},
    {"name": "currencyCode", "type": "string"},
    {"name": "createdAt", "type": {"type": "long", "logicalType": "timestamp-millis"}}
  ]
}
```

**Release sequence**:
1. Ship schema v3 (removing `currency`)
2. Producer can ship immediately (already only populating `currencyCode`)

## Known Limitations

1. **Registry compatibility checks are necessary but not sufficient**: They verify schema-level compatibility but do not validate consumer contracts. Consumer-level verification (read-matrix) is essential for distributed event-driven systems.

2. **Test coverage**: Verification used 2 sample events per schema version. Real-world data may have additional edge cases not covered by these samples.

3. **Declared consumers only**: Verification only covered the 2 consumers declared in `consumers.json` (order-router and billing). Undeclared consumers may exist and could also be affected.

4. **Release timing risk**: The billing consumer has a monthly release cadence. Any breaking change requires coordination with their release schedule, potentially delaying the full migration by weeks.

5. **Runtime validation**: The read-matrix tool verifies schema compatibility and required field presence, but does not validate business logic or data semantics (e.g., whether "EUR" default values are appropriate for all existing records).
