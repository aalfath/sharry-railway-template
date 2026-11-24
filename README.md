[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/sharry-1?utm_medium=integration&utm_source=button&utm_campaign=sharry)

# Sharry on Railway

One-click Railway template for [Sharry](https://github.com/eikek/sharry) **v1.17.0**, a self-hosted file-sharing server: signed-in users upload files and share them by link (with optional password, expiry and view limit), and anyone can send files to you through an alias upload page.

## What it deploys

| Service | Source | What it does |
|---|---|---|
| `Sharry` | this repo (`Dockerfile`, `FROM eikek0/sharry:v1.17.0@sha256:e70cf905…`) | Web UI and REST API on Railway's `PORT`, health check `/api/v2/open/info/version` |
| `Postgres` | Railway PostgreSQL | Accounts, shares **and file contents** (Sharry's default database file store), on the Postgres volume |

Only one volume is used (Postgres), so the template fits Railway's Free plan.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `SHARRY_ADMIN_PASSWORD` | `${{secret(24)}}` | Password of the `admin` account. Find it in the Sharry service's Variables tab. |
| `SHARRY_SERVER_SECRET` | `${{secret(48)}}` | Signs login tokens. Changing it logs everyone out. |
| `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE` | references to `Postgres` | Private-network database connection. |
| `PORT` | `9090` | Port Sharry listens on. |

Nothing to fill in at deploy time. The start script (`start.sh`):

- refuses to start (exit 1) if the admin password is shorter than 16 characters or the server secret shorter than 32;
- turns on upstream's fixed `admin` login (the account is created as admin on its first login) and keeps **open sign-up off** (`closed`);
- never sets `SHARRY_BACKEND_AUTH_INTERNAL_ENABLED`: in v1.17.0 that variable also switches on header-based proxy login, which would let anyone log in as admin with an `X-Valid-User` header;
- waits for PostgreSQL, sets the base URL from `RAILWAY_PUBLIC_DOMAIN`, and sizes the JVM heap (45 % of the memory limit), CPU count and checksum workers from the container's cgroup, so it runs inside Railway's 0.5 GB Free-plan limit. An out-of-memory error exits non-zero so Railway restarts it.

Any other Sharry setting can be added as a `SHARRY_*` variable on the service (see [upstream's configuration docs](https://eikek.github.io/sharry/doc/configure)), for example `SHARRY_BACKEND_SIGNUP_MODE=invite`, `SHARRY_BACKEND_SHARE_MAX_SIZE=5G` or the `SHARRY_BACKEND_MAIL_*` SMTP settings. Extra JVM flags go in `SHARRY_EXTRA_JAVA_OPTS`.

## After deploy

1. Open the Sharry service's public URL.
2. Log in as `admin` with `SHARRY_ADMIN_PASSWORD`.
3. Create more users under *Accounts*, or switch sign-up to `invite` and hand out invitation keys.

## Memory

Tested at 0.5 GB RAM / 1 vCPU: idle about 175 MB, about 230 MB while a 300 MB file uploads through the web UI's resumable (tus) upload. The legacy single-request multipart API (`POST /api/v2/sec/upload`) buffers the whole request, so at 0.5 GB send large files through the tus endpoint (as the web UI does) or give the service more RAM.

## Updates

The `Sharry` service builds from this repo's `main` branch. When we bump the pinned Sharry version, Railway shows an "update available" notice in your project, and you choose when to apply it. Read [CHANGELOG.md](CHANGELOG.md) first: breaking changes are listed at the top of each entry. Sharry runs its own database migrations on start.

## Licence

Sharry is GPL-3.0 (© eikek and contributors). This wrapper only adds a start script around the official image.
