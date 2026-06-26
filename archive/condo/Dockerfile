ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base
LABEL dind.project="true"

WORKDIR /coverage_reloaded

# Install Docker daemon + docker-compose for Docker-in-Docker.
# The repo's docker-compose.yml starts postgresdb and redis containers that
# bin/prepare.js interacts with via docker-compose exec.
# Images are pulled through the docker-cache registry mirror on the mining-net
# network (http://docker-cache:5000), which proxies Docker Hub.
# We use docker-compose-plugin (v2) from Docker's official repo because the
# Debian Bullseye docker-compose (v1.25) doesn't support version '3.8' format
# used by the repo's docker-compose.yml.
RUN apt-get update && apt-get install -y docker.io && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian bullseye stable' > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y docker-compose-plugin

# Install Python deps for kmigrator.py (Django-based migration tool).
# The base image manages Python via uv, which marks the interpreter as externally
# managed — uv pip install --system refuses to modify it. Instead we create a uv
# virtual environment, install Django/psycopg2 there, and prepend the venv's bin
# directory to PATH so python3 resolves to the venv's Python (which knows its own
# site-packages). The venv's Python binary is a symlink to the uv-managed one, so
# just symlinking /usr/local/bin/python3 to it won't activate the venv.
RUN uv venv /coverage_reloaded/.venv && \
    uv pip install --python /coverage_reloaded/.venv/bin/python "Django>=3.0.6" "psycopg2-binary>=2.8.5"
ENV PATH="/coverage_reloaded/.venv/bin:${PATH}"

COPY ./repo /coverage_reloaded/repo
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
COPY ./install-and-run-manual.sh /coverage_reloaded/install-and-run-manual.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run-manual.sh