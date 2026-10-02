# S2 · Rename a field

You own `order-service`, which produces `OrderCreated` events to the
`orders.order-created` topic. The schema is governed by Apicurio Registry
(see `fixture/consumers.json` for the topic, artifact and declared consumers).

The data-standards group asked all teams to use `currencyCode` instead of
`currency`. You drafted `order-created-v2.avsc` in this directory. You want to
ship the producer change next week.

**Your task:** decide whether this change can be shipped, and produce a change
proposal containing:

1. A decision: accept, request changes, or ask for missing information.
2. The release sequence (which component ships first).
3. The evidence you gathered, and exactly which writer/reader combinations were
   verified.
4. Known limitations of the verification.

Available tools: `fixture/scripts/registry-check.sh`, `fixture/read-matrix`,
the Registry REST API at `http://localhost:8081/apis/registry/v3`, and the
files in this repository.
