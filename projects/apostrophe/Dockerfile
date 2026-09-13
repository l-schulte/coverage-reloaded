ARG NODE_VERSION=24
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

# Apostrophe's test suite talks to a real MongoDB on localhost:27017. The
# project changed its Mongo driver on 2024-04-04: before that commit it used
# ``mongodb@^3.6.6`` (driver 3.6/3.7), which cannot speak to MongoDB 5.0+;
# afterwards it uses ``@apostrophecms/emulate-mongo-3-driver`` on driver 6.x.
# Both eras' CI ran the official Docker Hub ``mongo`` images (via the
# supercharge/mongodb-github-action, then explicitly ``mongo:<version>``).
# We therefore install both engines natively so install-and-run.sh can pick the
# one matching the checked-out commit's driver, mirroring mongo:4.4 and mongo:7.
#
# Both engines come from the official MongoDB tarballs rather than the apt
# repository: the base image's Debian security-pool migration makes the apt
# gnupg dependency unsatisfiable, and the tarballs are the same upstream builds
# the mongo:4.4 / mongo:7 images are assembled from. The Debian 10 build of
# 4.4 and the Debian 11 build of 7.0 both link the libssl1.1 that bullseye ships.
RUN curl -fsSL https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-debian10-4.4.29.tgz -o /tmp/mongodb-4.4.tgz \
    && tar -xzf /tmp/mongodb-4.4.tgz --strip-components=2 -C /usr/local/bin \
       mongodb-linux-x86_64-debian10-4.4.29/bin/mongod \
    && mv /usr/local/bin/mongod /usr/local/bin/mongod-4.4 \
    && chmod +x /usr/local/bin/mongod-4.4 \
    && rm /tmp/mongodb-4.4.tgz

RUN curl -fsSL https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-debian11-7.0.18.tgz -o /tmp/mongodb-7.0.tgz \
    && tar -xzf /tmp/mongodb-7.0.tgz --strip-components=2 -C /usr/local/bin \
       mongodb-linux-x86_64-debian11-7.0.18/bin/mongod \
    && mv /usr/local/bin/mongod /usr/local/bin/mongod-7.0 \
    && chmod +x /usr/local/bin/mongod-7.0 \
    && rm /tmp/mongodb-7.0.tgz

# uploadfs requires an image processor (sharp, or ImageMagick as fallback). sharp
# is an optional dependency and can fail to install for a given run, in which
# case uploadfs probes PATH for ImageMagick's `identify` and aborts with "No
# supported image processor found" if absent (e.g. commit 6915b839, 2023-08-01).
# Installing imagemagick guarantees the documented fallback is always available.
RUN apt-get update \
    && apt-get install -y --no-install-recommends imagemagick \
    && rm -rf /var/lib/apt/lists/*

COPY ./repo /coverage_reloaded/repo_disk
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh
