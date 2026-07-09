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
   - Is this on Kubernetes or local Docker?

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
   - **NetworkPolicy:** On K8s, check if a NetworkPolicy blocks traffic between namespaces: `kubectl get networkpolicy -n <namespace>`

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

8. **Diagnostic commands reference:**
   ```bash
   # K8s: Check all components
   kubectl get kafka,kafkaconnect,kafkaconnector,apicurioregistry3 -n <namespace>

   # K8s: Registry logs
   kubectl logs -l app=<registry-name> -n <namespace> --tail=50

   # K8s: Connect logs
   kubectl logs -l strimzi.io/kind=KafkaConnect -n <namespace> --tail=50

   # K8s: List Kafka topics
   kubectl exec <kafka-pod> -- bin/kafka-topics.sh --bootstrap-server localhost:9092 --list

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
   ```
