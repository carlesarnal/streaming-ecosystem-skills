---
name: deploy-kroxylicious
description: Deploy Kroxylicious Kafka proxy on Kubernetes or OpenShift using the operator, integrated with a Strimzi-managed Kafka cluster. Use when setting up record encryption, schema validation, multi-tenancy, or any Kafka proxy use case with Kroxylicious.
allowed-tools: Read, Bash, Write, Edit
---

# Deploy Kroxylicious on Kubernetes / OpenShift

Guide for deploying the Kroxylicious Kafka proxy alongside a Strimzi-managed Kafka cluster using the Kroxylicious operator. All CRs are compatible with both Kubernetes and OpenShift.

1. **Detect the platform and check prerequisites.** Determine if this is OpenShift or vanilla Kubernetes:
   ```bash
   kubectl api-resources | grep -q route.openshift.io && echo "OpenShift" || echo "Kubernetes"
   ```
   Verify Strimzi is installed and a Kafka cluster is running (Strimzi 0.49.0+ required for Kroxylicious integration):
   ```bash
   kubectl get kafka -A
   ```
   If no Kafka cluster exists, use the `deploy-stack` skill first.

2. **Ask the user about configuration.** Determine:
   - Which namespace to deploy Kroxylicious into
   - The name of the existing Strimzi Kafka cluster to proxy
   - Use case: record encryption, schema validation (Apicurio Registry), multi-tenancy, or plain proxy
   - If encryption: KMS provider — HashiCorp Vault or AWS KMS
   - If validation: Apicurio Registry URL and schema global ID
   - Ingress type: `clusterIP` (internal only) or `loadBalancer` (external access)

