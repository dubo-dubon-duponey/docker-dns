#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null 1>&2 && pwd)"
readonly root
# shellcheck source=/dev/null
source "$root/helpers.sh"
# shellcheck source=/dev/null
source "$root/mdns.sh"

helpers::dir::writable /certs

# mDNS blast if asked to
# XXX informative only, but look into that, and which port to broadcast or not
#[ ! "${MDNS_HOST:-}" ] || {
#  [ ! "${MDNS_STATION:-}" ] || mdns::records::add "_workstation._tcp" "$MDNS_HOST" "${MDNS_NAME:-}" "22"
#  mdns::records::add "${MDNS_TYPE:-_http._tcp}" "$MDNS_HOST" "${MDNS_NAME:-}" "22"
#  mdns::records::broadcast &
#}

DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
HTTPS_PORT="${HTTPS_PORT:-}"
STAGING="${STAGING:-}"
UPSTREAM_NAME="${UPSTREAM_NAME:-}"

certs::renew(){
  local domain="$1"
  local email="$2"
  local staging="$3"
  local command="renew --days=45"

  [ ! "$staging" ] || staging="--server=https://acme-staging-v02.api.letsencrypt.org/directory"

  [ -e "/certs/certificates/$domain.key" ] || command="run"

  printf >&2 "Running command: %s" "lego  --domains=\"$domain\" \
        --accept-tos --email=\"$email\" --path=/certs --tls $staging --pem \
        --tls.port=:${HTTPS_PORT} \
        ${command}"

  lego  --domains="$domain" \
        --accept-tos --email="$email" --path=/certs --tls ${staging} --pem \
        --tls.port=:"${HTTPS_PORT}" \
        ${command}
}

loop(){
  while true; do
    certs::renew "$1" "$2" "$3"
    # signal coredns to reload config - technically happens once a day, which is not optimal, but fine
    kill -s SIGUSR1 1
    sleep 86400
  done
}

# If we have a domain, get certificates for that, and the appropriate config
if [ "$DOMAIN" ]; then
  # Initial registration
  certs::renew "$DOMAIN" "$EMAIL" "$STAGING"

  # Now run in the background to renew 45 days before expiration
  loop "$DOMAIN" "$EMAIL" "$STAGING" &
fi

# Choose config based on environment values
[ "$DOMAIN" ]         && no_tls=      || no_tls=-no
[ "$UPSTREAM_NAME" ]  && mode=forward || mode=recursive

# Get coredns started
exec coredns -conf /config/coredns${no_tls}-tls-${mode}.conf "$@"
