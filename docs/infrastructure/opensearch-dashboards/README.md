# OpenSearch Dashboards

OpenSearch Dashboards 2.x — log visualization and search UI for the observability stack.

## Purpose

OpenSearch Dashboards provides a browser-based UI for exploring logs indexed in OpenSearch.
It runs as part of the optional `observability` profile alongside Jaeger, OpenSearch, and Logstash.

## Enabling the Observability Profile

```bash
# Docker Compose
docker compose --profile observability up -d

# Helm
helm install core-infrastructure deployment/helm/core-infrastructure \
  -f deployment/helm/core-infrastructure/values.observability.yaml
```

## Accessing the Dashboards UI

```bash
open http://localhost:5601
```

No login is required in the development configuration (`DISABLE_SECURITY_PLUGIN=true`).

## Creating the Default Index Pattern

On first access after a clean start:

1. Navigate to **Stack Management → Index Patterns**
2. Click **Create index pattern**
3. Enter `ops-logs-*` as the pattern
4. Select `@timestamp` as the time field
5. Click **Create index pattern**

The index pattern is now available in **Discover** for log search and in **Visualize** for charts.

## Log Search

- Navigate to **Discover** and select `ops-logs-*` index pattern
- Use the query bar for KQL queries: `service: "eureka-server" AND level: "ERROR"`
- Set the time range in the top-right time picker

## Startup / Shutdown

```bash
docker compose --profile observability up -d opensearch opensearch-dashboards
open http://localhost:5601

docker compose stop opensearch-dashboards
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| UI not loading | OpenSearch not healthy yet | Wait for OpenSearch health check to pass; check `docker compose logs opensearch` |
| "No index patterns" message | Index pattern not created | Follow the "Creating the Default Index Pattern" steps above |
| No data in Discover | Logstash not shipping logs | Verify Logstash is running and services have Logback appender configured |
| Login page shown | Security plugin enabled | In dev, set `DISABLE_SECURITY_PLUGIN=true`; in prod, configure security plugin credentials |
| Dashboards unreachable | Wrong OpenSearch host | Verify `OPENSEARCH_HOSTS` env var points to `["http://opensearch:9200"]` |
