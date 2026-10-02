# S3 · Allow guest checkouts

You own `order-service`, which produces `OrderCreated` events to the
`orders.order-created` topic. The schema is governed by Apicurio Registry.
For this scenario, the consumer inventory is in `consumers.json` in **this
directory** (it replaces `fixture/consumers.json`).

The business is launching guest checkout, so some orders will have no
customer. You drafted `order-created-v2.avsc` in this directory, which makes
`customerId` nullable. Sample v2 events are in `order-created-v2.jsonl`.

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
