# Change Proposal: Add `channel` Field to OrderCreated

## Decision: Accept with conditions

The schema change is technically safe and passes all compatibility checks. However, the **configured BACKWARD-only rule constrains the release sequence** to require all consumers upgrade before the producer can ship. Given billing's monthly release cadence, this would delay the feature by up to 4 weeks.

**Recommendation:** Accept the change and either:
1. **(Preferred)** Update the artifact compatibility rule to `FULL` to allow producer-first deployment, OR
2. Accept the delay and deploy consumers first (order-router week 1, billing by week 4, producer week 5)

The change is verified safe under both sequences.

## Change Summary

Add optional `channel` field (type `string`, default `"web"`) to the `OrderCreated` event schema (v1 → v2). This field tracks the sales channel (web, mobile, etc.) for analytics purposes and is informational only—no consumer currently requires it.

## Constraints

| Constraint | Value | Source |
|------------|-------|--------|
| **Topic** | `orders.order-created` | consumers.json |
| **Registry artifact** | `orders-t10/orders.order-created-value` | consumers.json |
| **Artifact type** | AVRO | consumers.json |
| **Configured compatibility rule** | `BACKWARD` | consumers.json, verified via Registry API |
| **Producer** | order-service, currently on v1 | consumers.json |
| **Consumer: order-router** | team-fulfilment, weekly releases, reader v1, requires [orderId, customerId, amount] | consumers.json |
| **Consumer: billing** | team-billing, **monthly releases**, reader v1, requires [orderId, amount, currency] | consumers.json |
| **Old event retention** | **UNKNOWN** — no documented retention policy or replay requirements found | assumption ⚠️ |
| **New consumers reading old events** | **UNKNOWN** — unclear if new deployments read from earliest offset | assumption ⚠️ |
| **Serde library** | Apicurio Avro deserializer (Camel + plain Kafka consumer) | consumers.json |

⚠️ **Assumptions:** No explicit retention or replay requirements documented. Assumed standard practice (finite retention, no guaranteed replay of old events by new readers).

## Required Compatibility Direction and Why

**Configured rule:** `BACKWARD` — new readers must read old data.

