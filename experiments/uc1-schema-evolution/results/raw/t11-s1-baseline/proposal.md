# Change Proposal: Add `channel` Field to OrderCreated Event

## Decision: ACCEPT

The proposed v2 schema change is safe to ship. All compatibility checks passed.

## Release Sequence

1. **First: Deploy order-service** (producer) with v2 schema
2. **Later: Upgrade consumers** at their own cadence:
   - order-router (team-fulfilment): weekly release cadence
   - billing (team-billing): monthly release cadence

**Rationale**: The BACKWARD compatibility rule allows old consumers (v1 readers) to continue reading new messages (v2 writers) by ignoring the new `channel` field. Consumers can upgrade independently without coordination.

## Evidence Gathered

### 1. Registry Compatibility Check
```
✓ COMPATIBLE   rule=BACKWARD candidate=scenarios/s1-add-field/order-created-v2.avsc
```

The Apicurio Registry confirmed that v2 is backward compatible with v1. The new `channel` field includes a default value (`"web"`), which satisfies the BACKWARD compatibility requirement.

### 2. Consumer Read Matrix Verification

All 8 writer/reader combinations verified successfully:

| Writer | Consumer     | Reader | Result | Contract Fields           |
|--------|--------------|--------|--------|---------------------------|
| v1     | order-router | v1*    | ✓ PASS | orderId, customerId, amount |
| v1     | order-router | v2     | ✓ PASS | orderId, customerId, amount |
| v1     | billing      | v1*    | ✓ PASS | orderId, amount, currency |
| v1     | billing      | v2     | ✓ PASS | orderId, amount, currency |
| v2     | order-router | v1*    | ✓ PASS | orderId, customerId, amount |
| v2     | order-router | v2     | ✓ PASS | orderId, customerId, amount |
| v2     | billing      | v1*    | ✓ PASS | orderId, amount, currency |
| v2     | billing      | v2     | ✓ PASS | orderId, amount, currency |

_* = current reader schema deployed in production_

**Key verified combinations:**
- **v2 writer → v1 reader**: Critical for producer-first rollout. Both consumers (order-router and billing) successfully decoded v2 messages using their current v1 reader schemas by ignoring the new field.
- **v1 writer → v2 reader**: Ensures consumers can safely upgrade before all producers finish rolling out. The default value (`"web"`) is populated for missing fields.
- **v2 writer → v2 reader**: Confirms the new field works end-to-end when both sides are upgraded.

All required fields contracts were satisfied in every combination (2 samples decoded per test).

## Known Limitations

1. **Limited sample size**: Testing used only 2 sample messages per schema version. Production traffic may expose edge cases not covered.

2. **Field contract only**: The read matrix verified that required fields are present and decodable, but did not validate:
   - Business logic handling of the new `channel` field
   - Actual consumer application behavior beyond deserialization
   - Downstream processing or storage of the channel value

3. **Default value assumption**: The verification assumes the default value `"web"` is semantically correct for all historical messages. No validation that this accurately represents legacy orders' actual sales channel.

4. **No stress testing**: Performance impact of the schema change (larger message size, serialization overhead) was not measured.

5. **Schema resolution only**: The verification relies on Avro's schema resolution rules. Consumer frameworks' actual schema handling in production (caching, registry interaction, error handling) was not exercised.

6. **No negative test cases**: Tested only valid messages. Malformed data, invalid channel values, or schema violations were not verified.
