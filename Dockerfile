##########################
# Building image
##########################
# XXX golang1.13 broken for now (thanks etcd and https://tip.golang.org/doc/go1.13#version-validation)
FROM        --platform=$BUILDPLATFORM golang:1.12-buster                                                  AS builder

# Install dependencies and tools
ARG         DEBIAN_FRONTEND="noninteractive"
ENV         TERM="xterm" LANG="C.UTF-8" LC_ALL="C.UTF-8"
RUN         apt-get update                                                                                > /dev/null
RUN         apt-get install -y --no-install-recommends \
                make=4.2.1-1.2 \
                git=1:2.20.1-2 \
                ca-certificates=20190110                                                                  > /dev/null
RUN         update-ca-certificates

WORKDIR     /build

ARG         TARGETPLATFORM

# Unbound plugin, version 0.0.5, XXX doesn't compile
#RUN         apt-get install libunbound8=1.9.0-2 libunbound-dev=1.9.0-2                                    > /dev/null
#ARG         UNBOUND_VERSION=266ea7f686ac4259bec30b6ec9d17773b1dc7ec9

#WORKDIR     /go/src/github.com/coredns/unbound
#RUN         git clone https://github.com/coredns/unbound.git .
#RUN         git checkout $UNBOUND_VERSION

# CoreDNS v1.6.3
ARG         COREDNS_VERSION=37b9550d62685d450553437776978518ccca631b

WORKDIR     /go/src/github.com/coredns/coredns
RUN         git clone https://github.com/coredns/coredns.git .
RUN         git checkout $COREDNS_VERSION
#RUN         printf "unbound:github.com/coredns/unbound\n" >> plugin.cfg
#RUN         sed -i'' -e "s,trace:trace,,g" plugin.cfg
RUN         arch=${TARGETPLATFORM#*/} && \
            env GOOS=linux GOARCH=${arch%/*} make CHECKS= all
            # env GOPATH=/go CGO_ENABLED=1 GOOS=linux GOARCH=${arch%/*} make -e CHECKS= all

# Lego, slightly more recent than 3.0.2, so to have go 1.13 support
ARG         LEGO_VERSION=e225f8d334bf823eb220cf70e8d54a9612a1bc2c

WORKDIR     /go/src/github.com/go-acme/lego
RUN         git clone https://github.com/go-acme/lego.git .
RUN         git checkout $LEGO_VERSION
RUN         arch=${TARGETPLATFORM#*/} && \
            env GOOS=linux GOARCH=${arch%/*} make build

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

# Get relevant bits from builder
COPY        --from=builder /etc/ssl/certs                             /etc/ssl/certs
COPY        --from=builder /go/src/github.com/coredns/coredns/coredns /bin/coredns
COPY        --from=builder /go/src/github.com/go-acme/lego/dist/lego  /bin/lego

# Get relevant local files into cwd
COPY        runtime .

# Create user, set permissions
# 002 so that both owner (eg: USER) and group (eg: in case we want to run as root) can manipulate the content of these folders
# This only matters if this is not mounted from the host, using root
RUN         addgroup --system --gid $BUILD_GID $BUILD_GROUP && \
            adduser --system --disabled-login --no-create-home --home /nonexistent --shell /bin/false \
                --gecos "in dockerfile user" \
                --ingroup $BUILD_GROUP \
                --uid $BUILD_UID \
                $BUILD_USER && \
            umask 0002 && \
            mkdir /config && \
            mkdir /data && \
            mkdir /certs && \
            chown $BUILD_UID:root /config && \
            chown $BUILD_UID:root /data && \
            chown $BUILD_UID:root /certs && \
            chown -R $BUILD_UID:root . && \
            chmod -R a+r .

USER        $BUILD_USER

ENV         OVERWRITE_CONFIG=""
ENV         OVERWRITE_DATA=""
ENV         OVERWRITE_CERTS=""

ENV         DOMAIN=""
ENV         EMAIL=""
ENV         STAGING=""

ENV         DNS_PORT=1053
ENV         TLS_PORT=1853
ENV         HTTPS_PORT=1443
ENV         UPSTREAM_SERVERS="tls://1.1.1.1"
ENV         UPSTREAM_NAME="cloudflare-dns.com"

EXPOSE      $DNS_PORT/udp
EXPOSE      $TLS_PORT
EXPOSE      $HTTPS_PORT

VOLUME      /config
VOLUME      /data
VOLUME      /certs

ENTRYPOINT  ["./entrypoint.sh"]
