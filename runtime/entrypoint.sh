#!/usr/bin/env bash

OVERWRITE_CONFIG=${OVERWRITE_CONFIG:-}

# ACME
DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
HTTPS_PORT="${HTTPS_PORT:-}"
STAGING="${STAGING:-}"

certs::sanity(){
  [ -w /certs ] || {
    >&2 printf "/certs is not writable.\n"
    exit 1
  }
}

config::setup(){
  # If no config, try to have the default one, and fail if this fails
  if [ ! -e /config/config.conf ] || [ "$OVERWRITE_CONFIG" ]; then
    [ ! -e /config/config.conf ] || >&2 printf "Overwriting configuration file.\n"
    cp config/* /config/ 2>/dev/null || {
      >&2 printf "Failed to create default config file. Permissions issue likely.\n"
      exit 1
    }
  fi
}

certs::renew(){
  local domain="$1"
  local email="$2"
  local staging="$3"
  local command="renew --days=45"

  [ ! "$staging" ] || staging="--server=https://acme-staging-v02.api.letsencrypt.org/directory"

  [ -e "/certs/certificates/$domain.key" ] || command="run"

  >&2 printf "Running command: %s" "lego  --domains=\"$domain\" \
        --accept-tos --email=\"$email\" --path=/certs --tls $staging --pem \
        --tls.port=:${HTTPS_PORT} \
        ${command}"

  lego  --domains="$domain" \
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

certs::sanity
config::setup

# If we have a domain, get certificates for that
if [ "$DOMAIN" ]; then
  # Initial registration
  certs::renew "$DOMAIN" "$EMAIL" "$STAGING"

  # Now run in the background to renew 45 days before expiration
  loop "$DOMAIN" "$EMAIL" "$STAGING" &
fi

# Get coredns started - the reload plugin will take care of certificates update
exec coredns -conf /config/config.conf "$@"
