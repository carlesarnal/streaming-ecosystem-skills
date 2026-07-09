---
name: troubleshoot-integration
description: Diagnose common issues in the Strimzi + Apicurio Registry + Debezium streaming stack. Use when encountering errors like schema not found, converter failures, connection refused, deserialization errors, or KafkaSQL startup problems.
allowed-tools: Read, Bash, Grep
---

# Troubleshoot Streaming Stack Integration

Guide for diagnosing and resolving common cross-project issues between Strimzi (Kafka), Apicurio Registry, and Debezium.

1. **Collect symptoms.** Ask the user:
   - Which component is failing (Kafka, Registry, Debezium Connect, application producer/consumer)?
   - What is the error message or behavior?
   - Is this on Kubernetes, OpenShift, or local Docker?
   Detect the platform: `kubectl api-resources | grep -q route.openshift.io && echo "OpenShift" || echo "Kubernetes"`. Use `oc` on OpenShift.

2. **Schema Not Found errors** (`ArtifactNotFoundException`, `404 on schema lookup`):
   - Check the artifact resolver strategy matches between producer and consumer. Default is `TopicIdStrategy` (artifact ID = topic name). If the producer uses `RecordIdStrategy`, the consumer must too.
   - Check the group ID. Default group is `default`. If the producer sets `apicurio.registry.artifact.group-id`, the consumer needs the same.
   - Check `apicurio.registry.auto-register` is `true` on the producer side.
   - Check `apicurio.registry.use-id` matches — both sides must use `contentId` (default) or both use `globalId`.
   - Verify the schema exists: `curl http://<registry>:8080/apis/registry/v3/groups/default/artifacts`
   - Check if the registry URL includes `/apis/registry/v3` — omitting the path is a common mistake.

3. **Debezium Converter errors** (`Converter not found`, `ClassNotFoundException`):
   - **Docker:** Ensure `ENABLE_APICURIO_CONVERTERS=true` is set on the Debezium Connect container. This activates the bundled Apicurio converter JARs.
   - **Kubernetes (Strimzi KafkaConnect):** Ensure the KafkaConnect CR has the Apicurio converter in its `spec.build.plugins`. Check: `kubectl describe kafkaconnect <name>` and look at the build status.
   - Verify the converter class name is correct:
     - Avro: `io.apicurio.registry.utils.converter.AvroConverter`
     - JSON: `io.apicurio.registry.utils.converter.ExtJsonConverter`
   - Check Connect logs: `kubectl logs <connect-pod>` or `docker logs <connect-container>`

4. **Connection Refused / Timeout** (`Connection refused`, `TimeoutException`):
   - **Registry to Kafka (KafkaSQL):** Check `bootstrapServers` value. On K8s: `<kafka-cluster>-kafka-bootstrap.<namespace>.svc:9092` (plain) or `:9093` (TLS). Run: `kubectl get svc -l strimzi.io/cluster=<cluster-name>` to find the correct service.
   - **Connect to Registry:** Check the registry URL in converter config. On K8s, use the service name: `http://<registry-service>.<namespace>.svc:8080/apis/registry/v3`
   - **TLS mismatch:** If Kafka expects TLS and the client sends plaintext (or vice versa), the connection will hang or reset. Check the listener port: 9092 = usually plain, 9093 = usually TLS.
   - **NetworkPolicy:** On K8s/OpenShift, check if a NetworkPolicy blocks traffic between namespaces: `kubectl get networkpolicy -n <namespace>`
   - **OpenShift Routes:** If accessing services externally via Routes, verify the Route exists and is admitted: `oc get routes -n <namespace>`. Check the Route's host matches what the client is using. For TLS Routes (e.g., Kafka `type: route` listener), the client needs the cluster CA cert.

5. **Deserialization errors** (`SerializationException`, `magic byte`, `Unknown magic byte`):
   - The producer and consumer must use the same serializer/deserializer pair. Avro-serialized data cannot be deserialized with the JSON Schema deserializer.
   - Check for `contentId` vs `globalId` mismatch — if the producer writes `contentId` in the message header but the consumer expects `globalId`, deserialization fails.
   - If the topic has a mix of old (non-registry) and new (registry-encoded) messages, the consumer will fail on old messages. Consider resetting offsets or using a new consumer group.

6. **Schema Compatibility errors** (`RuleViolationException`, `409 Conflict`):
   - Check the compatibility rule on the artifact: `curl http://<registry>:8080/apis/registry/v3/groups/<group>/artifacts/<artifactId>/rules`
   - Common cause: adding a required field without a default violates BACKWARD compatibility.
   - To temporarily disable: `curl -X DELETE http://<registry>:8080/apis/registry/v3/groups/<group>/artifacts/<artifactId>/rules/COMPATIBILITY`
   - Better fix: add the field with a default value, or change the compatibility level.

7. **KafkaSQL startup failures** (`Failed to initialize KafkaSQL`, `TopicAuthorizationException`):
   - Check Kafka ACLs: the registry's KafkaUser needs full access to topics `kafkasql-journal`, `kafkasql-snapshots`, and `registry-events`, plus all consumer groups.
   - Check TLS config: if using Strimzi TLS, verify the keystore/truststore secrets exist and match the Kafka cluster CA: `kubectl get secret <secret-name> -o jsonpath='{.data}' | head`
   - Check if the Kafka cluster is ready: `kubectl get kafka <cluster> -o jsonpath='{.status.conditions}'`
   - Check registry logs for the specific error: `kubectl logs <registry-pod> | grep -i error | head -20`

