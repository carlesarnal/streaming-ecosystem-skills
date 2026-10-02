# Schema Change Proposal: OrderCreated v2 (Guest Checkout)

## Decision: Request changes AND Ask for missing information

This change **cannot be shipped as proposed**. The schema is Registry-compatible under the BACKWARD rule, but violates consumer contracts and lacks critical deployment information.

## Change summary

Making `customerId` nullable (`["null", "string"]` with default `null`) to support guest checkout orders.

- **Current (v1)**: `customerId` is required (`"type": "string"`)
- **Proposed (v2)**: `customerId` is optional (`"type": ["null", "string"], "default": null`)

## Constraints (with source for each)

| Constraint | Value | Source |
|------------|-------|--------|
| Topic | `orders.order-created` | consumers.json |
| Registry group/artifact | `orders-t04` / `orders.order-created-value` | consumers.json |
| Artifact type | AVRO | Registry |
| Configured compatibility rule | BACKWARD | consumers.json |
| Producer current schema | v1 | consumers.json |
| **order-router** consumer | | |
| - Current reader schema | v1 | consumers.json |
| - Required fields | orderId, customerId, amount | consumers.json |
| - Release cadence | weekly | consumers.json |
| - Owner | team-fulfilment | consumers.json |
| **billing** consumer | | |
| - Current reader schema | **unknown** | consumers.json |
| - Required fields | **unknown** | consumers.json |
| - Release cadence | **unknown** | consumers.json |
| - Owner | team-billing | consumers.json |
| Retention/replay requirements | **unknown** | consumers.json notes |
| Serde | Apicurio Avro deserializer | consumers.json |

## Required compatibility direction and why

**Required: FULL or expand-migrate-contract approach**

The configured BACKWARD rule is insufficient:

- **BACKWARD needed**: If consumers upgrade before producer → new readers must handle old data (all customerId present) ✓
- **FORWARD also needed**: If producer ships before all consumers upgrade, OR if old events must be replayed while old readers exist, OR if retention allows old readers to start from beginning → old readers must handle new data (customerId may be null) ✗

Since:
1. Retention/replay requirements are **unknown** (could require reading both old and new events)
2. billing's release cadence is **unknown** (independent releases possible)
3. Even a coordinated release sequence cannot fix the order-router contract violation (see Evidence)

We need either FULL compatibility OR a different evolution strategy.

## Evidence

### Registry compatibility checks

| Check | Rule | Result | Detail |
|-------|------|--------|--------|
| Registry dry-run | BACKWARD | **COMPATIBLE** | New readers (v2) can read old data (v1). Default null applied. |
| Registry dry-run | FORWARD | **INCOMPATIBLE** | Old readers (v1) cannot decode new events with null customerId. Error: `reader type: STRING not compatible with writer type: NULL at /fields/1/type/0` |
| Registry dry-run | FULL | **INCOMPATIBLE** | Same FORWARD failure |

### Client read matrix

