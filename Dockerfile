##########################
# Building image
##########################
FROM        --platform=$BUILDPLATFORM golang:1.13-buster                                                  AS builder

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

# Checkout logspout upstream, install glide and run it
WORKDIR     /go/src/github.com/coredns/coredns
RUN         git clone https://github.com/coredns/coredns.git .
RUN         git checkout $COREDNS_VERSION

# Build it
RUN         arch=${TARGETPLATFORM#*/} && \
            env GOOS=linux GOARCH=${arch%/*} make CHECKS= all

#######################
# Running image
#######################
FROM        debian:buster-slim

LABEL       dockerfile.copyright="Dubo Dubon Duponey <dubo-dubon-duponey@jsboot.space>"

ARG         DEBIAN_FRONTEND="noninteractive"
ENV         TERM="xterm" LANG="C.UTF-8" LC_ALL="C.UTF-8"

WORKDIR     /dubo-dubon-duponey

# Get relevant bits from builder
COPY        --from=builder /etc/ssl/certs /etc/ssl/certs
COPY        --from=builder /go/src/github.com/coredns/coredns/coredns /bin/coredns

# Build time variable
ARG         BUILD_USER=dubo-dubon-duponey
ARG         BUILD_UID=1042
ARG         BUILD_GROUP=$BUILD_USER
ARG         BUILD_GID=$BUILD_UID
ARG         BUILD_CONFIG=/config
ARG         BUILD_PORT=1053

# Create user
RUN         addgroup --system --gid $BUILD_GID $BUILD_GROUP && \
            adduser --system --disabled-login --no-create-home --home /nonexistent --shell /bin/false \
                --gecos "in dockerfile user" \
                --ingroup $BUILD_GROUP \
                --uid $BUILD_UID \
                $BUILD_USER

USER        $BUILD_USER

# Symkink logs
#RUN         ln -sf /dev/stdout access.log && \
#            ln -sf /dev/stderr error.log

COPY        entrypoint.sh .
COPY        coredns.conf $BUILD_CONFIG/

EXPOSE      $BUILD_PORT $BUILD_PORT/udp

VOLUME      $BUILD_CONFIG

ENTRYPOINT  ["./entrypoint.sh"]
