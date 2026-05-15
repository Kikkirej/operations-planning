# Traefik API Gateway

Traefik v3 — reverse proxy and edge router. All inbound external traffic flows through Traefik.

## Purpose

Traefik routes external HTTP/HTTPS requests to registered services using Docker label-based
dynamic routing for Compose and IngressRoute CRDs for Kubernetes. It handles TLS termination
(self-signed certificates for local dev). Rate limiting is explicitly out of scope.

## Docker Label Routing Guide

Add these labels to any service container to make it reachable through Traefik:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.<service-name>.rule=Host(`<service-name>.ops.local`)"
  - "traefik.http.routers.<service-name>.entrypoints=websecure"
  - "traefik.http.routers.<service-name>.tls=true"
  - "traefik.http.services.<service-name>.loadbalancer.server.port=<port>"
```

Replace `<service-name>` with a unique identifier (e.g. `my-api`) and `<port>` with
the container's listening port.

## Local TLS Setup

Traefik uses a self-signed certificate resolver in development mode. Add the hostnames
to `/etc/hosts` on your workstation:

```
127.0.0.1  auth.ops.local config.ops.local admin.ops.local
```

Browsers will show a certificate warning — click through or add the cert to your trust store.

## Kubernetes IngressRoute

In Kubernetes, declare an `IngressRoute` CRD in the service's Helm chart:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-service
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`my-service.ops.local`)
      kind: Rule
      services:
        - name: my-service
          port: 8080
```

## Startup / Shutdown

```bash
docker compose up -d traefik

# Dashboard (insecure, local dev only)
open http://localhost:8080/dashboard/

docker compose stop traefik
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Route returns 404 | `traefik.enable=true` label missing | Add required labels to container |
| TLS error in browser | Host not in `/etc/hosts` | Add hostname to `/etc/hosts` |
| Service not in Traefik dashboard | Container not on `app-net` network | Verify container is on the `app-net` network |
| Redirect loop | `web` → `websecure` redirect misconfigured | Check `entryPoints.web.http.redirections` in `traefik.yml` |
