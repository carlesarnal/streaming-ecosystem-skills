# Change Proposal: Allow Guest Checkouts (Nullable customerId)

## Decision: REQUEST CHANGES

The proposed v2 schema **cannot be shipped safely** with the current consumer inventory. Critical breakage will occur regardless of release sequence.

---

## Evidence

### Registry Compatibility Check
```
✓ BACKWARD compatible per Apicurio Registry rules
```

The v2 schema passes Apicurio's BACKWARD compatibility check because making a field nullable with a default value is valid Avro schema evolution.

### Consumer Read Matrix

Verified all writer/reader combinations using `fixture/read-matrix`:

| Writer | Consumer     | Reader | Result     | Detail |
|--------|--------------|--------|------------|--------|
| v1     | order-router | v1*    | **PASS**   | decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v1     | order-router | v2     | **PASS**   | decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v1     | billing      | v1     | UNVERIFIED | decoded 2 samples; consumer contract unknown |
| v1     | billing      | v2     | UNVERIFIED | decoded 2 samples; consumer contract unknown |
| **v2** | **order-router** | **v1*** | **FAIL** | sample #2 not decodable: Found null, expecting string |
| **v2** | **order-router** | **v2**  | **FAIL** | sample #2: required field 'customerId' is null |
| **v2** | **billing**      | **v1**  | **FAIL** | sample #2 not decodable: Found null, expecting string |
| v2     | billing      | v2     | UNVERIFIED | decoded 2 samples; consumer contract unknown |

*\* = current reader schema per inventory*

**Critical findings:**
1. **order-router** (team-fulfilment) has `customerId` in its `requiredFields` contract, meaning it **requires** this field to be non-null for business logic
2. When v2 events with null customerId are sent:
   - Consumers still on v1 reader schema cannot decode them (Avro schema mismatch)
   - order-router on v2 reader schema can decode but fails its business contract (null required field)

---

## Release Sequence Analysis

**No safe release sequence exists:**

### Scenario A: Producer ships first
1. order-service deploys v2, starts sending events with null customerId
2. order-router (still on v1 reader) **immediately fails** - cannot decode null string
3. billing (unknown reader) **likely fails** if on v1 reader

### Scenario B: Consumers upgrade first  
1. order-router upgrades to v2 reader schema
2. order-service deploys v2, sends events with null customerId  
3. order-router **still fails** - decoded event has null customerId, violating `requiredFields: ["customerId"]` contract

**Root cause:** order-router's business logic requires customerId to be non-null, which conflicts with the guest checkout feature where customerId must be null.

---

## Missing Information

The following gaps prevent complete verification:

1. **billing consumer** (team-billing):
   - Current reader schema: **unknown**
   - Required fields contract: **unknown**  
   - Release cadence: **unknown**
   - Cannot verify impact without this information

2. **Topic configuration:**
   - Retention and replay requirements: **not documented**
   - Cannot assess risk window for breaking changes

3. **order-router contract:**
   - Why does order-router require customerId?
   - Can it be made optional in the business logic?

---

## Required Changes

Before this schema change can ship:

### 1. Update order-router's business logic
The order-router service must be modified to handle null customerId values for guest checkouts:
- Remove `customerId` from `requiredFields` in consumers.json  
- Update business logic to handle guest orders (null customerId)
- Deploy and verify the updated order-router

### 2. Document billing consumer
Contact team-billing to determine:
- Current reader schema version
- Whether billing requires customerId
- Release cadence and upgrade plan

### 3. Once consumers are ready, follow this sequence:
1. Deploy updated consumers (order-router without customerId requirement, billing if needed)
2. Verify consumers handle both non-null and null customerId correctly
3. Deploy order-service v2
4. Monitor for errors

---

## Verification Performed

**Tools used:**
- `fixture/scripts/registry-check.sh` - Apicurio Registry BACKWARD compatibility
- `fixture/read-matrix` - Consumer contract verification across all writer/reader combinations

**Writer/reader combinations verified:**
- v1 writer × v1 reader (current state baseline)
- v1 writer × v2 reader (consumers upgrade first)
- v2 writer × v1 reader (producer upgrades first)  
- v2 writer × v2 reader (both upgraded)

**Tested with:**
- 2 v1 sample events (both with non-null customerId)
- 2 v2 sample events (1 with non-null, 1 with null customerId for guest checkout)

---

## Known Limitations

1. **Incomplete consumer inventory:** billing's requirements unknown - actual impact may be greater
2. **Sample coverage:** Only 2 events per version tested; edge cases may exist
3. **No production traffic analysis:** Don't know actual distribution of guest vs. registered orders
4. **No consumer code review:** Only verified against declared contracts; consumers may have undocumented dependencies on customerId
5. **Schema resolution only:** Did not test end-to-end with actual Kafka + Apicurio deserializers in consumer environment
