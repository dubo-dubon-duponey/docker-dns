ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2022-04-01@sha256:d73bb6ea84152c42e314bc9bff6388d0df6d01e277bd238ee0e6f8ade721856d
ARG           FROM_IMAGE_AUDITOR=base:auditor-bullseye-2022-04-01@sha256:ca513bf0219f654afeb2d24aae233fef99cbcb01991aea64060f3414ac792b3f
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2022-04-01@sha256:6456b76dd2eedf34b4c5c997f9ad92901220dfdd405ec63419d0b54b6d85a777
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2022-04-01@sha256:323f3e36da17d8638a07a656e2f17d5ee4dc2b17dfea7e2da36e1b2174cc5f18

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools

#######################
# Fetcher
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-lego

ARG           GIT_REPO=github.com/go-acme/lego
#ARG           GIT_VERSION=v4.5.3
#ARG           GIT_COMMIT=3675fe68aed2c6c99d1f92eb02133ecd9af7b2be
ARG           GIT_VERSION=v4.6.0
ARG           GIT_COMMIT=3ad2fa7acb6d0d88499e8bf5c4b63cc77838ae87

ENV           WITH_BUILD_SOURCE="./cmd/lego"
ENV           WITH_BUILD_OUTPUT="lego"

ENV           CGO_ENABLED=1

RUN           git clone --recurse-submodules https://"$GIT_REPO" .; git checkout "$GIT_COMMIT"
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=NETRC \
              [[ "${GOFLAGS:-}" == *-mod=vendor* ]] || go mod download

#######################
# Lego builder
#######################
FROM          --platform=$BUILDPLATFORM fetcher-lego                                                                    AS builder-lego

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT
ENV           GOOS=$TARGETOS
ENV           GOARCH=$TARGETARCH

ENV           CGO_CFLAGS="${CFLAGS:-} ${ENABLE_PIE:+-fPIE}"
ENV           GOFLAGS="-trimpath ${ENABLE_PIE:+-buildmode=pie} ${GOFLAGS:-}"

RUN           export GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)"; \
              [ "${CGO_ENABLED:-}" != 1 ] || { \
                eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
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

ARG           GIT_REPO=github.com/coredns/coredns
ARG           GIT_VERSION=v1.9.1
ARG           GIT_COMMIT=4b597f8308d8d7cecb538e9831d77117da68c04e

ENV           WITH_BUILD_SOURCE=./coredns.go
ENV           WITH_BUILD_OUTPUT=coredns
ENV           WITH_LDFLAGS="-X $GIT_REPO/coremain.GitCommit=$GIT_COMMIT"

ENV           CGO_ENABLED=1

RUN           git clone --recurse-submodules https://"$GIT_REPO" .; git checkout "$GIT_COMMIT"
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=NETRC \
              [[ "${GOFLAGS:-}" == *-mod=vendor* ]] || go mod download; \
              printf "mdns:github.com/openshift/coredns-mdns\n" >> plugin.cfg; \
              printf "unbound:github.com/coredns/unbound\n" >> plugin.cfg; \
              go generate coredns.go; \
              go mod tidy
# XXX how to pin that?

# hadolint ignore=DL3009
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
FROM          --platform=$BUILDPLATFORM fetcher-coredns                                                                    AS builder-coredns

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT
ENV           GOOS=$TARGETOS
ENV           GOARCH=$TARGETARCH

ENV           CGO_CFLAGS="${CFLAGS:-} ${ENABLE_PIE:+-fPIE}"
ENV           GOFLAGS="-trimpath ${ENABLE_PIE:+-buildmode=pie} ${GOFLAGS:-}"

RUN           export GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)"; \
              [ "${CGO_ENABLED:-}" != 1 ] || { \
                eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
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
              eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
              cp /usr/lib/"$DEB_TARGET_MULTIARCH"/libunbound.so.8    /dist/boot/lib; \
              cp /usr/lib/"$DEB_TARGET_MULTIARCH"/libevent-2.1.so.7  /dist/boot/lib


# XXX whether or not we want these in depends on how slick we want the future runtime
#              cp /lib/"$DEB_TARGET_MULTIARCH"/libpthread.so.0        /dist/boot/lib; \
#              cp /lib/"$DEB_TARGET_MULTIARCH"/libc.so.6              /dist/boot/lib; \



#              go get github.com/coredns/unbound; \

#######################
# Builder assembly, XXX should be auditor
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_AUDITOR                                              AS builder

COPY          --from=builder-lego     /dist           /dist
COPY          --from=builder-coredns  /dist           /dist

COPY          --from=builder-tools  /boot/bin/dns-health    /dist/boot/bin

RUN           cp /dist/boot/bin/coredns /dist/boot/bin/coredns_no_cap
RUN           cp /dist/boot/bin/coredns /dist/boot/bin/coredns_cap+origin
RUN           setcap 'cap_net_bind_service+ep'                /dist/boot/bin/coredns_cap+origin
# hadolint ignore=SC2016
RUN           patchelf --set-rpath '$ORIGIN/../lib'           /dist/boot/bin/coredns_cap+origin
# hadolint ignore=SC2016
RUN           patchelf --set-rpath '$ORIGIN/../lib'           /dist/boot/bin/coredns_no_cap

# XXX https://mail.openjdk.java.net/pipermail/distro-pkg-dev/2010-May/009112.html
# no $ORIGIN rpath expansion with caps
RUN           patchelf --set-rpath '/boot/lib'           /dist/boot/bin/coredns
RUN           patchelf --set-rpath '/boot/lib'           /dist/boot/lib/*
RUN           patchelf --set-rpath '/boot/lib'           /dist/boot/bin/lego

RUN           setcap 'cap_net_bind_service+ep'                /dist/boot/bin/coredns

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
