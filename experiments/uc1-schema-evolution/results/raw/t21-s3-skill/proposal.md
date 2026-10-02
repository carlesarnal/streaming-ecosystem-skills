# Change Proposal: Allow Guest Checkouts (Make customerId Nullable)

## Decision: Ask for missing information

The change **cannot be safely evaluated** due to critical missing information about consumer contracts, release capabilities, and replay requirements. Additionally, verification reveals that even if all information were available, the current proposal would break the `order-router` consumer's contract.

## Change Summary

**Proposed change:** Make `customerId` field nullable in `OrderCreated` event schema to support guest checkout flows.

- **Current schema (v1):** `customerId` is required (`"type": "string"`)
- **Candidate schema (v2):** `customerId` is nullable (`"type": ["null", "string"], "default": null`)

## Constraints

| Constraint | Value | Source |
|------------|-------|--------|
| Topic | `orders.order-created` | consumers.json |
| Registry group/artifact | `orders-t21/orders.order-created-value` | consumers.json |
| Artifact type | AVRO | Registry API |
| Configured compatibility rule | BACKWARD | Registry API, consumers.json |
| Current schema version | v1 | consumers.json |
| Producer | order-service, currently on v1 | consumers.json |
| Consumer: order-router | team-fulfilment, weekly releases, v1 reader, requires [orderId, customerId, amount] | consumers.json |
| Consumer: billing | team-billing | consumers.json |
| billing reader schema | **UNKNOWN** | consumers.json |
| billing required fields | **UNKNOWN** | consumers.json |
| billing release cadence | **UNKNOWN** | consumers.json |
| Topic retention policy | **NOT DOCUMENTED** | consumers.json notes |
| Replay requirements | **NOT DOCUMENTED** | consumers.json notes |

## Required Compatibility Direction

Given independent release schedules and unknown constraints:

1. **If consumers upgrade before producer:** BACKWARD compatibility required
   - New readers (v2) must read old events (v1 schema, all customerId values present)
   - ✓ This direction passes

2. **If producer ships before all consumers upgrade:** FORWARD compatibility required
   - Old readers (v1) must read new events (v2 schema, null customerId values)
   - ✗ This direction **FAILS**

3. **With unknown replay requirements and unknown billing release cadence:** FULL or FULL_TRANSITIVE may be needed
   - ✗ Both **FAIL** due to FORWARD incompatibility

**The configured BACKWARD rule is insufficient** if:
- Any consumer cannot upgrade before the producer ships
- billing consumer has unknown/slow release cadence (cannot be assumed to upgrade first)
- Old events need to be replayed by new consumers while old consumers are still running

## Evidence

### Registry Compatibility Checks

| Check Type | Rule | Result | Detail |
|------------|------|--------|--------|
| Registry dry-run | BACKWARD | ✓ COMPATIBLE | New readers can read old events with required customerId |
| Registry dry-run | FORWARD | ✗ INCOMPATIBLE | "reader type: STRING not compatible with writer type: NULL at /fields/1/type/0" |
| Registry dry-run | FULL | ✗ INCOMPATIBLE | Same FORWARD failure |

### Consumer Read Matrix

| Writer | Consumer | Reader | Result | Detail |
|--------|----------|--------|--------|--------|
| v1 | order-router | v1 (current) | ✓ PASS | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v1 | order-router | v2 | ✓ PASS | Decoded 2 samples; contract satisfied |
| v2 | order-router | v1 (current) | ✗ FAIL | Sample #2 not decodable: "Found null, expecting string" |
| v2 | order-router | v2 | ✗ **FAIL** | Sample #2: **required field 'customerId' is null** |
| v1 | billing | v1 | ⚠ UNVERIFIED | Decoded 2 samples; consumer contract unknown |
| v1 | billing | v2 | ⚠ UNVERIFIED | Decoded 2 samples; consumer contract unknown |
| v2 | billing | v1 | ✗ FAIL | Sample #2 not decodable: "Found null, expecting string" |
| v2 | billing | v2 | ⚠ UNVERIFIED | Decoded 2 samples; consumer contract unknown |

**Summary:** 3 failed, 3 unverified

## Release Sequence

Cannot be determined due to missing information and contract violations.

Even if all information were available, **the order-router consumer would need its contract changed** before this schema change could ship. The consumer currently requires `customerId` to be present and non-null, which conflicts with guest checkout where `customerId` will be null.

## Not Verified / Limitations

1. **Contract violation:** order-router's business logic requires customerId (listed in requiredFields), but the v2 schema allows null values. The read test shows this contract is violated even with the v2 reader schema.

2. **Unknown consumer state:** billing consumer has unknown reader schema version, unknown required fields, and unknown release cadence - cannot verify any combinations involving this consumer's actual contract.

3. **Unknown replay requirements:** No documentation of whether old events must remain readable, whether new consumers will replay from earliest offset, or what retention period applies.

4. **Serde library versions:** While consumers use Apicurio Avro deserializer, specific library versions were not verified (though unlikely to affect this basic type compatibility issue).

5. **No FORWARD path tested:** Since FORWARD compatibility fails at the Registry level, producer-first deployment is not viable with the current proposal.

## Questions for Owners

### For team-fulfilment (order-router owner):
1. **Can order-router's business logic handle null customerId values for guest checkouts?** 
   - Current contract lists customerId as required
   - If guest orders need different processing logic, does the router need to be updated first?
   - If yes, what timeline for updating the consumer's contract?

### For team-billing (billing owner):
2. **What reader schema version is billing currently running?** (v1 or v2 or other)
3. **What fields does billing actually require from OrderCreated events?** 
   - Specifically, is customerId required for billing operations?
   - Can billing process guest orders with null customerId?
4. **What is billing's release cadence?** (to determine if consumer-first deployment is feasible)

### For platform/operations:
5. **What is the retention period for the orders.order-created topic?**
6. **Are there replay requirements?** 
   - Do new consumers read from earliest offset?
   - Are there reprocessing/backfill scenarios that require old events to remain readable?

## Recommendation

Before this change can be re-evaluated:

1. **Gather missing information** (questions above)

2. **Update consumer contracts first** if order-router and/or billing require customerId:
   - Deploy updated order-router v2 that handles null customerId appropriately
   - Deploy updated billing consumer if it also requires the field
   - Verify updated consumers are processing production events successfully

3. **Consider alternative approaches:**
   - **Two-phase migration:** Add a new optional field (e.g., `guestCheckout: boolean`) in v2, migrate consumers to handle guest orders, then make customerId nullable in v3
   - **New topic:** Use a separate `orders.guest-order-created` topic for guest orders if processing logic differs significantly
   - **Sentinel value:** Keep customerId required but use a sentinel value (e.g., "GUEST") for guest checkouts - simpler for consumers but may violate domain modeling preferences
