# Monetra — Self-Hosting Installer

> Web-based accounting software for Austria & Germany — host it on your own server.

## Requirements

- Linux server (Ubuntu 22.04+ recommended)
- [Docker](https://docs.docker.com/get-docker/) + [Docker Compose v2](https://docs.docker.com/compose/install/)
- A valid **license key** (available at [monetro.at](https://www.monetro.at))

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/aphex13/monetro-install/main/install.sh \
  | bash -s -- --key=MON-XXXX-XXXX-XXXX
```

The installer will:

1. Validate your license key
2. Authenticate with the container registry
3. Create `/opt/monetra/.env` with secure random secrets
4. Pull Docker images and start all services
5. Open the app at `http://localhost`

## Custom Install Directory

```bash
curl -fsSL https://raw.githubusercontent.com/aphex13/monetro-install/main/install.sh \
  | bash -s -- --key=MON-XXXX-XXXX-XXXX --dir=/srv/monetra
```

## Manual Setup

```bash
# 1. Download compose file
curl -fsSL https://raw.githubusercontent.com/aphex13/monetro-install/main/docker-compose.selfhost.yml \
  -o docker-compose.yml

# 2. Create .env
cp .env.example .env
nano .env

# 3. Start
docker compose up -d
```

## Configuration (`.env`)

| Variable | Required | Description |
|---|---|---|
| `POSTGRES_PASSWORD` | ✓ | Database password (auto-generated) |
| `JWT_SECRET` | ✓ | JWT signing secret (auto-generated) |
| `JWT_REFRESH_SECRET` | ✓ | JWT refresh secret (auto-generated) |
| `ENCRYPTION_KEY` | ✓ | AES-256 encryption key (auto-generated) |
| `ADMIN_EMAIL` | ✓ | First admin account email |
| `ADMIN_PASSWORD` | ✓ | First admin account password |
| `FRONTEND_URL` | ✓ | Public URL of your app (e.g. `https://accounting.mycompany.com`) |
| `ALLOWED_ORIGINS` | ✓ | CORS origins (same as `FRONTEND_URL`) |
| `HTTP_PORT` | — | Port to expose (default: `80`) |
| `SMTP_HOST` | — | SMTP server for email delivery |
| `SMTP_USER` | — | SMTP username |
| `SMTP_PASS` | — | SMTP password |
| `SMTP_FROM` | — | From address (e.g. `Monetra <noreply@mycompany.com>`) |
| `ANTHROPIC_API_KEY` | — | AI assistant (get key at console.anthropic.com) |
| `AI_PROVIDER` | — | `anthropic` (default) |

## Reverse Proxy (Domain + HTTPS)

To use a custom domain with HTTPS, place a reverse proxy in front.

**nginx example:**

```nginx
server {
    listen 443 ssl;
    server_name accounting.mycompany.com;

    ssl_certificate     /etc/letsencrypt/live/accounting.mycompany.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/accounting.mycompany.com/privkey.pem;

    location / {
        proxy_pass http://localhost:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Then update `.env`:
```
FRONTEND_URL=https://accounting.mycompany.com
ALLOWED_ORIGINS=https://accounting.mycompany.com
```

And restart: `docker compose up -d`

## Update

```bash
docker compose -C /opt/monetra pull
docker compose -C /opt/monetra up -d
```

## Common Commands

```bash
# View logs
docker compose -C /opt/monetra logs -f

# Stop
docker compose -C /opt/monetra down

# Backup database
docker exec monetra-db-1 pg_dump -U monetra monetra > backup.sql

# Restore database
cat backup.sql | docker exec -i monetra-db-1 psql -U monetra monetra
```

## Stack

- **Backend** — Node.js + Express + TypeScript + Prisma
- **Frontend** — React 18 + Vite + TailwindCSS
- **Database** — PostgreSQL 16
- **Container Registry** — GitHub Container Registry (ghcr.io)

## License

MIT — see [LICENSE](LICENSE)

---

Questions? [support@monetro.at](mailto:support@monetro.at)
