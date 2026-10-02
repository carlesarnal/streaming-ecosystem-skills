# Change Proposal: Add `channel` field to OrderCreated event

## Decision: ACCEPT ✅

The proposed schema change can be shipped safely. The addition of the `channel` field with a default value (`"web"`) is fully compatible with all existing consumers.

## Release Sequence

**Recommended order: Producer first, then consumers (in any order)**

1. **Deploy `order-service` (producer)** with v2 schema
   - Can deploy immediately
   - Old consumers (v1) will ignore the new `channel` field and continue working normally
   
2. **Deploy consumers** (when ready on their cadences)
   - `order-router` (team-fulfilment, weekly cadence) - can upgrade to v2 when convenient
   - `billing` (team-billing, monthly cadence) - can upgrade to v2 when convenient
   - Consumers can upgrade in any order, independently of each other

**Alternative (also safe): Consumers can be upgraded first**
- The schema is FULL compatible, so consumers could upgrade before the producer
- New consumers (v2) reading old events (v1) will use the default value `"web"` for the missing `channel` field
- However, producer-first is more logical since the producer owns the new feature

**No coordination required between deployments** - all services can deploy independently on their normal release schedules.

## Evidence Gathered

### Registry Compatibility Checks

Tested against Apicurio Registry at `http://localhost:8081/apis/registry/v3` with artifact `orders-t09/orders.order-created-value`:

- ✅ **BACKWARD compatibility**: PASS
  - Old readers (v1) can read new data (v2)
  - New `channel` field is optional and will be ignored by v1 consumers
  
- ✅ **FORWARD compatibility**: PASS  
  - New readers (v2) can read old data (v1)
  - Missing `channel` field uses default value `"web"`
  
- ✅ **FULL compatibility**: PASS
  - Both backward and forward compatible
  - Enables independent deployments in any order

### Read Matrix Verification

Tested all writer/reader combinations using fixture data (`order-created-v1.jsonl`, `order-created-v2.jsonl`) with Apache Avro deserializer:

| Writer Schema | Consumer | Reader Schema | Result | Notes |
|---------------|----------|---------------|--------|-------|
| v1 | order-router | v1* | ✅ PASS | Baseline: 2 samples decoded, contract satisfied [orderId, customerId, amount] |
| v1 | order-router | v2 | ✅ PASS | Forward compat: 2 samples decoded, contract satisfied |
| v1 | billing | v1* | ✅ PASS | Baseline: 2 samples decoded, contract satisfied [orderId, amount, currency] |
| v1 | billing | v2 | ✅ PASS | Forward compat: 2 samples decoded, contract satisfied |
| v2 | order-router | v1* | ✅ PASS | Backward compat: 2 samples decoded, contract satisfied |
| v2 | order-router | v2 | ✅ PASS | Both upgraded: 2 samples decoded, contract satisfied |
| v2 | billing | v1* | ✅ PASS | Backward compat: 2 samples decoded, contract satisfied |
| v2 | billing | v2 | ✅ PASS | Both upgraded: 2 samples decoded, contract satisfied |

**Summary: 8/8 combinations passed, 0 failed, 0 unverified**

(\* indicates the current reader schema version deployed by that consumer)

### Consumer Contract Verification

Both consumers' required fields are unaffected by the change:
- **order-router** requires: `orderId`, `customerId`, `amount` - all present in both v1 and v2
- **billing** requires: `orderId`, `amount`, `currency` - all present in both v1 and v2

The new `channel` field is not required by either consumer, so it can be safely added.

## Known Limitations

1. **Sample data coverage**: Only 2 sample records tested per schema version
   - Covered basic cases with different channel values (`"mobile"`, `"web"`)
   - Did not test edge cases like very long channel names, special characters, or unusual values
   - The default value `"web"` was verified to be applied when reading v1 data with v2 schema

2. **Consumer implementation details**: Verification used Apache Avro deserializer behavior
   - Assumes `order-router` (Apache Camel route) and `billing` (plain Kafka consumer) both use standard Apicurio Avro deserializer
   - Did not verify the actual deployed consumer code paths
   - Did not test with the consumers' actual business logic that processes these fields

3. **Registry rule scope**: Tested BACKWARD (configured), FORWARD, and FULL compatibility rules
   - Current rule is BACKWARD per `fixture/consumers.json`
   - All three rules passed, providing high confidence
   - Did not test BACKWARD_TRANSITIVE or FORWARD_TRANSITIVE (multi-version compatibility)

4. **Deployment scenario coverage**: 
   - Verified all 2x2 writer/reader combinations (v1→v1, v1→v2, v2→v1, v2→v2)
   - Did not test rolling deployments or partial rollout scenarios
   - Assumes standard Kafka consumer behavior (no custom deserialization logic)

5. **Field semantics**: 
   - The `channel` field is marked as "informational only" in the schema doc
   - Did not verify that consumers don't have hidden dependencies on specific channel values
   - Assumes default value `"web"` is appropriate for all historical events

Despite these limitations, the change has **high confidence** for safe deployment given:
- Full compatibility across all three modes (BACKWARD, FORWARD, FULL)
- All required consumer contracts preserved
- Standard Avro optional field pattern (new field with default value)
- Successful verification of all critical reader/writer combinations
