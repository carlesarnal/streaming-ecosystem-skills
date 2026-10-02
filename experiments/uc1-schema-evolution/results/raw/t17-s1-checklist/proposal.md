## Decision: Accept

The change is safe to ship. Adding the `channel` field with a default value is compatible in all directions, and all writer/reader combinations pass validation.

## Change summary

Add a new `channel` field (type: string, default: "web") to the OrderCreated schema (v1 → v2). The field is informational and not required by any consumer.

## Constraints

| Item | Value | Source |
|------|-------|--------|
| Topic | `orders.order-created` | fixture/consumers.json |
| Registry group | `orders-t17` | fixture/consumers.json |
| Registry artifact | `orders.order-created-value` | fixture/consumers.json |
| Artifact type | AVRO | fixture/consumers.json |
| Configured rule | BACKWARD | Registry API + consumers.json |
| Current schema | v1 (5 fields) | fixture/schemas/order-created-v1.avsc |
| Candidate schema | v2 (adds `channel` with default "web") | scenarios/s1-add-field/order-created-v2.avsc |
| **Consumers** | | |
| order-router | Reader: v1, Cadence: weekly, Owner: team-fulfilment, Requires: [orderId, customerId, amount] | fixture/consumers.json |
| billing | Reader: v1, Cadence: monthly, Owner: team-billing, Requires: [orderId, amount, currency] | fixture/consumers.json |
| Serde library | Apicurio Avro deserializer | fixture/consumers.json |
| Retention policy | **UNKNOWN** | Not documented |
| Replay requirements | **UNKNOWN** | Not documented |

## Required compatibility direction and why

**FULL compatibility is required**, though the configured BACKWARD rule is insufficient for the deployment constraints:

- **billing** has monthly releases → will lag behind producer by up to 30 days
- **order-router** has weekly releases → will lag behind producer by up to 7 days
- If producer (order-service) deploys v2 first → old readers (v1) must read new events (v2) → **FORWARD** compatibility required
- If consumers upgrade to v2 reader first → new readers (v2) must read old events (v1) → **BACKWARD** compatibility required
- No coordinated release mentioned → both deployment orders must be safe → **FULL** compatibility required

The configured BACKWARD rule would accept this change, but would **not** guarantee safety if the producer deploys first before all consumers upgrade.

## Evidence

| Check type | Rule/Combination | Result | Detail |
|------------|------------------|--------|--------|
| Registry compatibility | BACKWARD | **COMPATIBLE** | Apicurio Registry dry-run check |
| Registry compatibility | FORWARD | **COMPATIBLE** | Apicurio Registry dry-run check |
| Registry compatibility | FULL | **COMPATIBLE** | Apicurio Registry dry-run check |
| Client read test | v1 writer → order-router v1 reader* | **PASS** | Decoded 2 samples; contract satisfied |
| Client read test | v1 writer → order-router v2 reader | **PASS** | Decoded 2 samples; contract satisfied |
| Client read test | v2 writer → order-router v1 reader* | **PASS** | Decoded 2 samples; contract satisfied |
| Client read test | v2 writer → order-router v2 reader | **PASS** | Decoded 2 samples; contract satisfied |
| Client read test | v1 writer → billing v1 reader* | **PASS** | Decoded 2 samples; contract satisfied |
| Client read test | v1 writer → billing v2 reader | **PASS** | Decoded 2 samples; contract satisfied |
| Client read test | v2 writer → billing v1 reader* | **PASS** | Decoded 2 samples; contract satisfied |
| Client read test | v2 writer → billing v2 reader | **PASS** | Decoded 2 samples; contract satisfied |

\* = reader schema version the consumer currently runs in production

Summary: **8/8 combinations passed, 0 failed, 0 unverified**

Tool versions:
- Registry compatibility: Apicurio Registry REST API (http://localhost:8081/apis/registry/v3)
- Client read tests: fixture/read-matrix Java test harness with Apicurio Avro serde

## Release sequence

Since FULL compatibility is verified, either deployment order is safe. **Recommended sequence:**

1. **Consumers first** (safer, leverages the configured BACKWARD rule):
   - Deploy order-router with v2 reader schema (can read v1 and v2 events)
   - Deploy billing with v2 reader schema (can read v1 and v2 events)
   - Deploy order-service with v2 writer schema (produces events with `channel` field)

2. **Alternative** (producer first, relies on verified FORWARD compatibility):
   - Deploy order-service with v2 writer schema
   - Existing v1 readers will decode `channel` with default value "web"
   - Deploy order-router and billing with v2 reader schema when ready

The first sequence is recommended because:
- It matches the configured BACKWARD rule, making the Registry a guardrail
- Consumers upgraded early can handle both old and new events
- No risk of producers racing ahead of slow-to-upgrade consumers

## Not verified / limitations

1. **Topic retention policy unknown** → Cannot verify whether old events (v1) must remain readable by future consumers. If retention is long or unlimited, and new consumers might read from the earliest offset, FULL compatibility is required (which is satisfied).

2. **Replay/reprocessing requirements unknown** → Cannot verify whether consumers might need to replay the full topic history with a new reader version. If replay is required, FULL compatibility is required (which is satisfied).

3. **Production data coverage** → Client read tests used 2 sample events per schema version. Edge cases in production data (e.g., unusual `channel` values, maximum field lengths, encoding variations) were not tested.

4. **Serde version specifics unknown** → Exact Apicurio Avro deserializer version not documented. Different versions may have different default-handling behavior, though this is unlikely to affect a simple string field with a default.

5. **New consumer discovery** → Cannot verify whether additional consumers exist beyond `order-router` and `billing`. If undocumented consumers exist and have different requirements or release cadences, the decision may need revision.

## Questions for owners

None required for approval, but recommended for operational completeness:

1. **To team-fulfilment / team-billing**: Are there plans to replay the `orders.order-created` topic from the earliest offset with a new consumer version? If so, the FULL compatibility verified here ensures safety.

2. **To order-service owner**: What is the topic retention policy for `orders.order-created`? If retention is >30 days, ensure billing (monthly release cadence) is upgraded within one release cycle to avoid drift between producer and consumer.
