ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-07-01@sha256:f1c46316c38cc1ca54fd53b54b73797b35ba65ee727beea1a5ed08d0ad7e8ccf
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-07-01@sha256:9f5b20d392e1a1082799b3befddca68cee2636c72c502aa7652d160896f85b36
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-07-01@sha256:f1e25694fe933c7970773cb323975bb5c995fa91d0c1a148f4f1c131cbc5872c

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools

#######################
# Fetcher
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-lego

ENV           GIT_REPO=github.com/go-acme/lego
ENV           GIT_VERSION=4.2.0
ENV           GIT_COMMIT=52e6721dca65e1618067db242a61baf523140b71

ENV           WITH_BUILD_SOURCE="./cmd/lego"
ENV           WITH_BUILD_OUTPUT="lego"

ENV           CGO_ENABLED=1

RUN           git clone --recurse-submodules git://"$GIT_REPO" .
RUN           git checkout "$GIT_COMMIT"
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=NETRC \
              [[ "${GOFLAGS:-}" == *-mod=vendor* ]] || go mod download

#######################
# Lego builder
#######################
FROM          --platform=$BUILDPLATFORM fetcher-main                                                                    AS builder-lego

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT
ENV           GOOS=$TARGETOS
ENV           GOARCH=$TARGETARCH

ENV           CGO_CFLAGS="${CFLAGS:-} ${ENABLE_PIE:+-fPIE}"
ENV           GOFLAGS="-trimpath ${ENABLE_PIE:+-buildmode=pie} ${GOFLAGS:-}"

# Important cases being handled:
# - cannot compile statically with PIE but on amd64 and arm64
# - cannot compile fully statically with NETCGO
RUN           export GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)"; \
              [ "${CGO_ENABLED:-}" != 1 ] || { \
                eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/armv6/armel/" -e "s/armv7/armhf/" -e "s/ppc64le/ppc64el/" -e "s/386/i386/")")"; \
                export PKG_CONFIG="${DEB_TARGET_GNU_TYPE}-pkg-config"; \
                export AR="${DEB_TARGET_GNU_TYPE}-ar"; \
                export CC="${DEB_TARGET_GNU_TYPE}-gcc"; \
                export CXX="${DEB_TARGET_GNU_TYPE}-g++"; \
                [ ! "${ENABLE_STATIC:-}" ] || { \
                  [ ! "${WITH_CGO_NET:-}" ] || { \
                    ENABLE_STATIC=; \
                    LDFLAGS="${LDFLAGS:-} -static-libgcc -static-libstdc++"; \
                  }; \
                  [ "$GOARCH" == "amd64" ] || [ "$GOARCH" == "arm64" ] || [ "${ENABLE_PIE:-}" != true ] || ENABLE_STATIC=; \
                }; \
                WITH_LDFLAGS="${WITH_LDFLAGS:-} -linkmode=external -extld="$CC" -extldflags \"${LDFLAGS:-} ${ENABLE_STATIC:+-static}${ENABLE_PIE:+-pie}\""; \
                WITH_TAGS="${WITH_TAGS:-} cgo ${ENABLE_STATIC:+static static_build}"; \
              }; \
              go build -ldflags "-s -w -v ${WITH_LDFLAGS:-}" -tags "${WITH_TAGS:-} net${WITH_CGO_NET:+c}go osusergo" -o /dist/boot/bin/"$WITH_BUILD_OUTPUT" "$WITH_BUILD_SOURCE"

#######################
# Fetcher
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-coredns

ENV           GIT_REPO=github.com/coredns/coredns
ENV           GIT_VERSION=1.8.4
ENV           GIT_COMMIT=053c4d5ca1772517746a854e87ffa971249df14b

ENV           WITH_BUILD_SOURCE=./coredns.go
ENV           WITH_BUILD_OUTPUT=coredns
ENV           WITH_LDFLAGS="-X $GIT_REPO/coremain.GitCommit=$GIT_COMMIT"

ENV           CGO_ENABLED=1

