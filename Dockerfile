##########################
# Builder custom
# Custom steps required to build this specific image
##########################
FROM          --platform=$BUILDPLATFORM dubodubonduponey/base:builder                                   AS builder

# CoreDNS v1.6.4
ARG           COREDNS_VERSION=b139ba34f370a4937bf76e7cc259a26f1394a91d
# CoreDNS client
ARG           COREDNS_CLIENT_VERSION=af9fb99c870aa91af3f48d61d3565de31e078a89
# Lego 3.1.0
ARG           LEGO_VERSION=776850ffc87bf916d480833d0a996210a8b1d641
# Unbound, 0.0.6
ARG           UNBOUND_VERSION=d78fc1102044102fde63044ce13f55f07d0e1c87

# Dependencies necessary for unbound
RUN           apt-get install -y \
                libunbound-dev=1.9.0-2 \
                nettle-dev=3.4.1-1 \
                libevent-dev=2.1.8-stable-4 \
                > /dev/null
#                dnsutils=1:9.11.5.P4+dfsg-5.1 \

# Unbound
WORKDIR       $GOPATH/src/github.com/coredns/unbound
RUN           git clone https://github.com/coredns/unbound.git .
RUN           git checkout $UNBOUND_VERSION

# CoreDNS client
# https://github.com/coredns/client/blob/master/Makefile
WORKDIR       $GOPATH/src/github.com/coredns/client
RUN           git clone https://github.com/coredns/client.git .
RUN           git checkout $COREDNS_CLIENT_VERSION

RUN           arch=${TARGETPLATFORM#*/}; \
              env GOOS=linux GOARCH=${arch%/*} go build -v -ldflags '-s -w' -o dist/dnsgrpc ./cmd/dnsgrpc

# Lego
# https://github.com/go-acme/lego/blob/master/Makefile
WORKDIR       $GOPATH/src/github.com/go-acme/lego
RUN           git clone https://github.com/go-acme/lego.git .
RUN           git checkout $LEGO_VERSION

RUN           arch=${TARGETPLATFORM#*/}; \
              tag_name=$(git tag -l --contains HEAD); \
              env GOOS=linux GOARCH=${arch%/*} go build -v -ldflags "-s -w -X main.version=${tag_name:-$(git rev-parse HEAD)}" -o dist/lego ./cmd/lego

# CoreDNS v1.6.4
# https://github.com/coredns/coredns/blob/master/Makefile
WORKDIR       $GOPATH/src/github.com/coredns/coredns
RUN           git clone https://github.com/coredns/coredns.git .
RUN           git checkout $COREDNS_VERSION

RUN           arch=${TARGETPLATFORM#*/}; \
              commit=$(git describe --dirty --always); \
              if [ "$TARGETPLATFORM" = "$BUILDPLATFORM" ]; then \
                printf "unbound:github.com/coredns/unbound\n" >> plugin.cfg; \
                CGO_ENABLED=1; \
                go generate coredns.go; \
                mkdir -p /dist/usr/lib/$(uname -m)-linux-gnu; \
                cp /usr/lib/$(uname -m)-linux-gnu/libunbound.so.8   /dist/usr/lib/$(uname -m)-linux-gnu; \
                cp /usr/lib/$(uname -m)-linux-gnu/libpthread.so.0   /dist/usr/lib/$(uname -m)-linux-gnu; \
                cp /usr/lib/$(uname -m)-linux-gnu/libc.so.6         /dist/usr/lib/$(uname -m)-linux-gnu; \
                cp /usr/lib/$(uname -m)-linux-gnu/libevent-2.1.so.6 /dist/usr/lib/$(uname -m)-linux-gnu; \
              fi; \
              env GOOS=linux GOARCH=${arch%/*} CGO_ENABLED=$CGO_ENABLED go build -v -ldflags="-s -w -X github.com/coredns/coredns/coremain.GitCommit=$commit" -o dist/coredns

WORKDIR       /dist/bin
RUN           cp $GOPATH/src/github.com/coredns/coredns/dist/coredns  .
RUN           cp $GOPATH/src/github.com/go-acme/lego/dist/lego        .
RUN           cp $GOPATH/src/github.com/coredns/client/dist/dnsgrpc   .
RUN           chmod 555 *

#######################
# Running image
#######################
FROM         dubodubonduponey/base:runtime

# libunbound8=1.9.0-2

# Get relevant bits from builder
COPY        --from=builder /dist .

ENV         DOMAIN=""
ENV         EMAIL="dubo-dubon-duponey@farcloser.world"
ENV         UPSTREAM_SERVER_1=""
ENV         UPSTREAM_SERVER_2=""
ENV         UPSTREAM_NAME=""
ENV         STAGING=""

ENV         DNS_PORT=1053
ENV         TLS_PORT=1853
ENV         HTTPS_PORT=1443
ENV         GRPC_PORT=5553

# NOTE: this will not be updated at runtime and will always EXPOSE default values
# Either way, EXPOSE does not do anything, except function as a documentation helper
EXPOSE      $DNS_PORT/udp
EXPOSE      $TLS_PORT/tcp
EXPOSE      $HTTPS_PORT/tcp
EXPOSE      $GRPC_PORT/tcp

# Lego just needs /certs to work
VOLUME      /certs

HEALTHCHECK --interval=300s --timeout=30s --start-period=10s --retries=1 CMD dnsgrpc dev-null.farcloser.world || exit 1
# CMD dig @127.0.0.1 healthcheck.farcloser.world || exit 1
