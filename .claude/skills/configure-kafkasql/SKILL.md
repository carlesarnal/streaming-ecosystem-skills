---
name: configure-kafkasql
description: Set up KafkaSQL storage backend for Apicurio Registry, connecting it to a Kafka cluster managed by Strimzi. Use when configuring Kafka-based storage, switching from SQL to KafkaSQL, or setting up TLS/OAuth between Registry and Kafka.
allowed-tools: Read, Bash, Write, Edit
---

# Configure KafkaSQL Storage for Apicurio Registry

Guide for configuring Apicurio Registry to use KafkaSQL storage — a Kafka journal with SQL snapshots for fast startup.

1. **Determine the environment.** Ask the user:
   - Kubernetes or OpenShift with Apicurio operator + Strimzi, or standalone/Docker?
   - Kafka security: plain (no auth), TLS (mutual TLS), or OAuth (OAUTHBEARER)?
   Detect the platform: `kubectl api-resources | grep -q route.openshift.io && echo "OpenShift" || echo "Kubernetes"`. Both platforms use the same CRs — the Apicurio operator creates Routes on OpenShift and Ingresses on vanilla K8s automatically.

2. **For Kubernetes with operators (recommended):** There are three approaches, from simplest to most configurable:

   **Option A — KafkaAccess CR (simplest).** Uses Strimzi's KafkaAccess API to automatically wire the connection:
   ```yaml
   # 1. Create KafkaUser with ACLs
   apiVersion: kafka.strimzi.io/v1
   kind: KafkaUser
   metadata:
     name: apicurio-registry
     labels:
       strimzi.io/cluster: my-cluster
   spec:
     authentication:
       type: tls
     authorization:
       type: simple
       acls:
         - resource: { type: topic, name: kafkasql-journal, patternType: literal }
           operations: [All]
         - resource: { type: topic, name: kafkasql-snapshots, patternType: literal }
           operations: [All]
         - resource: { type: topic, name: registry-events, patternType: literal }
           operations: [All]
         - resource: { type: group, name: "*", patternType: literal }
           operations: [All]
   ---
   # 2. Create KafkaAccess
   apiVersion: access.strimzi.io/v1alpha1
   kind: KafkaAccess
   metadata:
     name: my-kafka-access
   spec:
     kafka: { name: my-cluster, listener: tls }
     user: { kind: KafkaUser, apiGroup: kafka.strimzi.io, name: apicurio-registry }
   ---
   # 3. Reference in ApicurioRegistry3
   apiVersion: registry.apicur.io/v1
   kind: ApicurioRegistry3
   metadata:
     name: my-registry
   spec:
     app:
       storage:
         type: kafkasql
         kafkasql:
           kafkaAccessSecretName: my-kafka-access
   ```

   **Option B — Manual bootstrapServers (plain, no auth):**
   ```yaml
   apiVersion: registry.apicur.io/v1
   kind: ApicurioRegistry3
   metadata:
     name: my-registry
   spec:
     app:
       storage:
         type: kafkasql
         kafkasql:
           bootstrapServers: "my-cluster-kafka-bootstrap.<namespace>.svc:9092"
   ```

   **Option C — Manual with TLS:**
   ```yaml
   spec:
     app:
       storage:
         type: kafkasql
         kafkasql:
           bootstrapServers: "my-cluster-kafka-bootstrap.<namespace>.svc:9093"
           tls:
             keystoreSecretRef:
               name: apicurio-registry   # Strimzi-generated KafkaUser secret
             keystorePasswordSecretRef:
               name: apicurio-registry
             truststoreSecretRef:
               name: my-cluster-cluster-ca-cert  # Strimzi cluster CA
             truststorePasswordSecretRef:
               name: my-cluster-cluster-ca-cert
   ```

   **Option D — Manual with OAuth:**
   ```yaml
   spec:
     app:
       storage:
         type: kafkasql
         kafkasql:
           bootstrapServers: "my-cluster-kafka-bootstrap.<namespace>.svc:9093"
           auth:
             enabled: true
             mechanism: "OAUTHBEARER"
             clientIdRef:
               name: client-credentials
               key: clientId
             clientSecretRef:
               name: client-credentials
               key: clientSecret
             tokenEndpoint: http://keycloak:8080/realms/registry/protocol/openid-connect/token
             loginHandlerClass: io.strimzi.kafka.oauth.client.JaasClientOauthLoginCallbackHandler
   ```

   See full example CRs in `examples/k8s/apicurio-registry-kafkasql.yaml`.

3. **For Docker/standalone:** Set environment variables:
   ```bash
   APICURIO_STORAGE_KIND=kafkasql
   APICURIO_KAFKASQL_BOOTSTRAP_SERVERS=kafka:9092
   ```
   For TLS, additionally set:
   ```bash
   APICURIO_KAFKASQL_SECURITY_PROTOCOL=SSL
   APICURIO_KAFKASQL_SSL_KEYSTORE_LOCATION=/path/to/keystore.p12
   APICURIO_KAFKASQL_SSL_KEYSTORE_PASSWORD=changeit
   APICURIO_KAFKASQL_SSL_TRUSTSTORE_LOCATION=/path/to/truststore.p12
   APICURIO_KAFKASQL_SSL_TRUSTSTORE_PASSWORD=changeit
   ```

4. **KafkaSQL creates these Kafka topics automatically:**
   - `kafkasql-journal` — the event journal (all state changes)
   - `kafkasql-snapshots` — periodic snapshots for fast startup
   - `registry-events` — integration events (optional, for consumers)
   Ensure the Kafka user has permissions for these topics (see ACLs in Option A above).

5. **Verify the setup:**
   - Registry starts without errors: check logs for `KafkaSQL storage initialized`
   - Topics were created: list topics on the Kafka cluster
   - API responds: `curl http://<registry>:8080/apis/registry/v3/system/info`
   - Create an artifact via API and verify it persists across registry restarts
