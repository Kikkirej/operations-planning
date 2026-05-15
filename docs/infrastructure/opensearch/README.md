# OpenSearch

OpenSearch 2.x — log storage and search backend for the platform observability stack.

## Purpose

OpenSearch stores structured log data shipped from Logstash. Logs are indexed daily
under the pattern `ops-logs-YYYY.MM.dd`. OpenSearch Dashboards provides a UI for
log search and visualization.

## Index Management

Logs follow the naming convention: `ops-logs-YYYY.MM.dd`

To list current indices:

```bash
curl http://localhost:9200/_cat/indices?v
```

Default retention: 30 days (configure via Index Lifecycle Management policy in Dashboards).

To delete indices older than 30 days manually:

```bash
curl -X DELETE http://localhost:9200/ops-logs-$(date -d '31 days ago' +%Y.%m.%d)
```

## OpenSearch Dashboards Access

```bash
open http://localhost:5601
```

On first access, create the default index pattern under:
**Stack Management → Index Patterns → Create index pattern → `ops-logs-*`**

## Security Note

`DISABLE_SECURITY_PLUGIN=true` is set in the development configuration. This disables
TLS and authentication for OpenSearch. **Never use this setting in production.** For
production, configure the OpenSearch security plugin with TLS certificates and user
authentication.

## Configuration Reference

| Variable | Value | Description |
|----------|-------|-------------|
| `DISABLE_SECURITY_PLUGIN` | `true` (dev only) | Disables TLS and auth |
| `discovery.type` | `single-node` | Single-node mode for dev |

## Startup / Shutdown

```bash
docker compose --profile observability up -d opensearch
curl http://localhost:9200/_cluster/health

docker compose stop opensearch
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| OpenSearch fails to start | `vm.max_map_count` too low | Run: `sudo sysctl -w vm.max_map_count=262144` |
| No logs indexed | Logstash not running or not connected | Check `docker compose logs logstash`; verify Beats input on port 5044 |
| Index pattern missing in Dashboards | Not created after first start | Create `ops-logs-*` pattern in Dashboards Stack Management |
| Disk full | Old indices not cleaned | Delete old indices or configure ILM rollover policy |
