# Logstash

Logstash — log shipping pipeline from application services to OpenSearch.

## Purpose

Logstash receives structured JSON logs from application services via the Beats protocol
(TCP port 5044) and forwards them to OpenSearch under the `ops-logs-YYYY.MM.dd` index.

## Pipeline Configuration

The active pipeline config is at `infrastructure/logstash/pipeline/logstash.conf`:

```
input  → Beats (port 5044)
filter → add index prefix metadata
output → OpenSearch (port 9200)
```

## Log Shipping Guide

Add `logstash-logback-encoder` to ship structured JSON logs from Spring Boot services:

```kotlin
// build.gradle.kts
implementation("net.logstash.logback:logstash-logback-encoder:7.4")
```

In `src/main/resources/logback-spring.xml`:

```xml
<configuration>
  <appender name="LOGSTASH" class="net.logstash.logback.appender.LogstashTcpSocketAppender">
    <destination>logstash:5044</destination>
    <encoder class="net.logstash.logback.encoder.LogstashEncoder"/>
  </appender>
  <root level="INFO">
    <appender-ref ref="LOGSTASH"/>
  </root>
</configuration>
```

Set the service name field so logs are distinguishable in OpenSearch:

```xml
<customFields>{"service":"my-service-name"}</customFields>
```

## Input Port

| Port | Protocol | Description |
|------|----------|-------------|
| 5044 | TCP | Logstash Beats input (log ingestion) |

## Startup / Shutdown

```bash
docker compose --profile observability up -d logstash
docker compose logs -f logstash

docker compose stop logstash
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Logs not reaching OpenSearch | Logstash not started | Start with `--profile observability` |
| Connection refused on port 5044 | Logstash not ready yet | Wait ~30s for Logstash to initialize pipeline |
| Logs arriving but wrong index | OpenSearch output index pattern | Verify pipeline `output.opensearch.index` pattern |
| No logs from service | Missing Logback appender config | Add `LogstashTcpSocketAppender` to service's `logback-spring.xml` |
