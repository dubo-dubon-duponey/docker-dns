##########################
# Building image
##########################
FROM        --platform=$BUILDPLATFORM golang:1.13-buster                                                  AS builder

# Install dependencies and tools
ARG         DEBIAN_FRONTEND="noninteractive"
ENV         TERM="xterm" LANG="C.UTF-8" LC_ALL="C.UTF-8"
RUN         apt-get update                                                                                > /dev/null
RUN         apt-get install -y --no-install-recommends \
                virtualenv=15.1.0+ds-2 \
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

# CoreDNS v1.6.4
ARG         COREDNS_VERSION=b139ba34f370a4937bf76e7cc259a26f1394a91d


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
ENV         TERM="xterm" LANG="C.UTF-8" LC_ALL="C.UTF-8"

# Build args
ARG         BUILD_UID=1000

# Labels build args
ARG         BUILD_CREATED="1976-04-14T17:00:00-07:00"
ARG         BUILD_URL="https://github.com/dubodubonduponey/nonexistent"
ARG         BUILD_DOCUMENTATION="https://github.com/dubodubonduponey/nonexistent"
ARG         BUILD_SOURCE="https://github.com/dubodubonduponey/nonexistent"
ARG         BUILD_VERSION="unknown"
ARG         BUILD_REVISION="unknown"
ARG         BUILD_VENDOR="dubodubonduponey"
ARG         BUILD_LICENSES="MIT"
ARG         BUILD_REF_NAME="dubodubonduponey/nonexistent"
ARG         BUILD_TITLE="A DBDBDP image"
ARG         BUILD_DESCRIPTION="So image. Much DBDBDP. Such description."

LABEL       org.opencontainers.image.created="$BUILD_CREATED"
LABEL       org.opencontainers.image.authors="Dubo Dubon Duponey <dubo-dubon-duponey@farcloser.world>"
LABEL       org.opencontainers.image.url="$BUILD_URL"
LABEL       org.opencontainers.image.documentation="$BUILD_DOCUMENTATION"
LABEL       org.opencontainers.image.source="$BUILD_SOURCE"
LABEL       org.opencontainers.image.version="$BUILD_VERSION"
LABEL       org.opencontainers.image.revision="$BUILD_REVISION"
LABEL       org.opencontainers.image.vendor="$BUILD_VENDOR"
LABEL       org.opencontainers.image.licenses="$BUILD_LICENSES"
LABEL       org.opencontainers.image.ref.name="$BUILD_REF_NAME"
LABEL       org.opencontainers.image.title="$BUILD_TITLE"
LABEL       org.opencontainers.image.description="$BUILD_DESCRIPTION"

# Get universal relevant files
COPY        runtime  /
COPY        --from=builder /etc/ssl/certs                             /etc/ssl/certs

# Create a restriced user account (no shell, no home, disabled)
# Setup directories and permissions
# The user can access the files as the owner, and root can access as the group (that way, --user root still works without caps).
# Write is granted, although that doesn't really matter in term of security
RUN         adduser --system --no-create-home --home /nonexistent --gecos "in dockerfile user" \
                --uid $BUILD_UID \
                dubo-dubon-duponey \
              && chmod 550 entrypoint.sh \
              && chown $BUILD_UID:root entrypoint.sh \
              && mkdir -p /config \
              && mkdir -p /data \
              && mkdir -p /certs \
              && chown -R $BUILD_UID:root /config \
              && chown -R $BUILD_UID:root /data \
              && chown -R $BUILD_UID:root /certs \
              && find /config -type d -exec chmod -R 770 {} \; \
              && find /config -type f -exec chmod -R 660 {} \; \
              && find /data -type d -exec chmod -R 770 {} \; \
              && find /data -type f -exec chmod -R 660 {} \; \
              && find /certs -type d -exec chmod -R 770 {} \; \
              && find /certs -type f -exec chmod -R 660 {} \;

# Default volumes for data and certs, since these are expected to be writable
VOLUME      /data
VOLUME      /certs

# Downgrade to system user
USER        dubo-dubon-duponey

ENTRYPOINT  ["/entrypoint.sh"]

##########################################
# Image specifics
##########################################

# Get relevant bits from builder
COPY        --from=builder /go/src/github.com/coredns/coredns/coredns /bin/coredns
COPY        --from=builder /go/src/github.com/go-acme/lego/dist/lego  /bin/lego

ENV         DOMAIN="somewhere.tld"
ENV         EMAIL="dubo-dubon-duponey@farcloser.world"
ENV         STAGING=""

ENV         DNS_PORT=1053
ENV         TLS_PORT=1853
ENV         HTTPS_PORT=1443
ENV         UPSTREAM_SERVER_1="tls://1.1.1.1"
ENV         UPSTREAM_SERVER_2="tls://1.0.0.1"
ENV         UPSTREAM_NAME="cloudflare-dns.com"

# NOTE: this will not be updated at runtime and will always EXPOSE default values
# Either way, EXPOSE does not do anything, except function as a documentation helper
EXPOSE      $DNS_PORT/udp
EXPOSE      $TLS_PORT/tcp
EXPOSE      $HTTPS_PORT/tcp
