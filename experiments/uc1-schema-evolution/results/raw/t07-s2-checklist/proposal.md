# Change Proposal: Rename `currency` to `currencyCode`

## Decision: Request changes

## Change summary

The proposed v2 schema removes the `currency` field and adds a new `currencyCode` field with a default value of `"EUR"`. This is a field rename to comply with data-standards group guidance.

## Constraints (with source for each)

| Constraint | Value | Source |
|------------|-------|--------|
| Topic | `orders.order-created` | `fixture/consumers.json` |
| Registry group | `orders-t07` | `fixture/consumers.json` |
| Registry artifact | `orders.order-created-value` | `fixture/consumers.json` |
| Artifact type | AVRO | `fixture/consumers.json` |
| Configured compatibility rule | BACKWARD | `fixture/consumers.json` |
| Producer | order-service, currently v1, wants to ship next week | `fixture/consumers.json`, task description |
| Consumer 1 | order-router (team-fulfilment) | `fixture/consumers.json` |
| - Release cadence | weekly | `fixture/consumers.json` |
| - Current reader schema | v1 | `fixture/consumers.json` |
| - Required fields | orderId, customerId, amount | `fixture/consumers.json` |
| Consumer 2 | billing (team-billing) | `fixture/consumers.json` |
| - Release cadence | monthly | `fixture/consumers.json` |
| - Current reader schema | v1 | `fixture/consumers.json` |
| - Required fields | orderId, amount, **currency** | `fixture/consumers.json` |
| Retention/replay | No explicit requirements found | Searched workspace |
| Serde library | Apicurio Avro deserializer | `fixture/consumers.json` |

## Required compatibility direction and why

**FORWARD compatibility is required**, but the configured rule is BACKWARD.

**Why FORWARD is needed:**
- The producer (order-service) will upgrade to v2 next week, emitting events with `currencyCode` but no `currency` field
- Both consumers are currently on v1 reader schemas and will remain so until they upgrade:
  - order-router: weekly releases, could upgrade soon
  - billing: **monthly releases**, will lag significantly behind the producer
- During this lag period, **old readers (v1) must be able to read new data (v2)** → this is FORWARD compatibility
- The configured BACKWARD rule only ensures new readers can read old data, which doesn't protect this scenario

**Critical gap:** The billing consumer with monthly releases will be unable to process new events for potentially weeks after the producer upgrade.

## Evidence

| Check | Rule/combination | Result | Detail |
|-------|------------------|--------|--------|
| Registry | BACKWARD | ✅ COMPATIBLE | New readers (v2) can read old data (v1). The `currencyCode` field has a default value. |
| Registry | FORWARD | ❌ INCOMPATIBLE | Old readers (v1) cannot read new data (v2). The `currency` field at /fields/3 is removed. |
| Registry | FULL | ❌ INCOMPATIBLE | Not both backward and forward compatible. |
| Read-matrix | v1 writer → order-router v1* | ✅ PASS | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| Read-matrix | v1 writer → order-router v2 | ✅ PASS | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| Read-matrix | v1 writer → billing v1* | ✅ PASS | Decoded 2 samples; contract [orderId, amount, currency] satisfied |
| Read-matrix | v1 writer → billing v2 | ❌ FAIL | Required field 'currency' absent from v2 reader schema |
| Read-matrix | v2 writer → order-router v1* | ❌ FAIL | Sample #1 not decodable: missing required field currency |
| Read-matrix | v2 writer → order-router v2 | ✅ PASS | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| Read-matrix | v2 writer → billing v1* | ❌ FAIL | Sample #1 not decodable: missing required field currency |
| Read-matrix | v2 writer → billing v2 | ❌ FAIL | Required field 'currency' absent from v2 reader schema |

*\* = current reader schema version*

**Critical failures:**
- **v2 writer → billing v1***: When the producer emits v2 events, the billing consumer (still on v1 reader, requires `currency` field) cannot decode them. This will break billing processing.
- **v2 writer → order-router v1***: Similarly fails for order-router until it upgrades.

## Release sequence

**The proposed change cannot be safely shipped in a single release.** 

Attempting to ship v2 producer next week will immediately break both consumers:
1. order-service upgrades to v2, starts emitting events with `currencyCode` but no `currency`
2. billing (v1 reader) and order-router (v1 reader) fail to decode these events
3. billing is especially at risk with monthly releases—it could be broken for weeks

## Recommended alternative: Expand → Migrate → Contract

**Phase 1 (v2-safe): Expand**
- Add `currencyCode` field **alongside** existing `currency` field (both present, both populated with same value)
- Ship producer first: emits both fields
- This is FULL compatible: old readers use `currency`, new readers can start using `currencyCode`

**Phase 2: Migrate consumers**
- order-router upgrades to read `currencyCode` (can happen within ~1 week)
- billing upgrades to read `currencyCode` (requires monthly release cycle)
- Wait until all consumers confirm they no longer read `currency`

**Phase 3 (v3): Contract**
- Remove the deprecated `currency` field
- Ship producer
- This is BACKWARD compatible at that point (new readers already using `currencyCode`, no old readers remain)

## Not verified / limitations

1. **Topic retention period**: Unknown. If retention is long and new consumers might start reading from earliest offset, they would need to handle events from all schema versions in retention.

2. **Backward compatibility after consumer migration**: The read-matrix shows that if billing were to upgrade to v2 reader schema, it would fail to read both v1 and v2 events because v2 schema doesn't include `currency` in the reader schema. This means the expand→migrate→contract approach is essential—we cannot upgrade consumers to a v2 schema that removes `currency`.

3. **Other consumers**: Only order-router and billing are listed in `consumers.json`. If there are undeclared consumers, they were not verified.

4. **Semantic equivalence**: Not verified that `currency` and `currencyCode` are semantically identical in all cases. Assuming ISO 4217 codes, but different formats (e.g., "EUR" vs "Euro") would break consumers.

5. **Producer-side population logic**: Not verified that the producer can correctly populate both `currency` and `currencyCode` with identical values during the expand phase.

## Questions for owners

**For team-billing:**
1. Can you upgrade billing to use `currencyCode` in your next monthly release? This is required before we can proceed with the migration.
2. Does your service have any logic that depends on the field name "currency" specifically, or can it adapt to reading "currencyCode"?
3. Are there any other services or jobs (batch processors, analytics) not listed in consumers.json that read from this topic and might depend on the `currency` field?

**For team-fulfilment:**
1. Can order-router be upgraded within the next 1-2 weeks to prepare for the migration?
