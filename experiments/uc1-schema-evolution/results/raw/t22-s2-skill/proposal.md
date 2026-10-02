# Change Proposal: Rename `currency` to `currencyCode`

## Decision: REQUEST CHANGES

This change **cannot be shipped as proposed**. The field rename breaks backward compatibility and violates the billing consumer's contract.

## Evidence

### Registry Compatibility Check
```
$ ./fixture/scripts/registry-check.sh check scenarios/s2-break-contract/order-created-v2.avsc
COMPATIBLE   rule=BACKWARD candidate=scenarios/s2-break-contract/order-created-v2.avsc
```

The Apicurio Registry API reports the change as BACKWARD compatible. However, this check does not verify consumer contracts.

### Consumer Read Matrix
```
WRITER   CONSUMER       READER   RESULT      DETAIL
v1       order-router   v1*      PASS        decoded 2 samples; contract [orderId, customerId, amount] satisfied
v1       order-router   v2       PASS        decoded 2 samples; contract [orderId, customerId, amount] satisfied
v1       billing        v1*      PASS        decoded 2 samples; contract [orderId, amount, currency] satisfied
v1       billing        v2       FAIL        required field 'currency' absent from reader schema
v2       order-router   v1*      FAIL        sample #1 not decodable: missing required field currency
v2       order-router   v2       PASS        decoded 2 samples; contract [orderId, customerId, amount] satisfied
v2       billing        v1*      FAIL        sample #1 not decodable: missing required field currency
v2       billing        v2       FAIL        required field 'currency' absent from reader schema
```

**Summary: 4 failed, 0 unverified**

### Verified Writer/Reader Combinations

| Writer | Consumer | Reader Schema | Result | Issue |
|--------|----------|---------------|--------|-------|
| v1 | order-router | v1 (current) | ✅ PASS | - |
| v1 | order-router | v2 | ✅ PASS | - |
| v1 | billing | v1 (current) | ✅ PASS | - |
| v1 | billing | v2 | ❌ FAIL | Field 'currency' absent from v2 reader schema |
| v2 | order-router | v1 (current) | ❌ FAIL | Cannot decode v2 messages (missing 'currency') |
| v2 | order-router | v2 | ✅ PASS | - |
| v2 | billing | v1 (current) | ❌ FAIL | Cannot decode v2 messages (missing 'currency') |
| v2 | billing | v2 | ❌ FAIL | Field 'currency' absent from v2 reader schema |

### Root Cause

The **billing** consumer declares `currency` as a required field in its contract. The proposed v2 schema:
- Removes the `currency` field
- Adds `currencyCode` field with a default value

This creates multiple breaking scenarios:
1. If order-service deploys v2 first, billing cannot read new messages (still expects `currency`)
2. Even if billing upgrades to v2 schema, it cannot fulfill its contract requirement for the `currency` field
3. No release sequence can make this work without changing the billing consumer's code

## Known Limitations

1. **Registry API gap**: The Apicurio Registry BACKWARD compatibility check passed, but it does not validate consumer contracts. The registry only checks Avro schema resolution rules, not application-level field requirements.

2. **Sample coverage**: Only 2 sample messages were verified per schema version. Edge cases with null values or missing optional fields were not tested.

3. **Consumer code not verified**: The read-matrix validates the declared contracts in `consumers.json`, but not the actual consumer application code. The billing team may have additional implicit dependencies on the `currency` field format or semantics.

4. **Transitive consumers**: Only direct consumers declared in the registry inventory were verified. Any undeclared consumers or downstream data pipelines may also break.

## Recommended Path Forward

To rename the field safely, use a **deprecation strategy** instead of removal:

1. **Phase 1**: Add `currencyCode` alongside `currency` (both fields present)
   - Set `currencyCode` default to match `currency` value
   - Producer writes both fields with same value
   - Schema is backward compatible
   
2. **Phase 2**: Coordinate with billing team to update their code
   - Billing switches from reading `currency` to `currencyCode`
   - Update `consumers.json` to reflect new required field
   - Deploy billing consumer

3. **Phase 3**: Mark `currency` as deprecated (keep in schema)
   - Wait for all consumers to migrate
   - Can only remove after all consumers upgraded

4. **Phase 4** (future): Remove `currency` field in next major version
   - Only after verifying zero consumers require it

This approach requires coordination but avoids breaking any consumer.