3. **Install the Kroxylicious operator.** Check if it's already installed:
   ```bash
   kubectl get crd kafkaproxies.kroxylicious.io 2>/dev/null && echo "Installed" || echo "Not installed"
   ```
   If not installed:
   - **OpenShift:** Install "Streams for Apache Kafka Proxy" from OperatorHub, or via a Subscription CR:
     ```yaml
     apiVersion: operators.coreos.com/v1alpha1
     kind: Subscription
     metadata:
       name: kroxylicious-operator
       namespace: openshift-operators
     spec:
       channel: stable
       name: kroxylicious-operator
       source: community-operators
       sourceNamespace: openshift-marketplace
     ```
   - **Kubernetes:** Download the operator release from [GitHub](https://github.com/kroxylicious/kroxylicious/releases) and apply:
     ```bash
     kubectl apply -f kroxylicious-operator-install/
     ```
   Wait for the operator pod to be ready:
   ```bash
   kubectl wait deployment -l app=kroxylicious-operator --for=condition=Available --timeout=120s -n <operator-namespace>
   ```

4. **Create the KafkaProxy CR.** This is the top-level resource representing a proxy instance. Use `examples/k8s/kroxylicious-proxy.yaml` as a template:
   ```yaml
   apiVersion: kroxylicious.io/v1alpha1
   kind: KafkaProxy
   metadata:
     name: my-proxy
   spec: {}
   ```
   Apply: `kubectl apply -f kroxylicious-proxy.yaml -n <namespace>`

5. **Create the KafkaProxyIngress CR.** Defines how clients connect to the proxy:
   ```yaml
   apiVersion: kroxylicious.io/v1alpha1
   kind: KafkaProxyIngress
   metadata:
     name: my-proxy-ingress
   spec:
     proxyRef:
       name: my-proxy
     clusterIP:
       protocol: TCP
   ```
   For external access, use `loadBalancer` instead of `clusterIP`:
   ```yaml
   spec:
     proxyRef:
       name: my-proxy
     loadBalancer:
       protocol: TCP
       bootstrapNodePort: 30092
   ```

6. **Create the KafkaService CR.** References the Strimzi Kafka cluster. Use `strimziKafkaRef` for automatic discovery:
   ```yaml
   apiVersion: kroxylicious.io/v1alpha1
   kind: KafkaService
   metadata:
     name: my-kafka-service
   spec:
     strimziKafkaRef:
       name: my-cluster
   ```
   Alternatively, for non-Strimzi clusters or explicit configuration:
   ```yaml
   spec:
     bootstrapServers: kafka-bootstrap:9092
     nodeIdRanges:
       - name: brokers
         start: 0
         end: 2
   ```

7. **Create KafkaProtocolFilter CR(s) based on use case.** Skip this step if deploying a plain proxy with no filters.

   **Record Encryption (Vault):** Use `examples/k8s/kroxylicious-encryption-filter.yaml`:
   ```yaml
   apiVersion: kroxylicious.io/v1alpha1
   kind: KafkaProtocolFilter
   metadata:
     name: my-encryption-filter
   spec:
     type: RecordEncryption
     configTemplate:
       kms: VaultKmsService
       kmsConfig:
         vaultTransitEngineUrl: https://vault.example.com:8200/v1/transit
         tls: {}
         vaultToken:
           passwordFile: /opt/vault/token
       selector: TemplateKekSelector
       selectorConfig:
         template: "KEK_$(topicName)"
   ```
   The Vault Transit engine must have keys named `KEK_<topicName>` of type `aes256-gcm96`.

   **Record Validation (Apicurio):** Use `examples/k8s/kroxylicious-validation-filter.yaml`:
   ```yaml
   apiVersion: kroxylicious.io/v1alpha1
   kind: KafkaProtocolFilter
   metadata:
     name: my-validation-filter
   spec:
     type: RecordValidation
     configTemplate:
       rules:
         - topicNames:
             - my-topic
           schemaValidationConfig:
             apicurioGlobalId: 1
             apicurioRegistryUrl: http://my-registry-app:8080
             allowNulls: true
             allowEmpty: true
   ```

   **Multi-Tenancy:**
   ```yaml
   apiVersion: kroxylicious.io/v1alpha1
   kind: KafkaProtocolFilter
   metadata:
     name: my-multi-tenant-filter
   spec:
     type: MultiTenant
     configTemplate:
       prefixResourceNameSeparator: "-"
   ```

   For details on filter configuration, use the `configure-kroxylicious-filters` skill.

8. **Create the VirtualKafkaCluster CR.** Ties everything together — the proxy, service, ingress, and filters:
   ```yaml
   apiVersion: kroxylicious.io/v1alpha1
   kind: VirtualKafkaCluster
   metadata:
     name: my-virtual-cluster
   spec:
     proxyRef:
       name: my-proxy
     targetKafkaServiceRef:
       name: my-kafka-service
     ingresses:
       - ingressRef:
           name: my-proxy-ingress
     filterRefs:
       - name: my-encryption-filter
   ```
   Apply and wait for the proxy pods to be ready:
   ```bash
   kubectl wait pods -l app=kroxylicious -n <namespace> --for=condition=Ready --timeout=120s
   ```

9. **Verify end-to-end.** Clients should now connect through the proxy instead of directly to Kafka:
   ```bash
   # Get the proxy bootstrap service
   kubectl get svc -l app=kroxylicious -n <namespace>

   # Test with a Kafka client through the proxy
   kubectl run kafka-test --rm -it --image=quay.io/strimzi/kafka:latest-kafka-3.9.0 -- \
     bin/kafka-console-producer.sh --bootstrap-server <proxy-service>:9092 --topic test-topic

   # Verify topics are accessible
   kubectl run kafka-test --rm -it --image=quay.io/strimzi/kafka:latest-kafka-3.9.0 -- \
     bin/kafka-topics.sh --bootstrap-server <proxy-service>:9092 --list
   ```
   Check proxy logs for errors:
   ```bash
   kubectl logs -l app=kroxylicious -n <namespace> --tail=50
   ```
