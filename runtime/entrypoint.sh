#!/usr/bin/env bash

# If no config, try to have the default one, and fail if this fails
[ -e /config/config.conf ] || cp config/* /config/ || {
  >&2 printf "Failed to create default config file. Permissions issue likely.\n"
  exit 1
}

exec coredns -conf /config/config.conf "$@"
