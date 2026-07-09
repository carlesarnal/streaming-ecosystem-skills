---
name: deploy-stack
description: Deploy the Strimzi + Apicurio Registry + Debezium streaming stack on Kubernetes using operators. Use when setting up the streaming ecosystem on K8s, deploying Kafka with Strimzi, or wiring Apicurio and Debezium together on a cluster.
allowed-tools: Read, Bash, Write, Edit
---

# Deploy Streaming Stack on Kubernetes

Guide for deploying Strimzi (Kafka), Apicurio Registry, and optionally Debezium on Kubernetes using their respective operators.

1. **Check prerequisites.** Verify `kubectl` is configured and has cluster access. Check if the Strimzi operator is installed (`kubectl get crd kafkas.kafka.strimzi.io`). If not, install it:
   ```bash
   kubectl create namespace kafka
   kubectl create -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka
   ```
   Check if the Apicurio Registry operator is installed (`kubectl get crd apicurioregistries3.registry.apicur.io`). If not, install via OLM or direct manifests from the Apicurio operator releases.

2. **Ask the user about configuration.** Determine:
   - Which namespace to deploy into
   - Kafka auth mode: plain (no auth), TLS (mutual TLS), or OAuth
   - Registry storage: SQL (PostgreSQL) or KafkaSQL (Kafka-backed)
   - Whether Debezium is needed
   - If Debezium: which source database (PostgreSQL, MySQL)

3. **Deploy Strimzi Kafka cluster.** Use the example CRs from this repo as templates:
   - Plain: `examples/k8s/strimzi-kafka.yaml`
   - TLS: `examples/k8s/strimzi-kafka-tls.yaml`
   Apply with `kubectl apply -f` and wait for readiness:
   ```bash
   kubectl wait kafka/my-cluster --for=condition=Ready --timeout=300s -n <namespace>
   ```

4. **Deploy PostgreSQL if needed.** Required for SQL storage variant. Deploy a PostgreSQL instance (Crunchy, Zalando, or a simple StatefulSet). The registry needs a database named `apicurio-registry` with a user that has DDL privileges.

5. **Deploy Apicurio Registry.** Use the operator CR templates:
   - SQL: `examples/k8s/apicurio-registry-sql.yaml` — set the datasource URL to the PostgreSQL service
   - KafkaSQL: `examples/k8s/apicurio-registry-kafkasql.yaml` — set `bootstrapServers` to `my-cluster-kafka-bootstrap.<namespace>.svc:9092` (plain) or `:9093` (TLS)
   For KafkaSQL with TLS, configure keystore/truststore secret references from the Strimzi-generated secrets.
   Wait for the registry pod to be ready.

6. **Deploy Debezium via Strimzi KafkaConnect CR (optional).** This is the operator-native approach — do NOT use a raw Deployment. Use `examples/k8s/debezium-kafkaconnect.yaml` which includes:
   - A `build` section that pulls the Debezium connector plugin from Maven
   - Apicurio converter JARs included via the build plugins
   - The annotation `strimzi.io/use-connector-resources: "true"` to enable KafkaConnector CRs
   Apply and wait for the KafkaConnect resource to be ready.

7. **Create KafkaConnector CR for the source database.** Use:
   - PostgreSQL: `examples/k8s/debezium-connector-postgres.yaml`
   - MySQL: `examples/k8s/debezium-connector-mysql.yaml`
   Update the database connection details (hostname, port, credentials) and the registry URL.

8. **Verify end-to-end.** Check:
   - Kafka topics exist: `kubectl exec my-cluster-kafka-0 -- bin/kafka-topics.sh --bootstrap-server localhost:9092 --list`
   - Registry API responds: `kubectl port-forward svc/<registry-service> 8080:8080` then `curl http://localhost:8080/apis/registry/v3/system/info`
   - If Debezium is deployed: make a change in the source database and verify schemas appear in the registry and messages appear on the CDC topic
