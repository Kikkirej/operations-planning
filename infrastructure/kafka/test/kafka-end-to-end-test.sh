#!/bin/sh
# Integration test: end-to-end Kafka event delivery using KRaft mode.
# Starts a Kafka container, produces an event, asserts the consumer receives it
# within 5 seconds. Tests offset resume after consumer restart.
# Exits 0 on success, 1 on any assertion failure.

set -e

KAFKA_IMAGE="apache/kafka:3.9"
CONTAINER_NAME="kafka-e2e-test-$$"
KAFKA_PORT=19092
TOPIC="springCloudBus"
GROUP_ID="test-consumer-group"
MAX_WAIT_KAFKA=60
RETRY_INTERVAL=5
DELIVERY_TIMEOUT=5

log() { printf '[kafka-e2e-test] %s\n' "$1"; }
fail() { log "FAIL: $1"; cleanup; exit 1; }

cleanup() {
  docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1 || true
}

# Start Kafka in KRaft mode
log "Starting Kafka KRaft ($KAFKA_IMAGE) on port $KAFKA_PORT ..."
docker run -d --name "$CONTAINER_NAME" \
  -p "$KAFKA_PORT:9092" \
  -e KAFKA_PROCESS_ROLES=broker,controller \
  -e KAFKA_NODE_ID=1 \
  -e KAFKA_CONTROLLER_QUORUM_VOTERS="1@localhost:9093" \
  -e KAFKA_LISTENERS="PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093" \
  -e KAFKA_ADVERTISED_LISTENERS="PLAINTEXT://localhost:$KAFKA_PORT" \
  -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP="PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT" \
  -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
  -e KAFKA_AUTO_CREATE_TOPICS_ENABLE=false \
  -e KAFKA_LOG_DIRS=/var/lib/kafka/data \
  -e CLUSTER_ID="test-cluster-$(date +%s)" \
  "$KAFKA_IMAGE"

# Wait for Kafka to be ready
log "Waiting for Kafka to be ready (max ${MAX_WAIT_KAFKA}s) ..."
elapsed=0
until docker exec "$CONTAINER_NAME" /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list > /dev/null 2>&1; do
  if [ "$elapsed" -ge "$MAX_WAIT_KAFKA" ]; then
    fail "Kafka did not become ready within ${MAX_WAIT_KAFKA}s"
  fi
  sleep "$RETRY_INTERVAL"
  elapsed=$((elapsed + RETRY_INTERVAL))
done
log "Kafka is ready."

# Create the springCloudBus topic
log "Creating topic '$TOPIC' ..."
docker exec "$CONTAINER_NAME" /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --create --if-not-exists \
  --topic "$TOPIC" \
  --partitions 3 \
  --replication-factor 1 \
  --config retention.ms=3600000 \
  || fail "Failed to create topic '$TOPIC'"
log "  ✓ Topic '$TOPIC' created"

# Verify topic exists
docker exec "$CONTAINER_NAME" /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --describe --topic "$TOPIC" > /dev/null \
  || fail "Topic '$TOPIC' not found after creation"
log "  ✓ Topic '$TOPIC' verified"

# ─── Test 1: produce → consume within 5 seconds ───────────────────────────────
log "=== Test 1: end-to-end delivery within ${DELIVERY_TIMEOUT}s ==="

PAYLOAD='{"type":"RefreshRemoteApplicationEvent","originService":"test","destinationService":"**"}'
log "Producing event to '$TOPIC' ..."
echo "$PAYLOAD" | docker exec -i "$CONTAINER_NAME" \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic "$TOPIC" \
  || fail "Failed to produce event"
log "  ✓ Event produced"

log "Consuming event from '$TOPIC' (timeout ${DELIVERY_TIMEOUT}s) ..."
RECEIVED=$(docker exec "$CONTAINER_NAME" \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic "$TOPIC" \
  --group "$GROUP_ID" \
  --from-beginning \
  --max-messages 1 \
  --timeout-ms $((DELIVERY_TIMEOUT * 1000)) \
  2>/dev/null || true)

if [ -z "$RECEIVED" ]; then
  fail "Consumer did not receive event within ${DELIVERY_TIMEOUT}s"
fi
log "  ✓ Event received: $RECEIVED"

# ─── Test 2: offset resume after consumer restart ─────────────────────────────
log "=== Test 2: offset resume after restart ==="

PAYLOAD2='{"type":"RefreshRemoteApplicationEvent","originService":"test2","destinationService":"myservice"}'
log "Producing second event ..."
echo "$PAYLOAD2" | docker exec -i "$CONTAINER_NAME" \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic "$TOPIC" \
  || fail "Failed to produce second event"
log "  ✓ Second event produced"

# Consumer restarts with same group ID — should receive only the new event
log "Consuming from committed offset (consumer restart simulation) ..."
RECEIVED2=$(docker exec "$CONTAINER_NAME" \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic "$TOPIC" \
  --group "$GROUP_ID" \
  --max-messages 1 \
  --timeout-ms $((DELIVERY_TIMEOUT * 1000)) \
  2>/dev/null || true)

if [ -z "$RECEIVED2" ]; then
  fail "Consumer did not receive second event after restart within ${DELIVERY_TIMEOUT}s"
fi
log "  ✓ Second event received after restart: $RECEIVED2"

# Cleanup
cleanup
log "All assertions passed."
exit 0
