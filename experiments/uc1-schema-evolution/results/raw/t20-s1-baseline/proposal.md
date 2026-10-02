# Change Proposal: Add `channel` Field to OrderCreated Schema

## Decision

**ACCEPT** — The proposed v2 schema is safe to ship.

## Proposed Change

Add a `channel` field to the `OrderCreated` event schema:
- **Type**: `string`
- **Default value**: `"web"`
- **Purpose**: Track the sales channel for each order (informational only)

## Release Sequence

The change is backward compatible, allowing flexible deployment options:

### Recommended: Consumer-First Deployment

1. **Deploy consumers first** (order-router, billing)
   - Upgrade to v2 reader schema
   - Can still read v1 data from existing producer (default value "web" applied)
   - Ready to consume real channel data when producer upgrades
   
2. **Deploy producer** (order-service)
   - Upgrade to v2 writer schema
   - Begins sending actual channel values
   - Consumers immediately benefit from real data

**Rationale**: This sequence ensures consumers are ready to use the new field as soon as the producer starts sending real channel values. No data loss during rollout.

### Alternative: Producer-First Deployment

Producer can safely deploy first if needed:
- Old consumers (v1 readers) can read new data (v2 writer) — they ignore the `channel` field
- Consumers can upgrade at their own cadence (order-router weekly, billing monthly)
- During the gap, channel data is written but not consumed

**Rationale**: Valid if producer team needs to move faster, but results in a period where channel data exists but isn't used.

## Evidence Gathered

### 1. Registry Compatibility Check

Tested candidate schema against Apicurio Registry compatibility rules:

```
✓ BACKWARD   — New readers can read old data (configured rule)
✓ FORWARD    — Old readers can read new data
✓ FULL       — Both directions work
```

**Result**: The schema passes the configured BACKWARD rule and exceeds it (also FORWARD compatible).

### 2. Read Matrix Verification

Tested all writer/reader combinations using Avro schema resolution:

| Writer | Consumer     | Reader | Result | Detail |
|--------|--------------|--------|--------|--------|
| v1     | order-router | v1*    | PASS   | Contract [orderId, customerId, amount] satisfied |
| v1     | order-router | v2     | PASS   | Contract [orderId, customerId, amount] satisfied |
| v1     | billing      | v1*    | PASS   | Contract [orderId, amount, currency] satisfied |
| v1     | billing      | v2     | PASS   | Contract [orderId, amount, currency] satisfied |
| v2     | order-router | v1*    | PASS   | Contract [orderId, customerId, amount] satisfied |
| v2     | order-router | v2     | PASS   | Contract [orderId, customerId, amount] satisfied |
| v2     | billing      | v1*    | PASS   | Contract [orderId, amount, currency] satisfied |
| v2     | billing      | v2     | PASS   | Contract [orderId, amount, currency] satisfied |

_* = current reader schema per inventory_

**Summary**: 8/8 combinations PASS, 0 failed, 0 unverified

### 3. Consumer Contract Analysis

Verified against declared required fields:

- **order-router** requires: `orderId`, `customerId`, `amount`
  - ✓ None of these are modified
  - ✓ New `channel` field is optional (not required)
  
- **billing** requires: `orderId`, `amount`, `currency`
  - ✓ None of these are modified
  - ✓ New `channel` field is optional (not required)

**Result**: The new field does not impact any consumer contracts.

## Why This Change Is Safe

1. **Default value present**: Old data decoded with v2 reader gets `channel = "web"`
2. **Optional field**: No consumer requires `channel` in their contract
3. **All compatibility modes pass**: BACKWARD, FORWARD, and FULL
4. **All reader scenarios verified**: Both consumers can read both v1 and v2 data with both v1 and v2 schemas
5. **No breaking changes**: All existing fields unchanged, all consumers continue to receive required data

## Known Limitations

### 1. Default Value Accuracy
- Old events (written before producer upgrade) will show `channel = "web"` when read with v2 schema
- This default may not reflect the actual historical channel
- **Mitigation**: Document that channel data is only accurate from producer v2 deployment date forward

### 2. Schema Evolution Beyond v2
- Current verification tested v1 ↔ v2 transitions only
- Future schema versions (v3+) not tested
- **Mitigation**: Re-run verification tools for each subsequent schema change

### 3. Apicurio Deserializer Assumption
- Read-matrix assumes Apicurio Avro deserializer behavior (Avro schema resolution)
- Custom deserializers or different Avro libraries may behave differently
- **Mitigation**: Both consumers use Apicurio Avro deserializer per inventory

### 4. Sample Data Coverage
- Verification used 2 samples per schema version
- Edge cases (very large amounts, unusual currencies, etc.) not explicitly tested
- **Mitigation**: New field is independent of existing fields; Avro type system guarantees string encoding

### 5. Runtime Writer/Reader Version Mix
- Verification tested discrete (v1,v1), (v1,v2), (v2,v1), (v2,v2) combinations
- Did not test rapid version flip-flops or partial rollouts
- **Mitigation**: Kubernetes rolling updates ensure gradual rollout; compatibility verified for all stable states

## Verification Tools Used

1. **fixture/scripts/registry-check.sh**
   - Seeded Apicurio Registry with v1 schema
   - Tested v2 compatibility against BACKWARD, FORWARD, FULL rules
   - Used REST API dry-run mode (no permanent registration)

2. **fixture/scripts/read-matrix.sh**
   - Java-based Avro round-trip testing
   - Encoded samples with writer schema, decoded with reader schema
   - Validated consumer contracts (required fields present and non-null)
   - Tested: v1→v1, v1→v2, v2→v1, v2→v2 for both consumers

3. **Apicurio Registry REST API**
   - Endpoint: http://localhost:8081/apis/registry/v3
   - Artifact: orders-t20/orders.order-created-value
   - Compatibility rule: BACKWARD

## Recommendation

**Proceed with deployment** using the consumer-first sequence:
1. Upgrade order-router and billing to v2 reader schema
2. Verify consumers are processing events normally (no errors, metrics stable)
3. Upgrade order-service to v2 writer schema
4. Monitor channel field population and consumer logs
5. Product team can begin analyzing channel data

**Timeline considerations**:
- order-router: Weekly release cadence (team-fulfilment)
- billing: Monthly release cadence (team-billing)
- Coordinate producer deployment after both consumers are ready, or accept that billing may not see channel data for up to a month if producer deploys immediately after order-router upgrade.
