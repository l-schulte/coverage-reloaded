ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

# ── System dependencies ──────────────────────────────────────
# nasm + yasm: both needed by isa-l native addon (node-gyp build).
#   isa-l's configure.ac prefers yasm and falls back to nasm; some build
#   paths call yasm directly.
# libcap-dev: needed by the project's native addons
# gnupg: needed for MongoDB repo key import
RUN apt-get update && apt-get install -y \
      nasm \
      yasm \
      libcap-dev \
      gnupg \
      --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# ── MongoDB 7.0 ──────────────────────────────────────────────
# The project used MongoDB throughout most of its history (driver 3.2.7 → 3.7.4).
# The mongod.conf is minimal (bindIp + wiredTiger + dbPath) and compatible with
# MongoDB 3.2 through 7.0.  A single MongoDB 7.0 install serves all eras.
RUN curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc \
      | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg \
    && echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] http://repo.mongodb.org/apt/debian bullseye/mongodb-org/7.0 main" \
      > /etc/apt/sources.list.d/mongodb-org-7.0.list \
    && apt-get update && apt-get install -y \
      mongodb-org \
      --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# ── PostgreSQL 12 ────────────────────────────────────────────
# The project uses centos/postgresql-12-centos7 in production and postgres:15 for
# SSL tests.  The pg npm driver evolved from 8.0.3 → 8.20.0, all compatible with
# PostgreSQL 12+.  We install PostgreSQL 12 from the official repo.
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
    && echo "deb [ signed-by=/usr/share/keyrings/postgresql.gpg ] http://apt.postgresql.org/pub/repos/apt bullseye-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update && apt-get install -y \
      postgresql-12 \
      --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

COPY ./repo /coverage_reloaded/repo
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh