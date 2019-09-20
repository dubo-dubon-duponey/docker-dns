##########################
# Building image
##########################
# XXX golang1.3 broken for now (thanks etcd and https://tip.golang.org/doc/go1.13#version-validation)
FROM        --platform=$BUILDPLATFORM golang:1.12-buster                                                  AS builder

# Install dependencies and tools
ARG         DEBIAN_FRONTEND="noninteractive"
ENV         TERM="xterm" LANG="C.UTF-8" LC_ALL="C.UTF-8"
RUN         apt-get update                                                                                > /dev/null
RUN         apt-get install -y --no-install-recommends \
                git=1:2.20.1-2 \
                ca-certificates=20190110                                                                  > /dev/null
RUN         update-ca-certificates

WORKDIR     /build

# v1.6.3
ARG         COREDNS_VERSION=37b9550d62685d450553437776978518ccca631b
ARG         TARGETPLATFORM

# Checkout and build
WORKDIR     /go/src/github.com/coredns/coredns

RUN         git clone https://github.com/coredns/coredns.git .
RUN         git checkout $COREDNS_VERSION
RUN         arch=${TARGETPLATFORM#*/} && \
            env GOOS=linux GOARCH=${arch%/*} make CHECKS= all

#######################
# Running image
#######################
FROM        debian:buster-slim

LABEL       dockerfile.copyright="Dubo Dubon Duponey <dubo-dubon-duponey@jsboot.space>"

ENV         TERM="xterm" LANG="C.UTF-8" LC_ALL="C.UTF-8"

WORKDIR     /dubo-dubon-duponey

# Build time variable
ARG         BUILD_USER=dubo-dubon-duponey
ARG         BUILD_UID=1000
ARG         BUILD_GROUP=$BUILD_USER
ARG         BUILD_GID=$BUILD_UID

ARG         CONFIG=/config
ARG         DATA=/data

# Get relevant bits from builder
COPY        --from=builder /etc/ssl/certs /etc/ssl/certs
COPY        --from=builder /go/src/github.com/coredns/coredns/coredns /bin/coredns

# Get relevant local files into cwd
COPY        runtime .

# Set links
RUN         mkdir $CONFIG && mkdir $DATA && \
            chown $BUILD_UID:$BUILD_GID $CONFIG && chown $BUILD_UID:$BUILD_GID $DATA && chown -R $BUILD_UID:$BUILD_GID . && \
            ln -sf /dev/stdout access.log && \
            ln -sf /dev/stderr error.log

# Create user
RUN         addgroup --system --gid $BUILD_GID $BUILD_GROUP && \
            adduser --system --disabled-login --no-create-home --home /nonexistent --shell /bin/false \
                --gecos "in dockerfile user" \
                --ingroup $BUILD_GROUP \
                --uid $BUILD_UID \
                $BUILD_USER

USER        $BUILD_USER

ENV         DNS_PORT=1053
ENV         TLS_PORT=1853
ENV         UPSTREAM_SERVERS="tls://1.1.1.1 tls://1.0.0.1"
ENV         UPSTREAM_NAME="cloudflare-dns.com"
ENV         OVERWRITE_CONFIG=""

EXPOSE      $DNS_PORT/udp
EXPOSE      $TLS_PORT

VOLUME      $CONFIG
VOLUME      $DATA

ENTRYPOINT  ["./entrypoint.sh"]
