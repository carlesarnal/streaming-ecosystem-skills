# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A collection of Claude Code skills (not application code) for the **Strimzi + Apicurio Registry + Debezium + Kroxylicious** streaming ecosystem. Apart from the UC1 experiment harness, there is no build system, test suite, or application to run — the repo contains skill definitions (`.claude/skills/*/SKILL.md`) and example Kubernetes/Docker Compose manifests (`examples/`).

## Repository Structure

- `.claude/skills/` — Nine skills that guide Claude through deployment, configuration, and troubleshooting of the streaming stack
- `examples/k8s/` — Kubernetes/OpenShift CRs (Strimzi Kafka, Apicurio Registry, Debezium KafkaConnect/KafkaConnector)
- `examples/docker-compose/full-stack.yaml` — Local dev stack (Kafka KRaft + PostgreSQL + Apicurio Registry + Kroxylicious + Debezium Connect + Registry UI)

## Skills Overview

| Skill | Purpose |
|-------|---------|
| `deploy-stack` | Deploy on Kubernetes/OpenShift using Strimzi, Apicurio, and Debezium operators |
| `deploy-stack-local` | Spin up locally with Docker Compose |
| `configure-kafkasql` | Set up KafkaSQL storage for Apicurio Registry (Kafka journal + SQL snapshots) |
| `connect-debezium-to-registry` | Wire Debezium CDC connectors to use Apicurio for schema management |
| `setup-kafka-serdes` | Configure Kafka producers/consumers with Apicurio SerDes (Avro, Protobuf, JSON Schema) |
| `deploy-kroxylicious` | Deploy Kroxylicious Kafka proxy on K8s/OpenShift with Strimzi integration |
| `configure-kroxylicious-filters` | Configure Kroxylicious filters (encryption, validation, multi-tenancy) |
| `troubleshoot-integration` | Diagnose cross-project issues (schema not found, converter errors, proxy issues) |
| `evolve-event-schema` | Decide whether a schema change can ship safely; produce a verified change proposal |

## Working on Skills

Each skill is a single `SKILL.md` file with YAML frontmatter (`name`, `description`, `allowed-tools`) followed by a numbered step-by-step guide. Skills are conversational — they ask the user questions to determine environment and configuration before generating manifests or code.

When editing skills, keep the interactive question-then-generate pattern: determine environment first (K8s/OpenShift vs Docker, auth mode, schema format), then produce the appropriate configuration. Several skills include OpenShift-specific guidance (Routes instead of Ingress, `oc` commands alongside `kubectl`, SCCs) — maintain this parity when updating.

## Example Manifests

Example YAMLs in `examples/` are referenced by skills as templates. If you update a manifest, check which skills reference it (grep for the filename across `SKILL.md` files) and ensure consistency.

## Experiments

`experiments/uc1-schema-evolution/` measures the value of `evolve-event-schema` (RHAF Use Case 1). Its `answer-key/` must never be visible to an agent under test. If you change a scenario, re-run `fixture/scripts/registry-check.sh` and `fixture/scripts/read-matrix.sh` and update `answer-key/expected-outcomes.md`. Its read-matrix harness is the only buildable code in the repo (Maven, under `fixture/read-matrix/`).