8. **OpenShift-specific issues:**
   - **SCC (Security Context Constraints):** If a pod fails to start with `unable to validate against any security context constraint`, the service account may need a permissive SCC. Check: `oc get scc` and `oc describe pod <pod> | grep -A5 'Security'`. Strimzi and Apicurio operators handle their own SCCs, but custom images may need: `oc adm policy add-scc-to-user anyuid -z <service-account>`
   - **KafkaConnect build fails on OpenShift:** Use `type: imagestream` in the build output instead of `type: docker`. This pushes to OpenShift's internal registry without needing external credentials. Ensure the builder service account has image-push permissions: `oc policy add-role-to-user system:image-builder system:serviceaccount:<namespace>:my-connect-cluster-connect`
   - **Route not resolving:** Check the Route is admitted: `oc get route <name> -o jsonpath='{.status.ingress[0].conditions}'`. If the host is not resolving, verify the OpenShift router is running and the wildcard DNS is configured.
   - **ImagePullBackOff on OpenShift:** If the KafkaConnect image built via imagestream can't be pulled, check the image reference: `oc get is my-connect-cluster -o jsonpath='{.status.dockerImageRepository}'`

9. **Kroxylicious proxy issues:**
   - **Strimzi version mismatch:** Kroxylicious `strimziKafkaRef` requires Strimzi 0.49.0+. Check the Strimzi operator version: `kubectl get deployment strimzi-cluster-operator -o jsonpath='{.spec.template.spec.containers[0].image}'`. If using an older Strimzi, use explicit `bootstrapServers` in the KafkaService CR instead.
   - **FrameOversizedException with TLS/OAuth:** This usually means a protocol mismatch — the proxy expects TLS but the client sends plaintext (or vice versa). Verify the listener configuration matches the client's security protocol.
   - **Records not encrypted/validated:** Check the filter is referenced in `filterRefs` of the VirtualKafkaCluster CR. Filters execute in order — ensure the correct filter name is listed. Check proxy logs: `kubectl logs -l app=kroxylicious -n <namespace> --tail=50 | grep -i filter`
   - **Proxy pod not starting:** Check if the Kroxylicious CRDs are installed: `kubectl get crd kafkaproxies.kroxylicious.io`. Check operator logs: `kubectl logs -l app=kroxylicious-operator --tail=50`
   - **Client can't connect through proxy:** Verify the KafkaProxyIngress service exists: `kubectl get svc -l app=kroxylicious -n <namespace>`. Ensure the client bootstrap server points to the proxy service, not the Kafka service directly.
   - **Vault KMS connection errors:** Check the Vault Transit engine URL is correct and accessible from the proxy pod. Verify the Vault token is mounted and has the `transit/encrypt/*` and `transit/decrypt/*` policies.
   - **Schema validation rejecting valid records:** Verify `apicurioGlobalId` matches the schema ID in the registry: `curl http://<registry>:8080/apis/registry/v3/ids/globalIds/<id>`. Check if `allowNulls` and `allowEmpty` are set appropriately.

10. **Diagnostic commands reference:**
   ```bash
   # K8s/OpenShift: Check all components
   kubectl get kafka,kafkaconnect,kafkaconnector,apicurioregistry3 -n <namespace>

   # K8s/OpenShift: Registry logs
   kubectl logs -l app=<registry-name> -n <namespace> --tail=50

   # K8s/OpenShift: Connect logs
   kubectl logs -l strimzi.io/kind=KafkaConnect -n <namespace> --tail=50

   # K8s/OpenShift: List Kafka topics
   kubectl exec <kafka-pod> -- bin/kafka-topics.sh --bootstrap-server localhost:9092 --list

   # OpenShift: Check Routes
   oc get routes -n <namespace>

   # OpenShift: Get Route URL for the registry
   oc get route <registry-route> -o jsonpath='https://{.spec.host}/apis/registry/v3/system/info'

   # OpenShift: Check operator subscriptions
   oc get subscriptions -n openshift-operators

   # OpenShift: Check CSVs (installed operators)
   oc get csv -n <namespace>

   # Docker: Check all containers
   docker compose ps

   # Docker: Registry logs
   docker compose logs apicurio-registry --tail=50

   # Check registry API
   curl -s http://<registry>:8080/apis/registry/v3/system/info

   # List all schemas in registry
   curl -s http://<registry>:8080/apis/registry/v3/search/artifacts | python3 -m json.tool

   # Check Debezium connector status
   curl -s http://<connect>:8083/connectors/<name>/status | python3 -m json.tool

   # K8s/OpenShift: Kroxylicious proxy status
   kubectl get kafkaproxy,virtualkafkacluster,kafkaservice,kafkaprotocolfilter -n <namespace>

   # K8s/OpenShift: Kroxylicious proxy logs
   kubectl logs -l app=kroxylicious -n <namespace> --tail=50
   ```
