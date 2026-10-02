# Change Proposal: Add `channel` field to OrderCreated

## Decision: Accept

The proposed change is safe and can be shipped.

## Change summary

Add a new string field `channel` with default value `"web"` to the `OrderCreated` event schema (v1 → v2). The field is documented as "Sales channel. Informational only."

**Schema diff:**
- **Added:** `channel` (string, default: `"web"`)
- **Unchanged:** All existing fields (orderId, customerId, amount, currency, createdAt)

## Constraints

| Constraint | Value | Source |
|------------|-------|--------|
| **Topic** | `orders.order-created` | fixture/consumers.json |
| **Registry group/artifact** | `orders-t27/orders.order-created-value` | fixture/consumers.json |
| **Artifact type** | AVRO | fixture/consumers.json |
| **Configured compatibility rule** | BACKWARD | fixture/consumers.json, verified via Registry API |
| **Current schema** | v1 (5 fields) | fixture/schemas/order-created-v1.avsc |
| **Candidate schema** | v2 (6 fields, adds channel) | scenarios/s1-add-field/order-created-v2.avsc |
| **Producer** | order-service (currently v1) | fixture/consumers.json |
| **Consumer: order-router** | team-fulfilment, weekly releases, v1 reader, requires [orderId, customerId, amount] | fixture/consumers.json |
| **Consumer: billing** | team-billing, monthly releases, v1 reader, requires [orderId, amount, currency] | fixture/consumers.json |
| **Old event retention** | Unknown (assumed: retained, may be replayed) | Assumption |
| **Serde library** | Apache Avro 1.12.0 with Apicurio deserializer | fixture/read-matrix/pom.xml, consumers.json |

## Required compatibility direction and why

**Required: FORWARD or FULL**

**Why:**
- Consumers release independently with different cadences (weekly vs. monthly)
- If the producer ships first (likely scenario for new feature rollout), old readers (v1) must read new data (v2) → **FORWARD** compatibility required
- The configured BACKWARD rule alone is insufficient for a producer-first release
- Since old events may be retained and replayed, and consumers may read from earliest offset, new readers must also read old data → **BACKWARD** also required
- Combined: **FULL** compatibility needed

**Note:** The configured Registry rule is BACKWARD only, which is less strict than what the release plan requires. The Registry will accept this change, but safety depends on verifying FORWARD compatibility separately.

## Evidence

### Registry Compatibility Checks

| Check | Rule | Result | Detail |
|-------|------|--------|--------|
| Registry dry-run | BACKWARD | ✓ COMPATIBLE | New readers (v2) can read old data (v1) |
| Registry dry-run | FORWARD | ✓ COMPATIBLE | Old readers (v1) can read new data (v2) |
| Registry dry-run | FULL | ✓ COMPATIBLE | Both directions supported |

**Method:** Used `fixture/scripts/registry-check.sh check` with dry-run mode against Apicurio Registry API at http://localhost:8081/apis/registry/v3. No versions were registered.

### Client Read Matrix Tests

| Writer | Consumer | Reader | Result | Detail |
|--------|----------|--------|--------|--------|
| v1 | order-router | v1* | ✓ PASS | decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v1 | order-router | v2 | ✓ PASS | decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v1 | billing | v1* | ✓ PASS | decoded 2 samples; contract [orderId, amount, currency] satisfied |
| v1 | billing | v2 | ✓ PASS | decoded 2 samples; contract [orderId, amount, currency] satisfied |
| v2 | order-router | v1* | ✓ PASS | decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v2 | order-router | v2 | ✓ PASS | decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v2 | billing | v1* | ✓ PASS | decoded 2 samples; contract [orderId, amount, currency] satisfied |
| v2 | billing | v2 | ✓ PASS | decoded 2 samples; contract [orderId, amount, currency] satisfied |

*\* = reader schema the consumer currently runs*

**Summary:** 8/8 combinations passed, 0 failed, 0 unverified

**Method:** Used `fixture/read-matrix` Maven project with Apache Avro 1.12.0. Each test:
1. Encodes sample events with the writer schema
2. Decodes with Avro schema resolution using the reader schema (simulating Apicurio deserializer behavior)
3. Verifies consumer contract: all required fields present and non-null

**Sample coverage:**
- v1 samples: 2 events (existing orders without channel field)
- v2 samples: 2 events (new orders with channel="web" and channel="mobile")

**Critical verified combinations:**
- **v2 writer → v1* reader** (producer ships first): old consumers can decode new events with default value
- **v1 writer → v2 reader** (consumers upgrade first): new consumers can decode old events, channel defaults to "web"

## Release sequence

**Recommended: Producer-first release**

1. **order-service** ships v2 schema (starts producing events with `channel` field)
2. **order-router** upgrades to v2 reader (within 1 week)
3. **billing** upgrades to v2 reader (within 1 month)

**Why producer-first:**
- FORWARD compatibility verified: old consumers (v1 readers) can read new events
- Neither consumer requires the `channel` field, so they function correctly with v1 reader schema during transition
- Allows Product to start collecting channel data immediately
- Lower coordination overhead than consumer-first (which would require coordinating 2 teams before shipping)

**Alternative: Consumer-first release**
Also safe due to BACKWARD compatibility, but requires coordinating both consumer teams before producer ships, delaying feature delivery.

## Not verified / limitations

1. **Old event retention and replay requirements:** Assumed that old events may be retained and replayed by new consumers. If retention is short and replay never occurs, BACKWARD compatibility is not strictly required.

2. **Consumer deployment state during rollout:** Assumed standard rolling deployments. If consumers use blue/green or canary deployments that temporarily run multiple schema versions simultaneously, additional verification may be needed.

3. **Sample event coverage:** Tested with 2 v1 samples and 2 v2 samples. Edge cases like extremely long channel names, special characters, or empty strings were not explicitly tested (though Avro schema validation would catch type mismatches).

4. **Consumer code changes:** Verified schema-level compatibility and required field contracts only. Did not verify that consumer application code correctly handles or ignores the new field (though since neither consumer requires it, impact should be minimal).

5. **Registry rule configuration:** Verified compatibility against multiple rules via dry-run, but the actual configured rule remains BACKWARD. If governance requires updating the rule to FULL for this artifact, that is a separate operational step.

## Questions for owners

None. All required information was available in the fixture files and Registry configuration.
