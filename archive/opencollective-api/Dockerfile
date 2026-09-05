ARG NODE_VERSION=20
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

# ── System dependencies ──────────────────────────────────────
# PostgreSQL 16 from official repo (debian bullseye ships PG 13)
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
    && echo "deb [ signed-by=/usr/share/keyrings/postgresql.gpg ] http://apt.postgresql.org/pub/repos/apt bullseye-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update && apt-get install -y \
      postgresql-16 \
      postgresql-16-postgis-3 \
      libssl1.1 \
      libssl-dev \
      --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

COPY ./repo /coverage_reloaded/repo
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh
