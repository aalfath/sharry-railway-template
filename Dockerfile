# Sharry on Railway: the official upstream image, pinned by version and digest,
# plus a small start script (start.sh). No volume on this service: accounts,
# shares and file contents live in the bundled Railway PostgreSQL.
FROM eikek0/sharry:v1.17.0@sha256:e70cf90528c1e1d8c991e0f3c1e5e76a121e68152e262cbeebdb0de84ca8b4f6

COPY start.sh /opt/railway/start.sh

# Upstream runs as uid 10001; the app writes nothing to disk, so keep it.
USER 10001
EXPOSE 9090

ENTRYPOINT ["/opt/railway/start.sh"]
