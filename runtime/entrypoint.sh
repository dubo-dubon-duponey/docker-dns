#!/usr/bin/env bash

# Generic config management
OVERWRITE_CONFIG=${OVERWRITE_CONFIG:-}
OVERWRITE_DATA=${OVERWRITE_DATA:-}
OVERWRITE_CERTS=${OVERWRITE_CERTS:-}

config::writable(){
  local folder="$1"
  [ -w "$folder" ] || {
    >&2 printf "$folder is not writable. Check your mount permissions.\n"
    exit 1
  }
}

config::setup(){
  local folder="$1"
  local overwrite="$2"
  local f
  local localfolder
  localfolder="$(basename "$folder")"

  # Clean-up if we are to overwrite
  [ ! "$overwrite" ] || rm -Rf "${folder:?}"/*

  # If we have a local source
  if [ -e "$localfolder" ]; then
    # Copy any file in there over the destination if it doesn't exist
    for f in "$localfolder"/*; do
      if [ ! -e "/$f" ]; then
        >&2 printf "(Over-)writing file /$f.\n"
        cp -R "$f" "/$f" 2>/dev/null || {
          >&2 printf "Failed to create file. Permissions issue likely.\n"
          exit 1
        }
      fi
    done
  fi
}

config::writable /certs
config::writable /data
config::setup   /config  "$OVERWRITE_CONFIG"
config::setup   /data    "$OVERWRITE_DATA"
config::setup   /certs   "$OVERWRITE_CERTS"

# ACME
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

# If we have a domain, get certificates for that
if [ "$DOMAIN" ]; then
  # Initial registration
  certs::renew "$DOMAIN" "$EMAIL" "$STAGING"

  # Now run in the background to renew 45 days before expiration
  loop "$DOMAIN" "$EMAIL" "$STAGING" &
fi

# Get coredns started - the reload plugin will take care of certificates update
exec coredns -conf /config/coredns.conf "$@"
