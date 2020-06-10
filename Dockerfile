#######################
# Extra builder for healthchecker
#######################
ARG           BUILDER_BASE=dubodubonduponey/base:builder
ARG           RUNTIME_BASE=dubodubonduponey/base:runtime
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-healthcheck

ARG           GIT_REPO=github.com/dubo-dubon-duponey/healthcheckers
ARG           GIT_VERSION=51ebf8ca3d255e0c846307bf72740f731e6210c3

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
RUN           arch="${TARGETPLATFORM#*/}"; \
              env GOOS=linux GOARCH="${arch%/*}" go build -v -ldflags "-s -w" \
                -o /dist/boot/bin/dns-health ./cmd/dns

##########################
# Builder custom
##########################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder

# CoreDNS v1.6.9
ARG           GIT_REPO=github.com/coredns/coredns
ARG           GIT_VERSION=1766568398e3120c85d44f5c6237a724248b652e
# CoreDNS client
# ARG           COREDNS_CLIENT_VERSION=af9fb99c870aa91af3f48d61d3565de31e078a89
# Lego 3.7.0
ARG           LEGO_REPO=github.com/go-acme/lego
ARG           LEGO_VERSION=e774e180a51b11a3ba9f3c1784b1cbc7dce1322b
# Unbound, 0.0.6
ARG           UNBOUND_REPO=github.com/coredns/unbound
ARG           UNBOUND_VERSION=d78fc1102044102fde63044ce13f55f07d0e1c87


# Dependencies necessary for unbound
RUN           apt-get update -qq && \
              apt-get install -qq --no-install-recommends \
                libunbound-dev=1.9.0-2+deb10u2 \
                nettle-dev=3.4.1-1 \
                libevent-dev=2.1.8-stable-4 && \
              apt-get -qq autoremove      && \
              apt-get -qq clean           && \
              rm -rf /var/lib/apt/lists/* && \
              rm -rf /tmp/*               && \
              rm -rf /var/tmp/*
#                dnsutils=1:9.11.5.P4+dfsg-5.1 \

# Unbound
WORKDIR       $GOPATH/src/$UNBOUND_REPO
RUN           git clone git://$UNBOUND_REPO .
RUN           git checkout $UNBOUND_VERSION

# CoreDNS client
# https://github.com/coredns/client/blob/master/Makefile
#WORKDIR       $GOPATH/src/github.com/coredns/client
#RUN           git clone https://github.com/coredns/client.git .
#RUN           git checkout $COREDNS_CLIENT_VERSION

#RUN           arch="${TARGETPLATFORM#*/}"; \
#              env GOOS=linux GOARCH="${arch%/*}" go build -v -ldflags "-s -w" -o dist/dnsgrpc ./cmd/dnsgrpc

# Lego
# https://github.com/go-acme/lego/blob/master/Makefile
WORKDIR       $GOPATH/src/$LEGO_REPO
RUN           git clone git://$LEGO_REPO .
RUN           git checkout $LEGO_VERSION

# hadolint ignore=DL4006
RUN           arch="${TARGETPLATFORM#*/}"; \
              tag_name=$(git tag -l --contains HEAD | head -n 1); \
              env GOOS=linux GOARCH="${arch%/*}" go build -v -ldflags "-s -w -X main.version=${tag_name:-$(git rev-parse HEAD)}" -o /dist/boot/bin/lego ./cmd/lego

# https://github.com/coredns/coredns/blob/master/Makefile
WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
RUN           set -eu; \
              arch=${TARGETPLATFORM#*/}; \
              commit="$(git describe --dirty --always)"; \
              if [ "$TARGETPLATFORM" = "$BUILDPLATFORM" ]; then \
                printf "unbound:github.com/coredns/unbound\n" >> plugin.cfg; \
                CGO_ENABLED=1; \
                triplet="$(gcc -dumpmachine)"; \
                go generate coredns.go; \
                mkdir -p /dist/boot/lib; \
                cp /usr/lib/"$triplet"/libunbound.so.8    /dist/boot/lib; \
                cp /lib/"$triplet"/libpthread.so.0        /dist/boot/lib; \
                cp /lib/"$triplet"/libc.so.6              /dist/boot/lib; \
                cp /usr/lib/"$triplet"/libevent-2.1.so.6  /dist/boot/lib; \
              fi; \
              env GOOS=linux GOARCH="${arch%/*}" CGO_ENABLED=$CGO_ENABLED go build -v -ldflags="-s -w -X github.com/coredns/coredns/coremain.GitCommit=$commit" -o /dist/boot/bin/coredns

COPY          --from=builder-healthcheck /dist/boot/bin /dist/boot/bin
RUN           chmod 555 /dist/boot/bin/*

#######################
# Running image
#######################
# hadolint ignore=DL3006
FROM          $RUNTIME_BASE

# Get relevant bits from builder
COPY          --from=builder --chown=$BUILD_UID:root /dist .

ENV           DOMAIN=""
ENV           EMAIL="dubo-dubon-duponey@farcloser.world"
ENV           UPSTREAM_SERVER_1=""
ENV           UPSTREAM_SERVER_2=""
ENV           UPSTREAM_NAME=""
ENV           STAGING=""

ENV           DNS_PORT=1053
ENV           TLS_PORT=1853
ENV           HTTPS_PORT=1443
ENV           GRPC_PORT=5553
ENV           METRICS_PORT=9253

# NOTE: this will not be updated at runtime and will always EXPOSE default values
# Either way, EXPOSE does not do anything, except function as a documentation helper
EXPOSE        $DNS_PORT/udp
EXPOSE        $TLS_PORT/tcp
EXPOSE        $HTTPS_PORT/tcp
EXPOSE        $GRPC_PORT/tcp
EXPOSE        $METRICS_PORT/tcp

# Lego just needs /certs to work
VOLUME        /certs

ENV           HEALTHCHECK_URL="127.0.0.1:$DNS_PORT"
ENV           HEALTHCHECK_QUESTION=healthcheck-dns.farcloser.world
ENV           HEALTHCHECK_TYPE=udp

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD dns-health || exit 1