RUN           git clone --recurse-submodules git://"$GIT_REPO" .
RUN           git checkout "$GIT_COMMIT"
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=NETRC \
              [[ "${GOFLAGS:-}" == *-mod=vendor* ]] || go mod download; \
              printf "mdns:github.com/openshift/coredns-mdns\n" >> plugin.cfg; \
              printf "unbound:github.com/coredns/unbound\n" >> plugin.cfg; \
              go generate coredns.go; \
              go mod tidy
# XXX how to pin that?

RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              apt-get update -qq; \
              for architecture in armel armhf arm64 ppc64el i386 s390x amd64; do \
                apt-get install -qq --no-install-recommends \
                  libunbound-dev:"$architecture"=1.13.1-1 \
                  nettle-dev:"$architecture"=3.7.3-1 \
                  libevent-dev:"$architecture"=2.1.12-stable-1; \
              done

##########################
# Builder custom
##########################
FROM          --platform=$BUILDPLATFORM fetcher-main                                                                    AS builder-coredns

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT
ENV           GOOS=$TARGETOS
ENV           GOARCH=$TARGETARCH

ENV           CGO_CFLAGS="${CFLAGS:-} ${ENABLE_PIE:+-fPIE}"
ENV           GOFLAGS="-trimpath ${ENABLE_PIE:+-buildmode=pie} ${GOFLAGS:-}"

# Important cases being handled:
# - cannot compile statically with PIE but on amd64 and arm64
# - cannot compile fully statically with NETCGO
RUN           export GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)"; \
              [ "${CGO_ENABLED:-}" != 1 ] || { \
                eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/armv6/armel/" -e "s/armv7/armhf/" -e "s/ppc64le/ppc64el/" -e "s/386/i386/")")"; \
                export PKG_CONFIG="${DEB_TARGET_GNU_TYPE}-pkg-config"; \
                export AR="${DEB_TARGET_GNU_TYPE}-ar"; \
                export CC="${DEB_TARGET_GNU_TYPE}-gcc"; \
                export CXX="${DEB_TARGET_GNU_TYPE}-g++"; \
                [ ! "${ENABLE_STATIC:-}" ] || { \
                  [ ! "${WITH_CGO_NET:-}" ] || { \
                    ENABLE_STATIC=; \
                    LDFLAGS="${LDFLAGS:-} -static-libgcc -static-libstdc++"; \
                  }; \
                  [ "$GOARCH" == "amd64" ] || [ "$GOARCH" == "arm64" ] || [ "${ENABLE_PIE:-}" != true ] || ENABLE_STATIC=; \
                }; \
                WITH_LDFLAGS="${WITH_LDFLAGS:-} -linkmode=external -extld="$CC" -extldflags \"${LDFLAGS:-} ${ENABLE_STATIC:+-static}${ENABLE_PIE:+-pie}\""; \
                WITH_TAGS="${WITH_TAGS:-} cgo ${ENABLE_STATIC:+static static_build}"; \
              }; \
              go build -ldflags "-s -w -v ${WITH_LDFLAGS:-}" -tags "${WITH_TAGS:-} net${WITH_CGO_NET:+c}go osusergo" -o /dist/boot/bin/"$WITH_BUILD_OUTPUT" "$WITH_BUILD_SOURCE"

RUN           mkdir -p /dist/boot/lib; \
              cp /usr/lib/"$DEB_TARGET_GNU_TYPE"/libunbound.so.8    /dist/boot/lib; \
              cp /lib/"$DEB_TARGET_GNU_TYPE"/libpthread.so.0        /dist/boot/lib; \
              cp /lib/"$DEB_TARGET_GNU_TYPE"/libc.so.6              /dist/boot/lib; \
              cp /usr/lib/"$DEB_TARGET_GNU_TYPE"/libevent-2.1.so.7  /dist/boot/lib

#              go get github.com/coredns/unbound; \

#######################
# Builder assembly, XXX should be auditor
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS builder

COPY          --from=builder-lego     /dist           /dist
COPY          --from=builder-coredns  /dist           /dist

COPY          --from=builder-tools  /boot/bin/dns-health    /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME

# Get relevant bits from builder
COPY          --from=builder --chown=$BUILD_UID:root /dist /

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
