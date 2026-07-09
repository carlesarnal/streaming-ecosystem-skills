---
name: deploy-stack
description: Deploy the Strimzi + Apicurio Registry + Debezium streaming stack on Kubernetes or OpenShift using operators. Use when setting up the streaming ecosystem on K8s/OpenShift, deploying Kafka with Strimzi, or wiring Apicurio and Debezium together on a cluster.
allowed-tools: Read, Bash, Write, Edit
---

# Deploy Streaming Stack on Kubernetes / OpenShift

Guide for deploying Strimzi (Kafka), Apicurio Registry, and optionally Debezium on Kubernetes or OpenShift using their respective operators. All CRs and operators are fully compatible with both platforms.

1. **Detect the platform and check prerequisites.** Determine if this is OpenShift or vanilla Kubernetes:
   ```bash
   # Detect OpenShift
   kubectl api-resources | grep -q route.openshift.io && echo "OpenShift" || echo "Kubernetes"
   # Or check: oc version 2>/dev/null
   ```
   Use `oc` on OpenShift, `kubectl` on vanilla K8s — both work, but `oc` provides OpenShift-specific features (login, projects, routes).

   Check if the Strimzi operator is installed (`kubectl get crd kafkas.kafka.strimzi.io`). If not:
   - **OpenShift:** Install "AMQ Streams" (or "Strimzi") from OperatorHub in the web console, or via CLI:
     ```bash
     oc apply -f - <<EOF
     apiVersion: operators.coreos.com/v1alpha1
     kind: Subscription
     metadata:
       name: strimzi-kafka-operator
       namespace: openshift-operators
     spec:
       channel: stable
       name: strimzi-kafka-operator
       source: community-operators
       sourceNamespace: openshift-marketplace
     EOF
     ```
   - **Kubernetes:** Install via YAML manifests:
     ```bash
     kubectl create namespace kafka
     kubectl create -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka
     ```

   Check if the Apicurio Registry operator is installed (`kubectl get crd apicurioregistries3.registry.apicur.io`). If not:
   - **OpenShift:** Install "Apicurio Registry" from OperatorHub, or via a Subscription CR targeting `community-operators`.
   - **Kubernetes:** Install via OLM or direct manifests from the Apicurio operator releases.

2. **Ask the user about configuration.** Determine:
   - Which namespace/project to deploy into
   - Kafka auth mode: plain (no auth), TLS (mutual TLS), or OAuth
   - Registry storage: SQL (PostgreSQL) or KafkaSQL (Kafka-backed)
   - Whether Debezium is needed
   - If Debezium: which source database (PostgreSQL, MySQL)
   - **OpenShift only:** Whether to expose Kafka externally via Routes (listener `type: route`)

3. **Deploy Strimzi Kafka cluster.** Use the example CRs from this repo as templates:
   - Plain: `examples/k8s/strimzi-kafka.yaml`
   - TLS: `examples/k8s/strimzi-kafka-tls.yaml`
   - **OpenShift external access:** Add a `route` type listener to the Kafka CR:
     ```yaml
     listeners:
       - name: external
         port: 9094
         type: route
         tls: true
     ```
     This creates OpenShift Routes automatically for each broker + bootstrap. The Routes are TLS-passthrough, so clients need the cluster CA certificate.
   Apply and wait for readiness:
   ```bash
   kubectl wait kafka/my-cluster --for=condition=Ready --timeout=300s -n <namespace>
   ```

4. **Deploy PostgreSQL if needed.** Required for SQL storage variant.
   - **OpenShift:** Use the PostgreSQL template from the catalog, or Crunchy PGO operator:
     ```bash
     oc new-app postgresql-persistent -p POSTGRESQL_USER=apicurio -p POSTGRESQL_PASSWORD=apicurio -p POSTGRESQL_DATABASE=apicurio-registry
     ```
   - **Kubernetes:** Deploy a PostgreSQL instance (Crunchy, Zalando, or a simple StatefulSet).
   The registry needs a database named `apicurio-registry` with a user that has DDL privileges.

5. **Deploy Apicurio Registry.** Use the operator CR templates:
   - SQL: `examples/k8s/apicurio-registry-sql.yaml` — set the datasource URL to the PostgreSQL service
   - KafkaSQL: `examples/k8s/apicurio-registry-kafkasql.yaml` — set `bootstrapServers` to `my-cluster-kafka-bootstrap.<namespace>.svc:9092` (plain) or `:9093` (TLS)
   For KafkaSQL with TLS, configure keystore/truststore secret references from the Strimzi-generated secrets.
   **OpenShift:** The operator automatically creates Routes from the `spec.app.ingress.host` and `spec.ui.ingress.host` fields. Set these to the desired hostnames or let OpenShift generate them.
   Wait for the registry pod to be ready.

6. **Deploy Debezium via Strimzi KafkaConnect CR (optional).** This is the operator-native approach — do NOT use a raw Deployment. Use `examples/k8s/debezium-kafkaconnect.yaml` which includes:
   - A `build` section that pulls the Debezium connector plugin from Maven
   - Apicurio converter JARs included via the build plugins
   - The annotation `strimzi.io/use-connector-resources: "true"` to enable KafkaConnector CRs
   **OpenShift:** For the KafkaConnect build output, use `type: imagestream` instead of `type: docker` to push to the internal OpenShift registry:
   ```yaml
   build:
     output:
       type: imagestream
       image: my-connect-cluster:latest
   ```
   This avoids needing an external container registry. OpenShift's internal registry handles the image.
   Apply and wait for the KafkaConnect resource to be ready.

7. **Create KafkaConnector CR for the source database.** Use:
   - PostgreSQL: `examples/k8s/debezium-connector-postgres.yaml`
   - MySQL: `examples/k8s/debezium-connector-mysql.yaml`
   Update the database connection details (hostname, port, credentials) and the registry URL.

8. **Verify end-to-end.** Check:
   - Kafka topics exist: `kubectl exec my-cluster-kafka-0 -- bin/kafka-topics.sh --bootstrap-server localhost:9092 --list`
   - Registry API responds:
     - **OpenShift:** Use the Route URL: `curl https://$(oc get route <registry-route> -o jsonpath='{.spec.host}')/apis/registry/v3/system/info`
     - **Kubernetes:** Port-forward: `kubectl port-forward svc/<registry-service> 8080:8080` then `curl http://localhost:8080/apis/registry/v3/system/info`
   - If Debezium is deployed: make a change in the source database and verify schemas appear in the registry and messages appear on the CDC topic
   - **OpenShift:** Check Routes are created: `oc get routes -n <namespace>`
