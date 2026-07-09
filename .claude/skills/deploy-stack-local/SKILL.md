---
name: deploy-stack-local
description: Spin up the Strimzi + Apicurio Registry + Debezium + Kroxylicious stack locally with Docker Compose. Use for local development, quick prototyping, or testing the streaming ecosystem without Kubernetes.
allowed-tools: Read, Bash, Write, Edit
---

# Deploy Streaming Stack Locally

Guide for running Kafka, Apicurio Registry, Debezium Connect, and a source database locally using Docker Compose.

1. **Check prerequisites.** Verify Docker or Podman is available:
   ```bash
   docker compose version || podman-compose version
   ```

2. **Use the full-stack compose file.** Reference `examples/docker-compose/full-stack.yaml` from this repo. It includes:
   - **Kafka** (Strimzi image, KRaft mode, no Zookeeper) on port 9092
   - **PostgreSQL** (source database for CDC + registry storage) on port 5432
   - **Apicurio Registry** (SQL storage) on port 8080
   - **Apicurio Registry UI** on port 8888
   - **Debezium Connect** (with Apicurio converters enabled) on port 8083
   - **Kroxylicious** (Kafka proxy with optional filters) on port 19092
   Copy or symlink the file to the user's working directory if needed.

3. **Start the stack.** Run:
   ```bash
   docker compose -f full-stack.yaml up -d
   ```
   Wait for all services to be healthy. Check with:
   ```bash
   docker compose -f full-stack.yaml ps
   ```

4. **Verify services are ready.** Poll the health endpoints:
   ```bash
   # Registry API
   curl -s http://localhost:8080/apis/registry/v3/system/info | head -20

   # Debezium Connect
   curl -s http://localhost:8083/ | head -20

   # Registry UI
   curl -s -o /dev/null -w '%{http_code}' http://localhost:8888/
   ```

5. **Provide endpoint summary to the user:**
   - Apicurio Registry API: `http://localhost:8080/apis/registry/v3`
   - Apicurio Registry UI: `http://localhost:8888`
   - Kafka bootstrap (direct): `localhost:9092`
   - Kafka bootstrap (via Kroxylicious proxy): `localhost:19092`
   - Debezium Connect REST API: `http://localhost:8083`
   - PostgreSQL: `localhost:5432` (user: `postgres`, password: `postgres`, database: `sourcedb`)

6. **Suggest next steps:**
   - Create a Debezium connector: use the `connect-debezium-to-registry` skill
   - Wire a Kafka producer/consumer: use the `setup-kafka-serdes` skill
   - Configure Kroxylicious filters (encryption, validation): use the `configure-kroxylicious-filters` skill
   - Make a change in the source database and watch schemas appear in the Registry UI
