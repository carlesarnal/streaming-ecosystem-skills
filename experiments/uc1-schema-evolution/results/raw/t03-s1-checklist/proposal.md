# Change Proposal: Add channel field to OrderCreated schema

## Decision: Accept

The proposed schema change is safe to ship. The addition of the `channel` field with a default value is fully compatible in both BACKWARD and FORWARD directions, and all consumer contracts are satisfied across all writer/reader combinations.

## Change summary

Add a new optional `channel` field to the OrderCreated event schema (v1 → v2):
- Field name: `channel`
- Type: `string`
- Default value: `"web"`
- Purpose: Track the sales channel (web, mobile, etc.) for each order

## Constraints

| Constraint | Value | Source |
|------------|-------|--------|
| Topic | `orders.order-created` | fixture/consumers.json |
| Registry group | `orders-t03` | fixture/consumers.json |
| Registry artifact | `orders.order-created-value` | fixture/consumers.json |
| Artifact type | AVRO | fixture/consumers.json |
| Configured compatibility rule | BACKWARD | fixture/consumers.json |
| Current schema version | v1 (5 fields) | fixture/schemas/order-created-v1.avsc |
| Candidate schema version | v2 (6 fields: +channel) | scenarios/s1-add-field/order-created-v2.avsc |
| **Consumers** | | |
| order-router | team-fulfilment, weekly releases, Camel route with Apicurio Avro deserializer, requires: orderId, customerId, amount | fixture/consumers.json |
| billing | team-billing, monthly releases, Kafka consumer with Apicurio Avro deserializer, requires: orderId, amount, currency | fixture/consumers.json |
| Both consumers current reader schema | v1 | fixture/consumers.json |
| Retention/replay requirement | **Unknown - not documented** | (assumption: not required for initial verification) |

## Required compatibility direction and why

**FULL compatibility is needed** because of independent release schedules:

- **BACKWARD** is required if any consumer upgrades before the producer (standard practice for schema-governed systems)
- **FORWARD** is required because the producer can ship independently while consumers lag on their regular cadences:
  - order-router releases weekly
  - billing releases monthly
  - There will be a period where old consumers (v1) read new events (v2)

The configured rule (BACKWARD only) is insufficient for the actual deployment scenario. However, the proposed change satisfies both directions, making it safe for any release order.

## Evidence

| Check | Rule/combination | Result | Detail |
|-------|------------------|--------|--------|
| Registry compatibility | BACKWARD | PASS | Apicurio Registry dry-run check via registry-check.sh |
| Registry compatibility | FORWARD | PASS | Apicurio Registry dry-run check via registry-check.sh |
| Client read: v1 writer → order-router v1 reader | (current state) | PASS | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| Client read: v1 writer → order-router v2 reader | BACKWARD | PASS | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| Client read: v2 writer → order-router v1 reader | FORWARD | PASS | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| Client read: v2 writer → order-router v2 reader | (future state) | PASS | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| Client read: v1 writer → billing v1 reader | (current state) | PASS | Decoded 2 samples; contract [orderId, amount, currency] satisfied |
| Client read: v1 writer → billing v2 reader | BACKWARD | PASS | Decoded 2 samples; contract [orderId, amount, currency] satisfied |
| Client read: v2 writer → billing v1 reader | FORWARD | PASS | Decoded 2 samples; contract [orderId, amount, currency] satisfied |
| Client read: v2 writer → billing v2 reader | (future state) | PASS | Decoded 2 samples; contract [orderId, amount, currency] satisfied |

**Summary**: 0 failed, 0 unverified. All 8 writer/reader combinations passed using the read-matrix test harness with representative sample data.

## Release sequence

**Recommended: Producer first, consumers on regular cadence**

1. Deploy order-service with v2 schema
   - New events will include the `channel` field
   - Existing v1 consumers will ignore the new field (FORWARD compatibility verified)

2. Upgrade order-router (team-fulfilment) on their next weekly release
   - Can now read the `channel` field if needed
   - Continues to satisfy its contract on old v1 events still in topic retention

3. Upgrade billing (team-billing) on their next monthly release
   - Can now read the `channel` field if needed
   - Continues to satisfy its contract on old v1 events still in topic retention

**Alternative: Consumer-first is also safe** due to FULL compatibility, but provides no benefit since neither consumer currently requires the new field.

## Not verified / limitations

1. **Topic retention policy**: Not verified whether old events (v1) must remain readable beyond the lifecycle of current consumers. If new consumers may read from earliest offset, they would use v2 reader schema and have been verified compatible.

2. **Actual production serde library versions**: Verification used the fixture's Apicurio Avro deserializer. Assumed to match production deployments per consumers.json metadata, but actual production versions not confirmed.

3. **Edge cases in channel values**: Test data included "mobile" and "web" values. Other potential values (e.g., "api", "partner", empty string) not tested, but schema does not restrict values so any string is valid.

4. **Transitive compatibility**: Only checked single-hop compatibility (v1 ↔ v2). If more than two schema versions will coexist on the topic during rollout, BACKWARD_TRANSITIVE or FULL_TRANSITIVE should be verified.

5. **Consumer deployment state**: Assumed both consumers are currently running v1 reader schema per inventory. If either has already been updated, the verification matrix still covers all combinations.

## Questions for owners

None. All information needed to make the accept decision was available in the fixture metadata and verification results.

---

**Recommendation**: Proceed with deployment. Register v2 schema and deploy order-service. Notify team-fulfilment and team-billing that the new `channel` field is available for consumption when they next upgrade.
