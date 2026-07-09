---
name: connect-debezium-to-registry
description: Configure Debezium connectors to use Apicurio Registry for schema management. Use when setting up CDC with schema registry integration, configuring Debezium converters, or connecting Debezium to Apicurio.
allowed-tools: Read, Bash, Write, Edit
---

# Connect Debezium to Apicurio Registry

Guide for configuring Debezium CDC connectors to use Apicurio Registry as the schema registry for Avro or JSON Schema encoding.

1. **Determine the environment.** Ask the user:
   - Kubernetes or OpenShift with Strimzi KafkaConnect/KafkaConnector CRs, or standalone Docker/bare-metal?
   - Source database type: PostgreSQL or MySQL?
   - Schema format: Avro (recommended) or JSON with schema (ExtJsonConverter)?
   Detect the platform: `kubectl api-resources | grep -q route.openshift.io && echo "OpenShift" || echo "Kubernetes"`. Use `oc` on OpenShift.

2. **For Kubernetes (Strimzi operator):** Create or update a `KafkaConnector` CR. The key converter properties go in `spec.config`:
   ```yaml
   apiVersion: kafka.strimzi.io/v1beta2
   kind: KafkaConnector
   metadata:
     name: my-connector
     labels:
       strimzi.io/cluster: my-connect-cluster
   spec:
     class: io.debezium.connector.postgresql.PostgresConnector  # or mysql
     tasksMax: 1
     config:
       # Database connection
       database.hostname: <db-service>
       database.port: "5432"
       database.user: postgres
       database.password: postgres
       database.dbname: sourcedb
       topic.prefix: dbserver1

       # Apicurio Avro converters
       key.converter: io.apicurio.registry.utils.converter.AvroConverter
       key.converter.apicurio.registry.url: http://<registry-service>:8080/apis/registry/v3
       key.converter.apicurio.registry.auto-register: "true"
       value.converter: io.apicurio.registry.utils.converter.AvroConverter
       value.converter.apicurio.registry.url: http://<registry-service>:8080/apis/registry/v3
       value.converter.apicurio.registry.auto-register: "true"
   ```
   The KafkaConnect CR must have the Apicurio converter JARs in its build plugins (see `examples/k8s/debezium-kafkaconnect.yaml`).
   **OpenShift:** Use `type: imagestream` for the KafkaConnect build output to push to the internal OpenShift registry instead of an external one.

3. **For Docker/standalone:** POST the connector config to the Connect REST API:
   ```bash
   curl -X POST http://localhost:8083/connectors \
     -H 'Content-Type: application/json' \
     -d '{
       "name": "my-connector",
       "config": {
         "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
         "database.hostname": "postgres",
         "database.port": "5432",
         "database.user": "postgres",
         "database.password": "postgres",
         "database.dbname": "sourcedb",
         "topic.prefix": "dbserver1",
         "key.converter": "io.apicurio.registry.utils.converter.AvroConverter",
         "key.converter.apicurio.registry.url": "http://apicurio-registry:8080/apis/registry/v3",
         "key.converter.apicurio.registry.auto-register": "true",
         "value.converter": "io.apicurio.registry.utils.converter.AvroConverter",
         "value.converter.apicurio.registry.url": "http://apicurio-registry:8080/apis/registry/v3",
         "value.converter.apicurio.registry.auto-register": "true"
       }
     }'
   ```

4. **Alternative: JSON with schema.** Replace the converter classes with `io.apicurio.registry.utils.converter.ExtJsonConverter` if the user prefers JSON encoding with schema references stored in the registry.

5. **Converter class reference:**
   - `io.apicurio.registry.utils.converter.AvroConverter` — Avro binary encoding, schema stored in registry (most common)
   - `io.apicurio.registry.utils.converter.ExtJsonConverter` — JSON encoding with schema reference header, schema stored in registry

6. **If the registry is secured (OIDC/basic auth)**, add auth properties to each converter:
   ```
   key.converter.apicurio.registry.auth.service.token.endpoint=http://<keycloak>/realms/<realm>/protocol/openid-connect/token
   key.converter.apicurio.registry.auth.client.id=<client-id>
   key.converter.apicurio.registry.auth.client.secret=<client-secret>
   ```

7. **Verify the integration:**
   - Check connector status:
     - **Docker/port-forward:** `curl http://localhost:8083/connectors/my-connector/status`
     - **OpenShift:** If Connect has a Route: `curl https://$(oc get route <connect-route> -o jsonpath='{.spec.host}')/connectors/my-connector/status`
   - Make a change in the source database (INSERT/UPDATE)
   - Check that schemas appeared in the registry: `curl http://<registry-url>/apis/registry/v3/search/artifacts`
   - Check that messages are on the Kafka topic (use `kafka-console-consumer` or `kafkacat`)

8. **Common pitfalls:**
   - Converter JARs not on the Connect classpath — ensure `ENABLE_APICURIO_CONVERTERS=true` for the Debezium image, or include them in the Strimzi KafkaConnect build plugins
   - Wrong registry URL — must include `/apis/registry/v3` path
   - Schema not found on consumer side — ensure `auto-register` is enabled on the producer (connector) side
