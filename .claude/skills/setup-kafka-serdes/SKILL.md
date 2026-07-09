---
name: setup-kafka-serdes
description: Wire Kafka producers and consumers to use Apicurio Registry SerDes (serializers/deserializers). Use when configuring schema-based serialization with Avro, Protobuf, or JSON Schema in Kafka applications.
allowed-tools: Read, Bash, Write, Edit, Grep
---

# Setup Kafka SerDes with Apicurio Registry

Guide for configuring Kafka producers and consumers to use Apicurio Registry for schema-based serialization.

1. **Determine the schema type.** Ask the user which format they use:
   - **Avro** — most common, binary encoding, requires Avro schema files (.avsc)
   - **Protobuf** — binary encoding, requires .proto files
   - **JSON Schema** — JSON encoding with validation against JSON Schema

2. **Add the Maven dependency.** Based on schema type:
   ```xml
   <!-- Avro -->
   <dependency>
     <groupId>io.apicurio</groupId>
     <artifactId>apicurio-registry-avro-serde-kafka</artifactId>
     <version>3.0.0</version>
   </dependency>

   <!-- JSON Schema -->
   <dependency>
     <groupId>io.apicurio</groupId>
     <artifactId>apicurio-registry-jsonschema-serde-kafka</artifactId>
     <version>3.0.0</version>
   </dependency>

   <!-- Protobuf -->
   <dependency>
     <groupId>io.apicurio</groupId>
     <artifactId>apicurio-registry-protobuf-serde-kafka</artifactId>
     <version>3.0.0</version>
   </dependency>
   ```
   For Gradle, use the equivalent `implementation` notation. Always use the latest stable version from Maven Central.

3. **Configure the Kafka producer.** Set these properties (example for Avro):
   ```java
   props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG,
       io.apicurio.registry.serde.avro.AvroKafkaSerializer.class);
   props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG,
       io.apicurio.registry.serde.avro.AvroKafkaSerializer.class);
   props.put("apicurio.registry.url", "http://localhost:8080/apis/registry/v3");
   props.put("apicurio.registry.auto-register", "true");
   ```
   Serializer classes by schema type:
   - Avro: `io.apicurio.registry.serde.avro.AvroKafkaSerializer`
   - JSON Schema: `io.apicurio.registry.serde.jsonschema.JsonSchemaKafkaSerializer`
   - Protobuf: `io.apicurio.registry.serde.protobuf.ProtobufKafkaSerializer`

4. **Configure the Kafka consumer.** Set these properties (example for Avro):
   ```java
   props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG,
       io.apicurio.registry.serde.avro.AvroKafkaDeserializer.class);
   props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG,
       io.apicurio.registry.serde.avro.AvroKafkaDeserializer.class);
   props.put("apicurio.registry.url", "http://localhost:8080/apis/registry/v3");
   ```
   Deserializer classes by schema type:
   - Avro: `io.apicurio.registry.serde.avro.AvroKafkaDeserializer`
   - JSON Schema: `io.apicurio.registry.serde.jsonschema.JsonSchemaKafkaDeserializer`
   - Protobuf: `io.apicurio.registry.serde.protobuf.ProtobufKafkaDeserializer`

5. **Choose an artifact resolver strategy.** This determines how the schema artifact ID is derived:
   - `TopicIdStrategy` (default) — artifact ID = topic name. One schema per topic.
   - `RecordIdStrategy` — artifact ID = full record name (e.g. `com.example.Order`). Multiple record types per topic.
   - `TopicRecordIdStrategy` — artifact ID = `<topic>-<record name>`. Hybrid approach.
   Set via: `props.put("apicurio.registry.artifact-resolver-strategy", "io.apicurio.registry.serde.strategy.RecordIdStrategy");`

6. **Key configuration properties reference:**
   | Property | Default | Description |
   |----------|---------|-------------|
   | `apicurio.registry.url` | (required) | Registry API base URL |
   | `apicurio.registry.auto-register` | `false` | Auto-register schemas on produce |
   | `apicurio.registry.artifact-resolver-strategy` | `TopicIdStrategy` | How artifact ID is derived |
   | `apicurio.registry.artifact.group-id` | (none) | Explicit group ID override |
   | `apicurio.registry.use-id` | `contentId` | ID type in message header (`contentId` or `globalId`) |
   | `apicurio.registry.find-latest` | `false` | Always use latest schema version |
   | `apicurio.registry.headers.enabled` | (varies) | Pass schema reference in Kafka headers |
   | `apicurio.registry.check-period-ms` | `30000` | Schema cache refresh interval |
   | `apicurio.registry.serde.validation-enabled` | `true` | Validate data against schema |

7. **If the registry is secured**, add auth properties:
   ```java
   // OIDC client credentials
   props.put("apicurio.registry.auth.service.token.endpoint",
       "http://keycloak:8080/realms/registry/protocol/openid-connect/token");
   props.put("apicurio.registry.auth.client.id", "my-client");
   props.put("apicurio.registry.auth.client.secret", "my-secret");

   // Or basic auth
   props.put("apicurio.registry.auth.username", "user");
   props.put("apicurio.registry.auth.password", "pass");
   ```

8. **For Quarkus applications**, use `application.properties` instead of programmatic config:
   ```properties
   mp.messaging.outgoing.orders.value.serializer=io.apicurio.registry.serde.avro.AvroKafkaSerializer
   mp.messaging.outgoing.orders.apicurio.registry.url=http://localhost:8080/apis/registry/v3
   mp.messaging.outgoing.orders.apicurio.registry.auto-register=true
   ```

9. **Verify the setup.** Produce a message and check:
   - The schema was auto-registered in the registry: `curl http://localhost:8080/apis/registry/v3/search/artifacts`
   - The consumer can deserialize the message without errors
   - The schema appears in the Registry UI at `http://localhost:8888`
