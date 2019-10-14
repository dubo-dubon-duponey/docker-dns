#!/usr/bin/env bash

# Ensure the certs folder is writable
[ -w "/certs" ] || {
  >&2 printf "/certs is not writable. Check your mount permissions.\n"
  exit 1
}

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

  >&2 printf "Running command: %s" "./bin/lego  --domains=\"$domain\" \
        --accept-tos --email=\"$email\" --path=/certs --tls $staging --pem \
        --tls.port=:${HTTPS_PORT} \
        ${command}"

  ./bin/lego  --domains="$domain" \
        --accept-tos --email="$email" --path=/certs --tls ${staging} --pem \
        --tls.port=:${HTTPS_PORT} \
        ${command}
}

loop(){
  while true; do
    certs::renew "$1" "$2" "$3"
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
exec ./bin/coredns -conf /config/coredns${no_tls}-tls-${mode}.conf "$@"
