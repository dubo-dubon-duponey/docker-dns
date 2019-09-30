#!/usr/bin/env bash

OVERWRITE_CONFIG=${OVERWRITE_CONFIG:-}

# ACME
DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
HTTPS_PORT="${HTTPS_PORT:-}"
STAGING="${STAGING:-}"

# If no config, try to have the default one, and fail if this fails
if [ ! -e /config/config.conf ] || [ "$OVERWRITE_CONFIG" ]; then
  [ ! -e /config/config.conf ] || >&2 printf "Overwriting configuration file.\n"
  cp config/* /config/ 2>/dev/null || {
    >&2 printf "Failed to create default config file. Permissions issue likely.\n"
    exit 1
  }
fi

legoregister(){
  local domain="$1"
  local email="$2"
  local staging="$3"
  local command="renew --days=45"

  [ ! "$staging" ] || staging="--server=https://acme-staging-v02.api.letsencrypt.org/directory"

  [ -e "/data/certificates/$domain.key" ] || command="run"

  lego  --domains="$domain" \
        --accept-tos --email="$email" --path=/data --tls "$staging" --pem \
        --tls.port=:${HTTPS_PORT} \
        ${command}
}

loop(){
  while true; do
    legoregister "$1" "$2" "$3"
    sleep 86400
  done
}

# If we have a domain, get certificates for that
if [ "$DOMAIN" ]; then
  # Initial registration
  legoregister "$DOMAIN" "$EMAIL" "$STAGING"

  # Now run in the background to renew 45 days before expiration
  loop "$DOMAIN" "$EMAIL" "$STAGING" &
fi

# Get coredns started - the reload plugin will take care of certificates update
exec coredns -conf /config/config.conf "$@"
