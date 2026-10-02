# Change Proposal: OrderCreated v2 Schema (currency → currencyCode)

## Decision: REQUEST CHANGES ❌

**This change cannot be shipped as proposed.** The field rename breaks compatibility with existing consumers and will cause production failures.

---

## Critical Issue

The `billing` consumer (team-billing, monthly release cadence) explicitly requires the `currency` field in its contract. The v2 schema removes this field entirely and replaces it with `currencyCode`. This breaks both:

1. **Current production state**: Billing v1 readers cannot decode v2 events (missing required field `currency`)
2. **Post-upgrade state**: Even after billing upgrades to v2, it still cannot read v2 events because the v2 reader schema doesn't contain the `currency` field that billing's application code requires

---

## Evidence Gathered

### 1. Registry Compatibility Check

```bash
$ ./fixture/scripts/registry-check.sh check scenarios/s2-break-contract/order-created-v2.avsc
COMPATIBLE   rule=BACKWARD candidate=scenarios/s2-break-contract/order-created-v2.avsc
```

**Result**: PASS with BACKWARD rule ✓  
**Limitation**: BACKWARD only verifies "can v2 readers read v1 data?" It does NOT verify "can v1 readers read v2 data?"

```bash
$ ./fixture/scripts/registry-check.sh check scenarios/s2-break-contract/order-created-v2.avsc FORWARD
INCOMPATIBLE rule=FORWARD candidate=scenarios/s2-break-contract/order-created-v2.avsc (HTTP 400)
Incompatible artifact: orders.order-created-value [AVRO]
  - currency [/fields/3]
```

**Result**: FAIL with FORWARD rule ❌  
**Reason**: Old readers cannot read new data (missing `currency` field)

```bash
$ ./fixture/scripts/registry-check.sh check scenarios/s2-break-contract/order-created-v2.avsc FULL
INCOMPATIBLE rule=FULL candidate=scenarios/s2-break-contract/order-created-v2.avsc (HTTP 400)
Incompatible artifact: orders.order-created-value [AVRO]
  - currency [/fields/3]
```

**Result**: FAIL with FULL rule ❌

### 2. Read Matrix Results

Tested all 8 writer/reader combinations (2 writer schemas × 2 consumers × 2 reader schemas each):

| Writer | Consumer     | Reader | Result | Detail |
|--------|--------------|--------|--------|--------|
| v1     | order-router | v1*    | ✓ PASS | decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v1     | order-router | v2     | ✓ PASS | decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v1     | billing      | v1*    | ✓ PASS | decoded 2 samples; contract [orderId, amount, currency] satisfied |
| v1     | billing      | v2     | ❌ FAIL | required field 'currency' absent from reader schema |
| v2     | order-router | v1*    | ❌ FAIL | sample #1 not decodable: missing required field currency |
| v2     | order-router | v2     | ✓ PASS | decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v2     | billing      | v1*    | ❌ FAIL | sample #1 not decodable: missing required field currency |
| v2     | billing      | v2     | ❌ FAIL | required field 'currency' absent from reader schema |

**Summary**: 4 failed, 0 unverified  
(*) = current production reader schema

### Critical Failures Explained

1. **v2 → order-router v1*** (current prod): order-router is currently running v1 reader. When order-service starts producing v2 events, order-router will fail to decode them because v1 schema requires `currency` field.

2. **v2 → billing v1*** (current prod): billing is currently running v1 reader and requires `currency` field. Will fail to decode v2 events.

3. **v1 → billing v2**: If billing upgrades to v2 reader before the producer ships v2, it can't read the old v1 events in the topic because the v2 reader schema doesn't have the `currency` field that billing's code requires.

4. **v2 → billing v2**: Even after billing upgrades, it still can't read v2 events because the application requires `currency` field which doesn't exist in the v2 reader schema.

---

## Release Sequence Analysis

**Cannot be released in any sequence** given current schema. The fundamental issue is:

- The `billing` consumer's application code requires `currency` field
- The v2 schema removes `currency` entirely
- No release ordering of producer vs consumers solves this

Attempted sequences would fail:
- **Producer first**: Breaks all consumers currently on v1 readers (both order-router and billing)
- **Consumers first**: Billing can't upgrade to v2 because v2 reader doesn't have `currency` field it requires
- **Simultaneous**: Still breaks because billing v2 reader doesn't have `currency`

---

## Recommended Solution

To safely ship this change, use a **multi-phase migration**:

### Phase 1: Dual-write (v1.1 schema)
Add `currencyCode` alongside existing `currency` field:

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

**Release sequence:**
1. Deploy v1.1 schema to registry
2. Deploy order-service to write both fields (populate `currencyCode` from `currency`)
3. All consumers can now read events (both old v1 and new v1.1)

### Phase 2: Consumer migration
1. Update billing service to read from `currencyCode` instead of `currency`
2. Update billing's required fields contract to `["orderId", "amount", "currencyCode"]`
3. Deploy billing service
4. Verify billing reads `currencyCode` successfully in production

### Phase 3: Remove old field (v2 schema - months later)
After confirming ALL consumers use `currencyCode`:
1. Deploy proposed v2 schema (removes `currency`)
2. Deploy order-service to write only `currencyCode`

**Estimated timeline**: 2-3 months (accounting for billing's monthly release cadence + verification period)

---

## Known Limitations of Verification

1. **Sample data coverage**: Read-matrix tested only 2 sample events per schema version. Production edge cases (null handling, extreme values, missing optional fields) not verified.

2. **Runtime behavior**: Tests verify schema compatibility and required fields, but don't verify application logic that processes the data.

3. **Consumer code review**: Did not inspect billing or order-router source code. Relied on declared `requiredFields` in consumers.json. Actual code may have additional implicit dependencies on `currency` field.

4. **Deployment timing**: Tests assume atomic schema changes. Real deployments have rollout windows where mixed versions coexist.

5. **Backward compatibility depth**: Only tested one version back (v1 → v2). Did not verify compatibility with older events if they exist in the topic's retention period.

6. **Consumer schema configuration**: Assumed consumers use Apicurio deserializer with schema resolution. Other deserialization paths not verified.

7. **Registry rule accuracy**: The configured BACKWARD rule doesn't protect against this type of breaking change. The topic's compatibility rule should likely be FULL or FORWARD for producer-driven changes.

---

## Verification Matrix

| Writer Schema | Reader Schema | Consumer       | Status | Evidence |
|---------------|---------------|----------------|--------|----------|
| v1            | v1            | order-router   | ✓ PASS | read-matrix |
| v1            | v1            | billing        | ✓ PASS | read-matrix |
| v1            | v2            | order-router   | ✓ PASS | read-matrix |
| v1            | v2            | billing        | ❌ FAIL | read-matrix |
| v2            | v1            | order-router   | ❌ FAIL | read-matrix |
| v2            | v1            | billing        | ❌ FAIL | read-matrix |
| v2            | v2            | order-router   | ✓ PASS | read-matrix |
| v2            | v2            | billing        | ❌ FAIL | read-matrix |

**Tools used:**
- `fixture/scripts/registry-check.sh` (Apicurio Registry compatibility API)
- `fixture/read-matrix` (Avro schema resolution simulation with consumer contracts)
- Registry REST API at http://localhost:8081/apis/registry/v3