Tested with representative events including edge cases (null customerId in v2 sample #2).

| Writer | Consumer | Reader | Result | Detail |
|--------|----------|--------|--------|--------|
| v1 | order-router | v1* | **PASS** | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v1 | order-router | v2 | **PASS** | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| **v2** | **order-router** | **v1*** | **FAIL** | Sample #2 not decodable: Found null, expecting string |
| **v2** | **order-router** | **v2** | **FAIL** | **Sample #2: required field 'customerId' is null** |
| v2 | billing | v1 | **FAIL** | Sample #2 not decodable: Found null, expecting string |
| v2 | billing | v2 | **UNVERIFIED** | Decoded 2 samples; consumer contract unknown |
| v1 | billing | v1 | **UNVERIFIED** | Decoded 2 samples; consumer contract unknown |
| v1 | billing | v2 | **UNVERIFIED** | Decoded 2 samples; consumer contract unknown |

\* = reader schema the consumer currently runs

**Critical failure**: order-router with v2 reader schema still fails because its contract requires `customerId` to be non-null, but v2 events can have `customerId: null` for guest checkouts.

## Release sequence

**No safe release sequence exists for the proposed schema.**

Even the most favorable sequence (all consumers upgrade to v2 before producer ships) fails:
1. ❌ Upgrade order-router to v2 reader → ❌ Still fails when v2 producer emits guest checkout events (null customerId violates contract)
2. ❌ Upgrade billing to v2 reader → Unknown if safe (contract unverified)
3. ❌ Deploy order-service with v2 schema → Breaks order-router regardless of its reader version

## Requested changes

Use **expand → migrate → contract** to avoid breaking consumers:

### Phase 1: Expand (v2)
Add a new optional field `guestCheckout: boolean` while keeping `customerId` required:
```json
{
  "fields": [
    {"name": "orderId", "type": "string"},
    {"name": "customerId", "type": "string"},
    {"name": "guestCheckout", "type": "boolean", "default": false},
    {"name": "amount", "type": "double"},
    {"name": "currency", "type": "string"},
    {"name": "createdAt", "type": {"type": "long", "logicalType": "timestamp-millis"}}
  ]
}
```
- For guest checkouts: set `customerId` to a sentinel like `"GUEST"` and `guestCheckout: true`
- For regular orders: set actual customerId and `guestCheckout: false`
- BACKWARD and FORWARD compatible (new optional field with default)
- order-router continues to work (customerId always present)

### Phase 2: Migrate
1. Deploy order-service v2 (producer)
2. Upgrade order-router to handle `guestCheckout` flag (stop requiring customerId to be a real customer ID)
3. Upgrade billing (after confirming requirements in Questions below)
4. Verify all consumers handle both patterns

### Phase 3: Contract (v3, future)
After all consumers are migrated and validated (weeks/months later):
- Make `customerId` nullable
- Remove `guestCheckout` field (or deprecate)
- Requires new verification cycle

**Alternative**: Create a new topic `orders.order-created-v2` for the breaking change if the migration timeline is too complex.

## Not verified / limitations

1. **billing consumer contract unknown**: Cannot verify if v2 schema is safe
   - Unknown which fields billing requires
   - Unknown if billing can handle null customerId
   - Unknown current reader schema version

2. **Retention/replay requirements unknown**: Cannot determine if FULL compatibility is needed
   - If retention > 0 and new consumers may read from earliest: need FULL compatibility
   - If replay/reprocessing is a requirement: need FULL compatibility
   - Current verification assumes no replay across schema versions

3. **Edge cases not exhaustively tested**:
   - Only tested with 2 sample events per schema version
   - Did not test all possible null/non-null combinations
   - Did not verify behavior with malformed events

4. **Release coordination not verified**:
   - Assumes ability to control deployment order
   - Unknown if traffic can be stopped during migration
   - Unknown rollback requirements

## Questions for owners

### For team-billing (billing consumer owner):

1. **Required fields**: Which fields does billing actually depend on? Specifically:
   - Is `customerId` required, or can it be null/absent?
   - Is `currency` required?
   - Any other field dependencies?

2. **Current state**: What reader schema version is billing currently running (v1 or other)?

3. **Release cadence**: What is billing's typical release cycle? Can releases be coordinated with order-service?

4. **Guest checkout handling**: If customerId becomes nullable, can billing's system handle guest orders? Are there business logic implications?

### For order-service owner (you):

5. **Replay requirements**: 
   - What is the retention period for `orders.order-created`?
   - Are there any replay/reprocessing requirements (e.g., rebuilding read models, backfills)?
   - Can new consumer deployments read from earliest offset?

6. **Coordinated deployment**: Can you guarantee all consumers upgrade before order-service ships v2? If not, FORWARD incompatibility is a blocker.

### For team-fulfilment (order-router owner):

7. **Contract change**: Can order-router be updated to handle guest checkouts (null or sentinel customerId)? What is the impact timeline?

8. **Business logic**: What does order-router do with customerId? Will null values break downstream systems?

---

**Recommendation**: Block v2 deployment until:
1. billing requirements are documented (team-billing)
2. Replay requirements are documented (order-service owner)
3. order-router confirms ability to handle revised contract (team-fulfilment)
4. Implement expand-migrate-contract approach instead of direct nullable change
