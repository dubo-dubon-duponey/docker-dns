#!/usr/bin/env bash

# Generic config management
config::writable(){
  local folder="$1"
  [ -w "$folder" ] || {
    >&2 printf "%s is not writable. Check your mount permissions.\n" "$folder"
    exit 1
  }
}

# Ensure the certs and data folders are writable
config::writable /certs
config::writable /data

# Specifics to the image
DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
HTTPS_PORT="${HTTPS_PORT:-}"
STAGING="${STAGING:-}"

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

config=coredns-no-tls.conf

# If we have a domain, get certificates for that, and the appropriate config
if [ "$DOMAIN" ]; then
  config=coredns.conf

  # Initial registration
  certs::renew "$DOMAIN" "$EMAIL" "$STAGING"

  # Now run in the background to renew 45 days before expiration
  loop "$DOMAIN" "$EMAIL" "$STAGING" &
fi

# Get coredns started - the reload plugin will take care of certificates update
exec coredns -conf /config/"$config" "$@"