**Actually needed (based on practical release constraints):**
- **FORWARD** is required if producer ships before all consumers upgrade (likely, given billing's monthly cadence).
- **BACKWARD** is required if old events might be replayed by new readers (unknown, but prudent assumption).
- **FULL** covers both directions and is the safest choice given unknowns.

**Analysis:**
- The configured `BACKWARD` rule assumes consumers upgrade first, then producer.
- With billing's monthly release cycle, this forces a ~4-week delay.
- Producer-first deployment requires `FORWARD` compatibility (verified below).
- If old events exist in the topic and might be read by new consumers, `BACKWARD` is also needed (verified).
- **Recommendation:** Use `FULL` compatibility to enable flexible release ordering.

## Evidence

### Registry Compatibility Checks

| Check | Rule | Result | Detail |
|-------|------|--------|--------|
| Registry dry-run | `BACKWARD` | ✅ PASS | HTTP 200, new readers (v2) can read old data (v1) |
| Registry dry-run | `FORWARD` | ✅ PASS | HTTP 200, old readers (v1) can read new data (v2) |
| Registry dry-run | `FULL` | ✅ PASS | HTTP 200, both directions safe |

**Tool:** `fixture/scripts/registry-check.sh check scenarios/s1-add-field/order-created-v2.avsc [RULE]`  
**Registry URL:** http://localhost:8081/apis/registry/v3

### Client Read Matrix

| Writer | Consumer | Reader | Result | Detail |
|--------|----------|--------|--------|--------|
| v1 | order-router | v1 (current) | ✅ PASS | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v1 | order-router | v2 | ✅ PASS | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v1 | billing | v1 (current) | ✅ PASS | Decoded 2 samples; contract [orderId, amount, currency] satisfied |
| v1 | billing | v2 | ✅ PASS | Decoded 2 samples; contract [orderId, amount, currency] satisfied |
| v2 | order-router | v1 (current) | ✅ PASS | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v2 | order-router | v2 | ✅ PASS | Decoded 2 samples; contract [orderId, customerId, amount] satisfied |
| v2 | billing | v1 (current) | ✅ PASS | Decoded 2 samples; contract [orderId, amount, currency] satisfied |
| v2 | billing | v2 | ✅ PASS | Decoded 2 samples; contract [orderId, amount, currency] satisfied |

**Summary:** 8/8 combinations passed, 0 failed, 0 unverified  
**Tool:** `fixture/scripts/read-matrix.sh scenarios/s1-add-field/`  
**Test data:** v1 samples (2 events), v2 samples (2 events with `channel` field)

**Interpretation:**
- ✅ **v1 writer → v2 reader (BACKWARD):** New readers successfully decode old events; `channel` defaults to `"web"`.
- ✅ **v2 writer → v1 reader (FORWARD):** Old readers successfully decode new events; `channel` field is ignored.
- ✅ **Consumer contracts:** All required fields ([orderId, customerId, amount] for order-router; [orderId, amount, currency] for billing) are present and decodable in every combination.

## Release Sequence

### Option 1: Producer-first (requires FULL rule)

**Prerequisite:** Update artifact compatibility rule from `BACKWARD` to `FULL` in Registry.

1. **Week 1:** Deploy order-service v2 (starts producing `channel` field with default `"web"` or actual value)
2. **Week 1-4:** Both consumers continue running v1 readers, successfully ignoring the new `channel` field (FORWARD verified)
3. **Week 2:** Deploy order-router v2 (optional, can leverage `channel` if needed)
4. **Week 4:** Deploy billing v2 (optional, can leverage `channel` if needed)

**Benefit:** Feature available immediately; consumers upgrade on their natural cadence.  
**Risk:** None—FORWARD compatibility verified for v2 writer → v1 reader.

### Option 2: Consumer-first (works with current BACKWARD rule)

1. **Week 1:** Deploy order-router v2 (starts accepting `channel` field, receives default `"web"` from v1 producer)
2. **Week 2-4:** billing still on v1, reads v1 events successfully
3. **Week 4:** Deploy billing v2 (starts accepting `channel` field)
4. **Week 5:** Deploy order-service v2 (starts producing actual `channel` values)

**Benefit:** No Registry rule change needed.  
**Drawback:** 4-week delay to feature availability; coordination overhead across 3 teams.

### Recommendation

**Use Option 1 (producer-first)** with `FULL` compatibility rule:
- Faster time-to-value (immediate vs 4-week delay)
- No cross-team coordination required (consumers upgrade independently)
- All compatibility checks passed—no additional risk

## Not Verified / Limitations

1. **Topic retention period:** Unknown. If retention exceeds typical consumer lag, old v1 events might be replayed by new v2 readers during incidents or backfills. BACKWARD compatibility (verified) covers this, but the actual retention setting was not confirmed.

2. **New consumer bootstrap behavior:** Unknown if new consumer instances read from `earliest` offset. If they do, they would encounter old v1 events. BACKWARD compatibility (verified) covers this scenario.

3. **Edge case: null or empty `channel` values:** The v2 schema defines `channel` as non-nullable `string` with default `"web"`. Sample data included `"mobile"` and `"web"`, but did not test empty string `""` or programmatically null assignments (which would fail schema validation). Assumes producer implementation respects the non-null contract.

4. **Serde version compatibility:** Read matrix uses Apicurio Avro deserializer per consumers.json, but specific library versions were not verified. Assumes current production versions behave consistently with the test fixture.

5. **Concurrent writer/reader upgrades:** Tests verified discrete v1/v2 combinations, not concurrent rollings deploys (e.g., 50% producer pods on v2 while consumers are mid-rollout). This is expected to be safe given per-message schema versioning, but was not explicitly tested.

## Questions for Owners

_None at this time._ All required information was available in consumers.json and verified via tooling. If Option 1 (producer-first) is chosen, confirm with platform team that updating the artifact rule to `FULL` is acceptable and does not conflict with organizational schema governance policies.
