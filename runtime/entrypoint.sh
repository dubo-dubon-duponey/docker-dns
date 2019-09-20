#!/usr/bin/env bash

OVERWRITE_CONFIG=${OVERWRITE_CONFIG:-}

# If no config, try to have the default one, and fail if this fails
if [ ! -e /config/config.conf ] || [ "$OVERWRITE_CONFIG" ]; then
  [ ! -e /config/config.conf ] || >&2 printf "Overwriting configuration file.\n"
  cp config/* /config/ 2>/dev/null || {
    >&2 printf "Failed to create default config file. Permissions issue likely.\n"
    exit 1
  }
fi

exec coredns -conf /config/config.conf "$@"
