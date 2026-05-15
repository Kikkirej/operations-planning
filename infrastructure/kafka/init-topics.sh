#!/bin/sh
# init-topics.sh — Create Kafka topics declared in topics.yml.
# Runs as an init container (exits 0 on success, non-zero on any failure).
# Usage: init-topics.sh [--replication-factor <n>]
# Env:   KAFKA_BOOTSTRAP_SERVERS  (default: kafka:9092)
#        KAFKA_REPLICATION_FACTOR (default: 1; overridden by --replication-factor arg)
#        TOPICS_FILE              (default: /topics.yml)
#        KAFKA_BIN                (default: /opt/kafka/bin)
set -e

BOOTSTRAP="${KAFKA_BOOTSTRAP_SERVERS:-kafka:9092}"
RF="${KAFKA_REPLICATION_FACTOR:-1}"
TOPICS_FILE="${TOPICS_FILE:-/topics.yml}"
KAFKA_BIN="${KAFKA_BIN:-/opt/kafka/bin}"
MAX_WAIT=60
RETRY_INTERVAL=5

# Parse --replication-factor arg
while [ "$#" -gt 0 ]; do
  case "$1" in
    --replication-factor)
      RF="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ ! -f "$TOPICS_FILE" ]; then
  echo "ERROR: topics file not found: $TOPICS_FILE" >&2
  exit 1
fi

# Wait for Kafka to be ready (max MAX_WAIT seconds)
echo "[init-topics] Waiting for Kafka at $BOOTSTRAP (max ${MAX_WAIT}s) ..."
elapsed=0
until "$KAFKA_BIN/kafka-topics.sh" --bootstrap-server "$BOOTSTRAP" --list > /dev/null 2>&1; do
  if [ "$elapsed" -ge "$MAX_WAIT" ]; then
    echo "ERROR: Kafka not ready after ${MAX_WAIT}s. Giving up." >&2
    exit 1
  fi
  echo "[init-topics]   not ready yet, retrying in ${RETRY_INTERVAL}s ..."
  sleep "$RETRY_INTERVAL"
  elapsed=$((elapsed + RETRY_INTERVAL))
done
echo "[init-topics] Kafka is ready."

CREATED_COUNT=0
FAILED_TOPICS=""

create_topic() {
  local name="$1"
  local partitions="$2"
  local retention="$3"
  local rf_override="$4"
  local effective_rf="${rf_override:-$RF}"

  if [ -z "$name" ]; then return 0; fi

  echo "[init-topics] Creating topic: $name"
  echo "  partitions=$partitions  retention=${retention}ms  replication-factor=$effective_rf"

  if ! "$KAFKA_BIN/kafka-topics.sh" \
    --bootstrap-server "$BOOTSTRAP" \
    --create \
    --if-not-exists \
    --topic "$name" \
    --partitions "$partitions" \
    --replication-factor "$effective_rf" \
    --config "retention.ms=$retention" \
    --config "cleanup.policy=delete"; then
    echo "ERROR: Failed to create topic '$name'" >&2
    FAILED_TOPICS="$FAILED_TOPICS $name"
    return 1
  fi

  # Validate topic exists via --describe
  if ! "$KAFKA_BIN/kafka-topics.sh" \
    --bootstrap-server "$BOOTSTRAP" \
    --describe \
    --topic "$name" > /dev/null 2>&1; then
    echo "ERROR: Topic '$name' created but --describe failed" >&2
    FAILED_TOPICS="$FAILED_TOPICS $name"
    return 1
  fi

  echo "[init-topics]   ✓ $name"
  CREATED_COUNT=$((CREATED_COUNT + 1))
  return 0
}

# Parse topics.yml (pure POSIX sh — no external tools beyond sed)
CURRENT_NAME=""
CURRENT_PARTITIONS=3
CURRENT_RETENTION=3600000
CURRENT_RF=""

while IFS= read -r line; do
  case "$line" in
    \#*) continue ;;
    *"- name:"*)
      create_topic "$CURRENT_NAME" "$CURRENT_PARTITIONS" "$CURRENT_RETENTION" "$CURRENT_RF"
      CURRENT_NAME="$(printf '%s' "$line" | sed 's/.*- name:[[:space:]]*//' | tr -d '"' | tr -d "'")"
      CURRENT_PARTITIONS=3
      CURRENT_RETENTION=3600000
      CURRENT_RF=""
      ;;
    *"partitions:"*)
      val="$(printf '%s' "$line" | sed 's/.*partitions:[[:space:]]*//' | tr -d '"' | cut -d'#' -f1 | tr -d ' ')"
      [ -n "$val" ] && CURRENT_PARTITIONS="$val"
      ;;
    *"retentionMs:"*)
      val="$(printf '%s' "$line" | sed 's/.*retentionMs:[[:space:]]*//' | tr -d '"' | cut -d'#' -f1 | tr -d ' ')"
      [ -n "$val" ] && CURRENT_RETENTION="$val"
      ;;
    *"replicationFactor:"*)
      val="$(printf '%s' "$line" | sed 's/.*replicationFactor:[[:space:]]*//' | tr -d '"' | cut -d'#' -f1 | tr -d ' ')"
      [ -n "$val" ] && CURRENT_RF="$val"
      ;;
  esac
done < "$TOPICS_FILE"

# Flush last parsed topic
create_topic "$CURRENT_NAME" "$CURRENT_PARTITIONS" "$CURRENT_RETENTION" "$CURRENT_RF"

# Summary
echo ""
echo "[init-topics] ─── Summary ──────────────────────────────"
echo "[init-topics] Topics created: $CREATED_COUNT"

if [ -n "$FAILED_TOPICS" ]; then
  echo "[init-topics] FAILED topics:$FAILED_TOPICS" >&2
  echo "[init-topics] Init failed — see errors above." >&2
  exit 1
fi

echo "[init-topics] All topics created and verified successfully."
exit 0
