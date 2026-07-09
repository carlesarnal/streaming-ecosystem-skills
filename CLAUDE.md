# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A collection of Claude Code skills (not application code) for the **Strimzi + Apicurio Registry + Debezium** streaming ecosystem. There is no build system, test suite, or application to run — the repo contains skill definitions (`.claude/skills/*/SKILL.md`) and example Kubernetes/Docker Compose manifests (`examples/`).

## Repository Structure

- `.claude/skills/` — Six skills that guide Claude through deployment, configuration, and troubleshooting of the streaming stack
- `examples/k8s/` — Kubernetes CRs (Strimzi Kafka, Apicurio Registry, Debezium KafkaConnect/KafkaConnector)
- `examples/docker-compose/full-stack.yaml` — Local dev stack (Kafka KRaft + PostgreSQL + Apicurio Registry + Debezium Connect)

## Skills Overview

| Skill | Purpose |
|-------|---------|
| `deploy-stack` | Deploy on Kubernetes using Strimzi, Apicurio, and Debezium operators |
| `deploy-stack-local` | Spin up locally with Docker Compose |
| `configure-kafkasql` | Set up KafkaSQL storage for Apicurio Registry (Kafka journal + SQL snapshots) |
| `connect-debezium-to-registry` | Wire Debezium CDC connectors to use Apicurio for schema management |
| `setup-kafka-serdes` | Configure Kafka producers/consumers with Apicurio SerDes (Avro, Protobuf, JSON Schema) |
| `troubleshoot-integration` | Diagnose cross-project issues (schema not found, converter errors, connection failures) |

## Working on Skills

Each skill is a single `SKILL.md` file with YAML frontmatter (`name`, `description`, `allowed-tools`) followed by a numbered step-by-step guide. Skills are conversational — they ask the user questions to determine environment and configuration before generating manifests or code.

When editing skills, keep the interactive question-then-generate pattern: determine environment first (K8s vs Docker, auth mode, schema format), then produce the appropriate configuration.

## Example Manifests

Example YAMLs in `examples/` are referenced by skills as templates. If you update a manifest, check which skills reference it (grep for the filename across `SKILL.md` files) and ensure consistency.
