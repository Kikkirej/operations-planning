# Kafka

Apache Kafka 3.9 — event streaming platform running in KRaft mode (no ZooKeeper).

## Purpose

Kafka provides the asynchronous event transport for the operations platform.
Spring Cloud Bus uses Kafka to broadcast config-refresh events (`RefreshRemoteApplicationEvent`)
to all subscribed services. Auto-topic creation is disabled; all topics must be declared
in `infrastructure/kafka/topics.yml`.

## KRaft Configuration

Key environment variables for KRaft mode:

| Variable | Value | Description |
|----------|-------|-------------|
| `KAFKA_PROCESS_ROLES` | `broker,controller` | Single-node combined mode |
| `KAFKA_NODE_ID` | `1` | Unique node ID (must match VOTERS) |
| `KAFKA_CONTROLLER_QUORUM_VOTERS` | `1@kafka:9093` | Controller quorum config |
| `KAFKA_AUTO_CREATE_TOPICS_ENABLE` | `false` | Prevents accidental topic creation |
| `KAFKA_LOG_DIRS` | `/var/lib/kafka/data` | Persistent data volume mount point |

## Topic Management

### Adding New Topics

1. Edit `infrastructure/kafka/topics.yml`:

```yaml
topics:
  - name: my-domain-events
    partitions: 3
    retentionMs: 604800000   # 7 days
    cleanupPolicy: delete
    offsetReset: earliest
    purpose: "Domain events for my-service"
```

2. On next platform start, `kafka-init` creates the topic automatically.

3. For immediate creation on a running cluster:

```bash
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --create --if-not-exists \
  --topic my-domain-events \
  --partitions 3 \
  --replication-factor 1 \
  --config retention.ms=604800000
```

### Verifying Topics

```bash
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --list

docker compose exec kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --describe --topic springCloudBus
```

## Consumer Group Conventions

- Set `group.id` to the consuming service's Spring application name
- Use manual commit (`enable.auto.commit=false`) for at-least-once delivery
- Set `auto.offset.reset=earliest` for domain event topics (replay on restart)
- Set `auto.offset.reset=latest` for ephemeral/infrastructure topics (e.g., `springCloudBus`)

## Startup / Shutdown

```bash
docker compose up -d kafka kafka-init
# kafka-init exits 0 after all topics are created

docker compose stop kafka
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Topic not found on first use | `kafka-init` did not run or failed | Check `docker compose logs kafka-init`; verify `topics.yml` syntax |
| `kafka-init` exits non-zero | Topic creation failed | Check Kafka is healthy; verify `KAFKA_BOOTSTRAP_SERVERS` env var |
| Messages not consumed | Wrong `group.id` or offset | Check consumer `group.id` matches service name; verify `auto.offset.reset` |
| KRaft startup failure | Stale `kafka-data` volume with old cluster ID | Remove volume: `docker volume rm <project>_kafka-data` |
| Auto-created topics appear | `KAFKA_AUTO_CREATE_TOPICS_ENABLE` not set to false | Set env var in docker-compose.yml |
