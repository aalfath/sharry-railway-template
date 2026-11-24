#!/bin/bash
# Railway start script for Sharry. Maps Railway's settings onto Sharry's
# SHARRY_* environment variables (env wins over the conf file), sizes the JVM
# from the container's cgroup, waits for PostgreSQL, then execs upstream's
# launcher. Every failure exits non-zero so Railway's ON_FAILURE restarts it.
set -euo pipefail

log() { echo "sharry-railway: $*"; }
die() { echo "sharry-railway: ERROR: $*" >&2; exit 1; }

# --- Required generated secrets (template variables) -----------------------
ADMIN_USER="${SHARRY_ADMIN_USER:-admin}"
ADMIN_PASSWORD="${SHARRY_ADMIN_PASSWORD:-}"
SERVER_SECRET="${SHARRY_SERVER_SECRET:-}"
[ "${#ADMIN_PASSWORD}" -ge 16 ] || die "SHARRY_ADMIN_PASSWORD is missing or shorter than 16 characters; refusing to start with a weak admin login."
[ "${#SERVER_SECRET}" -ge 32 ] || die "SHARRY_SERVER_SECRET is missing or shorter than 32 characters; refusing to start (it signs every login token)."

# Upstream reads the *proxy* login settings from SHARRY_BACKEND_AUTH_INTERNAL_*
# (v1.17.0 ConfigValues.scala), so SHARRY_BACKEND_AUTH_INTERNAL_ENABLED=true
# would also switch on header-trusting proxy login (anyone could log in as
# admin with an X-Valid-User header). Never let it through.
unset SHARRY_BACKEND_AUTH_INTERNAL_ENABLED

# --- Database (Railway PostgreSQL over the private network) ----------------
: "${PGHOST:?PGHOST is not set; it should reference the Postgres service}"
PGPORT="${PGPORT:-5432}"
: "${PGDATABASE:?PGDATABASE is not set}"
: "${PGUSER:?PGUSER is not set}"
: "${PGPASSWORD:?PGPASSWORD is not set}"
export SHARRY_BACKEND_JDBC_URL="jdbc:postgresql://${PGHOST}:${PGPORT}/${PGDATABASE}"
export SHARRY_BACKEND_JDBC_USER="$PGUSER"
export SHARRY_BACKEND_JDBC_PASSWORD="$PGPASSWORD"

# A sibling's private DNS name can take a minute to resolve on a first deploy,
# and a connect to a restarting Postgres can hang without an answer, so every
# attempt gets its own 3 s timeout and the whole wait a 150 s deadline.
log "waiting for PostgreSQL at ${PGHOST}:${PGPORT}..."
deadline=$((SECONDS + 150))
until timeout 3 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$PGHOST" "$PGPORT" 2>/dev/null; do
  [ "$SECONDS" -ge "$deadline" ] && die "PostgreSQL at ${PGHOST}:${PGPORT} did not answer within 150 s."
  sleep 2
done
log "PostgreSQL is reachable."

# --- Network ----------------------------------------------------------------
export SHARRY_BIND_ADDRESS="0.0.0.0"
export SHARRY_BIND_PORT="${PORT:-9090}"
# Share links, mails and cookies use base-url. Use the public domain when it is
# a plain hostname; otherwise keep upstream's localhost default, which makes
# Sharry derive the URL from the request's X-Forwarded-* headers.
if [[ "${RAILWAY_PUBLIC_DOMAIN:-}" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
  export SHARRY_BASE_URL="https://${RAILWAY_PUBLIC_DOMAIN}"
fi

# --- Accounts: generated admin, no open sign-up ----------------------------
# The fixed login module creates this account as admin on its first login.
export SHARRY_BACKEND_AUTH_FIXED_ENABLED=true
export SHARRY_BACKEND_AUTH_FIXED_USER="$ADMIN_USER"
export SHARRY_BACKEND_AUTH_FIXED_PASSWORD="$ADMIN_PASSWORD"
export SHARRY_BACKEND_AUTH_SERVER_SECRET="$SERVER_SECRET"
export SHARRY_BACKEND_SIGNUP_MODE="${SHARRY_BACKEND_SIGNUP_MODE:-closed}"
export SHARRY_BACKEND_FILES_DEFAULT_STORE="${SHARRY_BACKEND_FILES_DEFAULT_STORE:-database}"
export SHARRY_LOGGING_FORMAT="${SHARRY_LOGGING_FORMAT:-Plain}"

# --- JVM sized from the cgroup (Railway shows the host's CPUs and RAM) -----
mem_limit=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)
if [[ "$mem_limit" =~ ^[0-9]+$ ]]; then mem_mb=$((mem_limit / 1048576)); else mem_mb=2048; fi
[ "$mem_mb" -gt 8192 ] && mem_mb=8192
heap_mb=$((mem_mb * 45 / 100))
[ "$heap_mb" -lt 96 ] && heap_mb=96
[ "$heap_mb" -gt 2048 ] && heap_mb=2048
cpus=1
read -r quota period < /sys/fs/cgroup/cpu.max 2>/dev/null || quota=max
if [[ "${quota:-max}" =~ ^[0-9]+$ ]] && [ "${period:-0}" -gt 0 ]; then
  cpus=$(( (quota + period - 1) / period ))
fi
[ "$cpus" -lt 1 ] && cpus=1
[ "$cpus" -gt 4 ] && cpus=4
export SHARRY_BACKEND_COMPUTE_CHECKSUM_USE_DEFAULT=false
export SHARRY_BACKEND_COMPUTE_CHECKSUM_PARALLEL="${SHARRY_BACKEND_COMPUTE_CHECKSUM_PARALLEL:-1}"
export JAVA_OPTS="-Xms64m -Xmx${heap_mb}m -Xss512k -XX:MaxMetaspaceSize=160m -XX:ReservedCodeCacheSize=64m -XX:MaxDirectMemorySize=64m -XX:+UseSerialGC -XX:ActiveProcessorCount=${cpus} -XX:+ExitOnOutOfMemoryError -Djava.security.egd=file:/dev/./urandom ${SHARRY_EXTRA_JAVA_OPTS:-}"
log "memory limit ${mem_mb} MB, heap ${heap_mb} MB, ${cpus} CPU(s); base URL ${SHARRY_BASE_URL:-from request headers}"

exec /opt/sharry/bin/sharry-restserver
