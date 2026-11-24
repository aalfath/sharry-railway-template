# Changelog

## 1.17.0-railway.1 (2026-11-24)

First release of the Railway template.

- Sharry v1.17.0, official image `eikek0/sharry:v1.17.0@sha256:e70cf90528c1e1d8c991e0f3c1e5e76a121e68152e262cbeebdb0de84ca8b4f6`.
- Railway PostgreSQL holds accounts, shares and file contents.
- Generated admin password and server secret; open sign-up off; header proxy login kept off.
- The start script waits up to 150 s for PostgreSQL with a 3 s timeout per attempt, so a deploy that starts while Postgres restarts can't hang.
- JVM heap, CPU count and checksum workers sized from the container's cgroup (fits 0.5 GB).
