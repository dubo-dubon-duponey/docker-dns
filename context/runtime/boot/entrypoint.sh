#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null 1>&2 && pwd)"
readonly root
# shellcheck source=/dev/null
source "$root/helpers.sh"

helpers::dir::writable /certs

# DNS over tls settings
DNS_OVER_TLS_ENABLED="${DNS_OVER_TLS_ENABLED:-}"
DNS_OVER_TLS_DOMAIN="${DNS_OVER_TLS_DOMAIN:-}"
DNS_OVER_TLS_PORT="${DNS_OVER_TLS_PORT:-}"
DNS_OVER_TLS_LEGO_PORT="${DNS_OVER_TLS_LEGO_PORT:-}"
DNS_OVER_TLS_LEGO_EMAIL="${DNS_OVER_TLS_LEGO_EMAIL:-}"
DNS_OVER_TLS_LE_USE_STAGING="${DNS_OVER_TLS_LE_USE_STAGING:-}"

# Forward settings
DNS_FORWARD_ENABLED="${DNS_FORWARD_ENABLED:-}"
DNS_FORWARD_UPSTREAM_NAME="${DNS_FORWARD_UPSTREAM_NAME:-}"
DNS_FORWARD_UPSTREAM_IP_1="${DNS_FORWARD_UPSTREAM_IP_1:-}"
DNS_FORWARD_UPSTREAM_IP_2="${DNS_FORWARD_UPSTREAM_IP_2:-}"

# Other DNS settings
DNS_PORT="${DNS_PORT:-}"
DNS_OVER_GRPC_PORT="${DNS_OVER_GRPC_PORT:-}"
DNS_STUFF_MDNS="${DNS_STUFF_MDNS:-}"

# Metrics settings
METRICS_PORT="${METRICS_PORT:-}"

certs::renew(){
  local domain="$1"
  local email="$2"
  local port="$3"
  local staging="$4"
  local command="renew --days=45"

  [ "$staging" != true ] \
    && staging= \
    || staging="--server=https://acme-staging-v02.api.letsencrypt.org/directory"

  [ -e "/certs/certificates/$domain.key" ] || command="run"

  printf >&2 "Running command: %s" "lego  --domains=\"$domain\" \
        --accept-tos --email=\"$email\" --path=/certs --tls $staging --pem \
        --tls.port=:$port \
        ${command}"

  lego  --domains="$domain" \
        --accept-tos \
        --email="$email" \
        --path=/certs \
        --tls $staging --pem \
        --tls.port=:"$port" \
        ${command}
}

loop(){
  while true; do
    sleep 86400
    certs::renew "$@"
    # signal coredns to reload config - technically happens once a day, which is not optimal, but fine
    kill -s SIGUSR1 1
  done
}

no_tls=-no
# If we have a domain, get certificates for that, and the appropriate config
if [ "$DNS_OVER_TLS_ENABLED" == true ]; then
  no_tls=

  # Initial registration, blocking
  certs::renew "$DNS_OVER_TLS_DOMAIN" "$DNS_OVER_TLS_LEGO_EMAIL" "$DNS_OVER_TLS_PORT" "$DNS_OVER_TLS_LE_USE_STAGING"

  # Now run in the background to renew 45 days before expiration
  loop "$DNS_OVER_TLS_DOMAIN" "$DNS_OVER_TLS_LEGO_EMAIL" "$DNS_OVER_TLS_PORT" "$DNS_OVER_TLS_LE_USE_STAGING" &
fi

# Choose config based on environment values
[ "$DNS_FORWARD_ENABLED" == true ]  && mode=forward || mode=recursive
[ "$DNS_STUFF_MDNS" == true ]  && mod=-mdns || mod=

# Get coredns started
exec coredns -conf /config/coredns${no_tls}-tls-${mode}${mod}.conf "$@"
