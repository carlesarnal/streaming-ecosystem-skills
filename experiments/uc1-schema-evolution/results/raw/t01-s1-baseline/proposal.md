# Change Proposal: Add `channel` Field to OrderCreated Schema

## Decision: ACCEPT

The proposed schema change (v2) adding a `channel` field can be shipped safely.

## Release Sequence

**Recommended approach: Producer-first deployment**

1. **Immediate**: Deploy `order-service` with v2 schema to production
2. **Optional**: Upgrade consumers (`order-router`, `billing`) to v2 schema at their normal release cadence
   - `order-router` (team-fulfilment): next weekly release
   - `billing` (team-billing): next monthly release

**Rationale**: The change is FULL compatible (both BACKWARD and FORWARD), meaning:
- New producer (v2) can be deployed immediately without consumer coordination
- Existing consumers running v1 reader schema will continue to function correctly when reading v2 data
- Consumers can upgrade to v2 schema independently to gain visibility into the `channel` field
- No cross-team coordination or synchronized deployment is required

**Alternative**: Consumer-first deployment is also safe but adds unnecessary delay given the FULL compatibility.

## Evidence Gathered

### 1. Schema Compatibility Verification (Apicurio Registry)

Tested v2 schema against Registry compatibility rules:

| Rule | Result | Details |
|------|--------|---------|
| BACKWARD | ✅ COMPATIBLE | New schema (v2) can read data written with old schema (v1) |
| FORWARD | ✅ COMPATIBLE | Old schema (v1) can read data written with new schema (v2) |
| FULL | ✅ COMPATIBLE | Both BACKWARD and FORWARD compatibility satisfied |

**Command executed**: `./fixture/scripts/registry-check.sh check scenarios/s1-add-field/order-created-v2.avsc [RULE]`

**Key finding**: The `channel` field with default value `"web"` enables:
- v2 readers to successfully decode v1 data (default is applied when field is absent)
- v1 readers to successfully decode v2 data (unknown fields are ignored by Avro)

### 2. Consumer Read-Matrix Verification

Tested all writer/reader combinations with actual Avro serialization and deserialization:

| Writer Schema | Consumer | Reader Schema | Result | Contract Validation |
|---------------|----------|---------------|--------|-------------------|
| v1 | order-router | v1* (current) | ✅ PASS | [orderId, customerId, amount] satisfied |
| v1 | order-router | v2 | ✅ PASS | [orderId, customerId, amount] satisfied |
| v1 | billing | v1* (current) | ✅ PASS | [orderId, amount, currency] satisfied |
| v1 | billing | v2 | ✅ PASS | [orderId, amount, currency] satisfied |
| v2 | order-router | v1* (current) | ✅ PASS | [orderId, customerId, amount] satisfied |
| v2 | order-router | v2 | ✅ PASS | [orderId, customerId, amount] satisfied |
| v2 | billing | v1* (current) | ✅ PASS | [orderId, amount, currency] satisfied |
| v2 | billing | v2 | ✅ PASS | [orderId, amount, currency] satisfied |

**Summary**: 8/8 combinations passed, 0 failed, 0 unverified

**Command executed**: `./fixture/scripts/read-matrix.sh scenarios/s1-add-field/`

**Critical verification**: Both consumers can successfully:
- Decode v2 data using their current v1 reader schema
- Extract all required fields from v2 data
- Continue operating without any changes

### 3. Writer/Reader Combinations Verified

**Producer (order-service)**:
- v1 writer → v1 readers: ✅ (baseline, currently in production)
- v1 writer → v2 readers: ✅ (consumers can upgrade first)
- v2 writer → v1 readers: ✅ (producer can upgrade first) ← **Critical path**
- v2 writer → v2 readers: ✅ (both upgraded)

**Consumers verified**:
1. **order-router** (Apache Camel route with Apicurio Avro deserializer)
   - Required fields: orderId, customerId, amount
   - Both v1 and v2 reader schemas can extract required fields from both v1 and v2 data
   
2. **billing** (Plain Kafka consumer with Apicurio Avro deserializer)
   - Required fields: orderId, amount, currency
   - Both v1 and v2 reader schemas can extract required fields from both v1 and v2 data

## Known Limitations of Verification

1. **Sample data coverage**: Testing used limited sample data (2 v1 samples, 2 v2 samples). Does not cover all possible edge cases or data variations.

2. **Synthetic testing**: Read-matrix uses `GenericDatumReader` directly rather than testing through actual Apache Camel routes or production Kafka infrastructure. Assumes Apicurio Avro deserializer behavior matches the test implementation.

3. **No runtime validation**: Cannot verify that the producer application code correctly populates the `channel` field with appropriate values ("web", "mobile", etc.) beyond the test samples.

4. **No performance testing**: Impact on serialization/deserialization performance, message size, or throughput has not been measured.

5. **No error handling verification**: Edge cases like null values (despite the default), extremely long channel strings, or unexpected channel values have not been tested.

6. **Limited deployment scenario coverage**: Testing assumes clean schema evolution. Does not cover scenarios like Registry unavailability, schema cache behavior, or network partitions during deployment.

7. **No backward deployment verification**: If rollback is needed, reverting from v2 to v1 producer has not been explicitly tested (though it should work given FORWARD compatibility).

## Schema Change Summary

**Current schema (v1)**: 5 fields
- orderId (string)
- customerId (string)
- amount (double)
- currency (string)
- createdAt (timestamp-millis)

**Proposed schema (v2)**: 6 fields (added 1)
- orderId (string)
- customerId (string)
- amount (double)
- currency (string)
- createdAt (timestamp-millis)
- **channel (string, default: "web", doc: "Sales channel. Informational only.")** ← NEW

**Change type**: Additive (new optional field with default value)

**Semantic impact**: Informational only - no consumer contracts require this field
