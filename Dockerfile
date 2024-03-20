ARG           FROM_REGISTRY=docker.io/dubodubonduponey

ARG           FROM_IMAGE_BUILDER=base:builder-bookworm-2024-03-01
ARG           FROM_IMAGE_AUDITOR=base:auditor-bookworm-2024-03-01
ARG           FROM_IMAGE_RUNTIME=base:runtime-bookworm-2024-03-01
ARG           FROM_IMAGE_TOOLS=tools:linux-bookworm-2024-03-01

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools

#######################
# Fetcher
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-lego

ARG           GIT_REPO=github.com/go-acme/lego
ARG           GIT_VERSION=v4.16.1
ARG           GIT_COMMIT=40dcce60be3dbbd0ae05b789e486341b6741e2ae

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
ARG           GIT_VERSION=v1.11.1
ARG           GIT_COMMIT=ae2bbc29be1aaae0b3ded5d188968a6c97bb3144

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
              go mod tidy -compat=1.17

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
              for architecture in arm64 amd64; do \
                apt-get install -qq --no-install-recommends \
                  libunbound-dev:"$architecture"=1.17.1-2+deb12u2 \
                  nettle-dev:"$architecture"=3.8.1-2 \
                  libevent-dev:"$architecture"=2.1.12-stable-8; \
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

ENV           DNS_OVER_TLS_ENABLED=false
ENV           DNS_OVER_TLS_DOMAIN=""
ENV           DNS_OVER_TLS_PORT=853
ENV           DNS_OVER_TLS_LEGO_PORT=443
ENV           DNS_OVER_TLS_LEGO_EMAIL="dubo-dubon-duponey@farcloser.world"
ENV           DNS_OVER_TLS_LE_USE_STAGING=false

ENV           DNS_FORWARD_ENABLED=true
ENV           DNS_FORWARD_UPSTREAM_NAME="cloudflare-dns.com"
ENV           DNS_FORWARD_UPSTREAM_IP_1="tls://1.1.1.1"
ENV           DNS_FORWARD_UPSTREAM_IP_2="tls://1.0.0.1"

ENV           DNS_PORT=53
# ENV           DNS_OVER_GRPC_PORT=553
ENV           DNS_STUFF_MDNS=false

# XXX cannot be disabled through this variable
ENV           MOD_METRICS_ENABLED=true
ENV           MOD_METRICS_BIND=:4242

# NOTE: this will not be updated at runtime and will always EXPOSE default values
# Either way, EXPOSE does not do anything, except function as a documentation helper
EXPOSE        $DNS_PORT/udp
EXPOSE        $DNS_OVER_TLS_PORT/tcp
EXPOSE        $DNS_OVER_TLS_LEGO_PORT/tcp
#EXPOSE        $DNS_OVER_GRPC_PORT/tcp
EXPOSE        $MOD_METRICS_BIND/tcp

# Lego just needs certs to work
VOLUME        "$XDG_DATA_HOME"

ENV           HEALTHCHECK_URL="127.0.0.1:$DNS_PORT"
ENV           HEALTHCHECK_QUESTION=dns.autonomous.healthcheck.farcloser.world
ENV           HEALTHCHECK_TYPE=udp

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD dns-health || exit 1
