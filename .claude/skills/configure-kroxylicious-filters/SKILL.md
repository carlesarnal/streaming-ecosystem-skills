---
name: configure-kroxylicious-filters
description: Configure Kroxylicious proxy filters for record encryption (Vault/AWS KMS), schema validation (Apicurio Registry), multi-tenancy, and OAuth validation. Use when adding or modifying filters on an existing Kroxylicious deployment.
allowed-tools: Read, Bash, Write, Edit
---

# Configure Kroxylicious Filters

Guide for configuring Kroxylicious `KafkaProtocolFilter` CRs for specific use cases. Filters intercept Kafka protocol messages as they pass through the proxy and can transform, validate, or encrypt records.

1. **Determine the use case.** Ask the user:
   - Which filter type: Record Encryption, Record Validation, Multi-Tenancy, or OAuth Bearer Validation?
   - Is Kroxylicious already deployed? If not, use the `deploy-kroxylicious` skill first.
   - Get the namespace and VirtualKafkaCluster name.

2. **Record Encryption** — encrypts record values using envelope encryption (DEK encrypted by KEK in a KMS). Only values are encrypted; keys, headers, and timestamps remain plaintext. Null values pass through unencrypted (required for compacted topic tombstones).

   **With HashiCorp Vault:**
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
         vaultTransitEngineUrl: https://vault:8200/v1/transit
         tls: {}
         vaultToken:
           passwordFile: /opt/vault/token
       selector: TemplateKekSelector
       selectorConfig:
         template: "KEK_$(topicName)"
   ```
   Prerequisites:
   - Vault Transit secrets engine enabled: `vault secrets enable transit`
   - KEK keys created for each topic: `vault write -f transit/keys/KEK_my-topic type=aes256-gcm96`
   - Vault token mounted as a Secret into the proxy pod

   See `examples/k8s/kroxylicious-encryption-filter.yaml` for a complete example including AWS KMS.

   **With AWS KMS:**
   ```yaml
   apiVersion: kroxylicious.io/v1alpha1
   kind: KafkaProtocolFilter
   metadata:
     name: my-encryption-filter-aws
   spec:
     type: RecordEncryption
     configTemplate:
       kms: AwsKmsService
       kmsConfig:
         endpointUrl: https://kms.us-east-1.amazonaws.com
         accessKey:
           passwordFile: /opt/aws/access-key
         secretKey:
           passwordFile: /opt/aws/secret-key
         region: us-east-1
       selector: TemplateKekSelector
       selectorConfig:
         template: "alias/KEK_$(topicName)"
   ```
   Prerequisites:
   - AWS KMS keys created with aliases matching the template pattern
   - AWS credentials mounted as Secrets

   **KEK rotation:** After rotating a KEK in the KMS, existing DEKs continue to work. New DEKs will be encrypted with the new KEK material. For immediate rotation across all records, perform a rolling restart of Kroxylicious. By default, DEKs are refreshed within ~1 hour.

3. **Record Validation** — validates that record values (or keys) conform to a schema registered in Apicurio Registry. Non-conforming records are rejected at produce time.

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
             - another-topic
           schemaValidationConfig:
             apicurioGlobalId: 1
             apicurioRegistryUrl: http://my-registry-app:8080
             allowNulls: true
             allowEmpty: true
   ```
   See `examples/k8s/kroxylicious-validation-filter.yaml` for a complete example.

   The filter can extract the schema global ID from:
   - The `apicurioGlobalId` config (static, as shown above)
   - The Apicurio `globalId` record header (dynamic, set by producer SerDes)
   - The initial bytes of the serialized content (Apicurio wire format)

   Prerequisites:
   - Apicurio Registry deployed and accessible from the proxy pod
   - Schema registered in Apicurio with a known global ID
   - Verify the schema exists: `curl http://<registry>:8080/apis/registry/v3/ids/globalIds/<id>`

4. **Multi-Tenancy** — isolates tenants on a shared Kafka cluster by automatically prefixing topic names, consumer group IDs, and transactional IDs.

   ```yaml
   apiVersion: kroxylicious.io/v1alpha1
   kind: KafkaProtocolFilter
   metadata:
     name: tenant-a-filter
   spec:
     type: MultiTenant
     configTemplate:
       prefixResourceNameSeparator: "-"
   ```
   Create a separate VirtualKafkaCluster per tenant, each with its own MultiTenant filter. The tenant prefix is derived from the VirtualKafkaCluster name. A client connecting to `tenant-a` virtual cluster and producing to topic `orders` will actually write to `tenant-a-orders` on the physical cluster.

5. **OAuth Bearer Validation** — validates OAuth tokens presented by Kafka clients using a JWKS endpoint.

   ```yaml
   apiVersion: kroxylicious.io/v1alpha1
   kind: KafkaProtocolFilter
   metadata:
     name: my-oauth-filter
   spec:
     type: OauthBearerValidation
     configTemplate:
       jwksEndpointUrl: https://keycloak:8443/realms/kafka/protocol/openid-connect/certs
   ```
   This filter validates SASL/OAUTHBEARER tokens against the configured JWKS endpoint. The Kafka client must be configured with `sasl.mechanism=OAUTHBEARER`.

6. **Attach filters to a VirtualKafkaCluster.** After creating the filter CR(s), reference them in the VirtualKafkaCluster:
   ```yaml
   spec:
     filterRefs:
       - name: my-encryption-filter
       - name: my-validation-filter
   ```
   Filters execute in the order listed. Apply the update:
   ```bash
   kubectl apply -f virtual-cluster.yaml -n <namespace>
   ```
   The proxy picks up filter changes automatically — no restart needed.

7. **Verify the filter is active.** Check proxy logs for filter initialization:
   ```bash
   kubectl logs -l app=kroxylicious -n <namespace> --tail=50 | grep -i filter
   ```
   Test by producing a record through the proxy and verifying the expected behavior:
   - **Encryption:** Consume directly from Kafka (bypassing proxy) — the record value should be ciphertext
   - **Validation:** Produce a record that violates the schema — it should be rejected
   - **Multi-Tenancy:** List topics on the physical cluster — they should have the tenant prefix
   - **OAuth:** Connect with invalid credentials — the client should be rejected with an authentication error
