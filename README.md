# Streaming Ecosystem Skills

Claude Code skills for the **Strimzi + Apicurio Registry + Debezium + Kroxylicious** streaming ecosystem.

These skills help you deploy, connect, configure, and troubleshoot the four projects together — on **Kubernetes**, **OpenShift**, or locally with **Docker Compose**.

All skills and example manifests are fully compatible with both vanilla Kubernetes and OpenShift. On OpenShift, the skills automatically handle platform-specific features: OperatorHub installation, Route-based ingress, ImageStream builds for KafkaConnect, and SCC troubleshooting.

## Installation

Clone this repo and add it as a skill source in your project:

```bash
git clone https://github.com/carlesarnal/streaming-ecosystem-skills.git
```

Then copy or symlink the `.claude/skills/` directories into your project's `.claude/skills/`.

## Skills

| Skill | Description |
|-------|-------------|
| `deploy-stack` | Deploy the full Strimzi + Apicurio + Debezium stack on Kubernetes/OpenShift using operators |
| `deploy-stack-local` | Spin up the full stack locally with Docker Compose |
| `connect-debezium-to-registry` | Configure Debezium connectors to use Apicurio Registry for schema management |
| `setup-kafka-serdes` | Wire Kafka producers/consumers to use Apicurio SerDes |
| `configure-kafkasql` | Set up KafkaSQL storage backend for Apicurio Registry |
| `deploy-kroxylicious` | Deploy the Kroxylicious Kafka proxy on Kubernetes/OpenShift with Strimzi integration |
| `configure-kroxylicious-filters` | Configure Kroxylicious filters (encryption, schema validation, multi-tenancy) |
| `troubleshoot-integration` | Diagnose common cross-project integration issues |
| `evolve-event-schema` | Decide whether an event schema change can ship safely with independently released consumers, backed by Registry and client read checks |

## Example Manifests

The `examples/` directory contains ready-to-use manifests:

### Kubernetes (`examples/k8s/`)

- `strimzi-kafka.yaml` — Strimzi Kafka cluster (KRaft, plain listener)
- `strimzi-kafka-tls.yaml` — Strimzi Kafka cluster (TLS + mutual auth)
- `apicurio-registry-sql.yaml` — Apicurio Registry with PostgreSQL storage
- `apicurio-registry-kafkasql.yaml` — Apicurio Registry with KafkaSQL storage
- `debezium-kafkaconnect.yaml` — Strimzi KafkaConnect CR with Debezium + Apicurio converters
- `debezium-connector-postgres.yaml` — KafkaConnector for PostgreSQL CDC
- `debezium-connector-mysql.yaml` — KafkaConnector for MySQL CDC
- `kroxylicious-proxy.yaml` — Kroxylicious proxy with Strimzi integration (KafkaProxy + KafkaService + VirtualKafkaCluster)
- `kroxylicious-encryption-filter.yaml` — KafkaProtocolFilter for record encryption (Vault + AWS KMS)
- `kroxylicious-validation-filter.yaml` — KafkaProtocolFilter for record validation (Apicurio Registry)

### Docker Compose (`examples/docker-compose/`)

- `full-stack.yaml` — Kafka + PostgreSQL + Apicurio Registry + Kroxylicious + Debezium Connect + Registry UI

## Experiments

- [`experiments/uc1-schema-evolution/`](experiments/uc1-schema-evolution/): RHAF Agentic Skills Use Case 1. A fixture, three scenarios and a protocol for measuring `evolve-event-schema` against the same assistant without the skill.

## Project Links

- [Strimzi](https://strimzi.io/) — Kafka on Kubernetes
- [Apicurio Registry](https://www.apicur.io/registry/) — API and Schema Registry
- [Debezium](https://debezium.io/) — Change Data Capture
- [Kroxylicious](https://kroxylicious.io/) — Kafka Protocol Proxy

## License

Apache License 2.0
