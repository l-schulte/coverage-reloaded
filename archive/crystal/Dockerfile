ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

# ── System dependencies ──────────────────────────────────────
# gnupg: needed for PostgreSQL repo key import
# libreadline-dev: required by some node native addons
RUN apt-get update && apt-get install -y \
      gnupg \
      libreadline-dev \
      --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# ── PostgreSQL 14 from official repo ─────────────────────────
# Debian bullseye ships PG 13; we need PG 14 for logical replication.
# CI tests against PG 12, 14, 18; we pick 14 as a safe default.
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
    && echo "deb [ signed-by=/usr/share/keyrings/postgresql.gpg ] http://apt.postgresql.org/pub/repos/apt bullseye-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update && apt-get install -y \
      postgresql-14 \
      postgresql-server-dev-14 \
      --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# ── wal2json extension (logical replication decoding) ────────
# Required by some tests that use PostgreSQL logical replication.
RUN cd /tmp \
    && git clone https://github.com/eulerto/wal2json -b master --single-branch \
    && cd wal2json \
    && git checkout wal2json_2_6 \
    && make && make install \
    && cd / && rm -rf /tmp/wal2json

COPY ./repo /coverage_reloaded/repo
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh
