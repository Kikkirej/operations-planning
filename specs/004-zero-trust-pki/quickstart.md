# Quickstart: Zero Trust PKI & Secrets Setup

## Prerequisites

- Docker Engine + Docker Compose
- OpenSSL (`openssl version` — available on Linux/macOS by default)
- `sudo` access (for `/etc/hosts` entries only)

---

## First-Time Setup (New Developer)

Run the single setup script from the repo root:

```sh
cd deployment/compose
./setup.sh
```

The script does the following in order:

1. **Generates certificates** — creates `infrastructure/certs/trust/local-ca.crt` (Platform CA) and `infrastructure/certs/server/local.{crt,key}` (wildcard server cert). Skipped if certs already exist.
2. **Copies `.env.example` to `.env`** — skipped if `.env` already exists.
3. **Validates secrets** — lists every secret still set to `CHANGE_ME_BEFORE_USE`.
4. **Adds `/etc/hosts` entries** — adds `auth.ops.local`, `admin.ops.local`, `config.ops.local` (requires sudo).

After running `setup.sh`, open `.env` and replace every `CHANGE_ME_BEFORE_USE` value with a real secret. Then:

```sh
docker compose up --build
```

---

## Browser Certificate Trust (One-Time)

After certs are generated, import the Platform CA into your browser so `*.ops.local` domains show no certificate warnings.

**Firefox (Linux)**:

```sh
sudo apt-get install -y libnss3-tools  # if not already installed

for dir in ~/.config/mozilla/firefox/*/; do
  certutil -A -n "ops.local Dev CA" -t "CT,," \
    -i infrastructure/certs/trust/local-ca.crt \
    -d "sql:$dir"
done
```

Restart Firefox. No further steps needed — all `*.ops.local` domains are trusted.

**Chrome / Chromium (Linux)**:

```sh
certutil -A -n "ops.local Dev CA" -t "CT,," \
  -i infrastructure/certs/trust/local-ca.crt \
  -d ~/.pki/nssdb
```

---

## Certificate Renewal

Certificates expire after 2 years (server cert) or 10 years (CA). To regenerate:

```sh
./setup.sh --renew
```

This regenerates the server cert (and optionally the CA if `--renew-ca` is also passed). After renewal:

1. Rebuild images: `docker compose build`
2. Restart Traefik: `docker compose restart traefik`
3. Re-import CA into browser if the CA was regenerated.

---

## Secret Validation (Any Time)

To check for missing secrets without running the full setup:

```sh
./setup.sh --check
```

Lists all `.env` variables still set to `CHANGE_ME_BEFORE_USE`.

---

## Adding a New Service

1. Add the CA import block to the service's `Dockerfile` runtime stage (see `contracts/pki-interface.md`).
2. Declare any new secrets in `deployment/compose/.env.example` with `CHANGE_ME_BEFORE_USE` placeholder.
3. That's it — the service inherits trust automatically on the next `docker build`.

---

## Production (AKS)

In AKS, replace the dev CA cert in `infrastructure/certs/trust/local-ca.crt` with your production CA cert before building images. Server certs are provided by cert-manager (or Azure Key Vault) and mounted as Kubernetes Secrets at the same paths Traefik expects.

Secret values come from Kubernetes Secrets or Azure Key Vault — same environment variable names as the local `.env` file.
